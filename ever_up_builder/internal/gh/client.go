package gh

import (
	"bytes"
	"fmt"
	"os/exec"
	"regexp"
	"strings"
)

// CommandRunner defines the function signature for executing gh commands.
type CommandRunner func(dir string, stdin string, name string, args ...string) (stdout []byte, stderr []byte, exitCode int, err error)

// AuthStatus encapsulates the parsed authentication state of the gh CLI.
type AuthStatus struct {
	IsLoggedIn bool   `json:"is_logged_in"`
	Account    string `json:"account,omitempty"`
	Host       string `json:"host,omitempty"`
	Message    string `json:"message,omitempty"`
}

// LookPathFunc defines the function signature for locating executables in PATH.
type LookPathFunc func(file string) (string, error)

// Client provides GitHub CLI integration for EverUp.
type Client struct {
	Dir      string
	Runner   CommandRunner
	LookPath LookPathFunc
}

// DefaultRunner executes real system commands via os/exec.
func DefaultRunner(dir string, stdin string, name string, args ...string) ([]byte, []byte, int, error) {
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	if stdin != "" {
		cmd.Stdin = strings.NewReader(stdin)
	}
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()
	exitCode := 0
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			exitCode = exitErr.ExitCode()
		} else {
			exitCode = 1
		}
	}
	return stdout.Bytes(), stderr.Bytes(), exitCode, err
}

// NewClient creates a new Client configured for the specified working directory.
func NewClient(dir string) *Client {
	return &Client{
		Dir:      dir,
		Runner:   DefaultRunner,
		LookPath: exec.LookPath,
	}
}

// WithRunner returns a copy of the client with a custom runner.
// Also defaults LookPath to succeed so unit tests do not depend on the host PATH.
func (c *Client) WithRunner(runner CommandRunner) *Client {
	return &Client{
		Dir:    c.Dir,
		Runner: runner,
		LookPath: func(file string) (string, error) {
			return "/mock/" + file, nil
		},
	}
}

// WithLookPath returns a copy of the client with a custom look path resolver.
func (c *Client) WithLookPath(lp LookPathFunc) *Client {
	return &Client{
		Dir:      c.Dir,
		Runner:   c.Runner,
		LookPath: lp,
	}
}

// CheckInstalled checks whether the gh binary is discoverable in PATH.
func (c *Client) CheckInstalled() error {
	lp := c.LookPath
	if lp == nil {
		lp = exec.LookPath
	}
	_, err := lp("gh")
	if err != nil {
		return fmt.Errorf("GitHub CLI (gh) is not installed. Install it from https://cli.github.com")
	}
	return nil
}

// CheckAuth inspects the gh authentication status using 'gh auth status'.
func (c *Client) CheckAuth() (*AuthStatus, error) {
	if err := c.CheckInstalled(); err != nil {
		return &AuthStatus{
			IsLoggedIn: false,
			Message:    err.Error(),
		}, err
	}

	stdout, stderr, exitCode, err := c.Runner(c.Dir, "", "gh", "auth", "status")
	combined := string(stdout) + "\n" + string(stderr)

	status := &AuthStatus{
		IsLoggedIn: exitCode == 0,
		Message:    strings.TrimSpace(combined),
	}

	// Parse host if found (e.g. github.com or github.mycompany.com)
	if hostMatch := regexp.MustCompile(`(?m)^([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})`).FindStringSubmatch(combined); len(hostMatch) > 1 {
		status.Host = hostMatch[1]
	} else {
		status.Host = "github.com"
	}

	// Parse account username (supports both 'account <username>' and legacy 'as <username>')
	if accMatch := regexp.MustCompile(`(?i)(?:account|as)\s+([a-zA-Z0-9_.-]+)`).FindStringSubmatch(combined); len(accMatch) > 1 {
		status.Account = accMatch[1]
	}

	if !status.IsLoggedIn {
		return status, fmt.Errorf("GitHub CLI is not authenticated (run 'gh auth login' to authenticate): %s", strings.TrimSpace(combined))
	}

	return status, err
}

// GetRepository retrieves the current repository in owner/repo format.
func (c *Client) GetRepository() (string, error) {
	stdout, stderr, exitCode, err := c.Runner(c.Dir, "", "gh", "repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner")
	if exitCode != 0 || err != nil {
		return "", fmt.Errorf("failed to detect GitHub repository: %s", strings.TrimSpace(string(stderr)))
	}
	return strings.TrimSpace(string(stdout)), nil
}

// SetSecret creates or updates a repository secret with the given name and string value.
func (c *Client) SetSecret(secretName, secretValue string) error {
	stdout, stderr, exitCode, err := c.Runner(c.Dir, secretValue, "gh", "secret", "set", secretName)
	if exitCode != 0 || err != nil {
		out := strings.TrimSpace(string(stdout) + " " + string(stderr))
		return fmt.Errorf("gh secret set %s failed: %s", secretName, out)
	}
	return nil
}

// ListSecrets returns the names of all secrets registered in the repository.
func (c *Client) ListSecrets() ([]string, error) {
	stdout, stderr, exitCode, err := c.Runner(c.Dir, "", "gh", "secret", "list", "--json", "name", "-q", ".[].name")
	if exitCode != 0 || err != nil {
		return nil, fmt.Errorf("gh secret list failed: %s", strings.TrimSpace(string(stderr)))
	}
	lines := strings.Split(strings.TrimSpace(string(stdout)), "\n")
	var names []string
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if trimmed != "" {
			names = append(names, trimmed)
		}
	}
	return names, nil
}
