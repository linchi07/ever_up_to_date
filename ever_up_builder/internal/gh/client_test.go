package gh

import (
	"fmt"
	"strings"
	"testing"
)

func TestCheckAuth_LoggedIn(t *testing.T) {
	mockRunner := func(dir string, stdin string, name string, args ...string) ([]byte, []byte, int, error) {
		if name != "gh" {
			t.Fatalf("expected binary gh, got %s", name)
		}
		if len(args) == 2 && args[0] == "auth" && args[1] == "status" {
			output := `github.com
  ✓ Logged in to github.com account linchi07 (keyring)
  - Active account: true
  - Git operations protocol: https
  - Token: gho_************************************`
			return []byte(output), nil, 0, nil
		}
		t.Fatalf("unexpected args: %v", args)
		return nil, nil, 1, nil
	}

	client := NewClient(".").WithRunner(mockRunner)
	status, err := client.CheckAuth()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !status.IsLoggedIn {
		t.Fatalf("expected IsLoggedIn true")
	}
	if status.Account != "linchi07" {
		t.Errorf("expected account linchi07, got %q", status.Account)
	}
	if status.Host != "github.com" {
		t.Errorf("expected host github.com, got %q", status.Host)
	}
}

func TestCheckAuth_LegacyOutput(t *testing.T) {
	mockRunner := func(dir string, stdin string, name string, args ...string) ([]byte, []byte, int, error) {
		output := `github.com
  ✓ Logged in to github.com as octocat-developer (/Users/octocat/.config/gh/hosts.yml)
  - Git operations protocol: ssh
  - Token: gho_************************************`
		return []byte(output), nil, 0, nil
	}

	client := NewClient(".").WithRunner(mockRunner)
	status, err := client.CheckAuth()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !status.IsLoggedIn {
		t.Fatalf("expected IsLoggedIn true")
	}
	if status.Account != "octocat-developer" {
		t.Errorf("expected account octocat-developer, got %q", status.Account)
	}
}

func TestCheckAuth_EnterpriseHost(t *testing.T) {
	mockRunner := func(dir string, stdin string, name string, args ...string) ([]byte, []byte, int, error) {
		output := `github.mycompany.internal
  ✓ Logged in to github.mycompany.internal account dev_ops (keyring)
  - Active account: true`
		return []byte(output), nil, 0, nil
	}

	client := NewClient(".").WithRunner(mockRunner)
	status, err := client.CheckAuth()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status.Host != "github.mycompany.internal" {
		t.Errorf("expected host github.mycompany.internal, got %q", status.Host)
	}
	if status.Account != "dev_ops" {
		t.Errorf("expected account dev_ops, got %q", status.Account)
	}
}

func TestCheckAuth_NotInstalled(t *testing.T) {
	client := NewClient(".").WithLookPath(func(file string) (string, error) {
		return "", fmt.Errorf("file not found in PATH")
	})
	status, err := client.CheckAuth()
	if err == nil {
		t.Fatalf("expected error when gh is not installed")
	}
	if status.IsLoggedIn {
		t.Fatalf("expected IsLoggedIn false")
	}
	if !strings.Contains(err.Error(), "GitHub CLI (gh) is not installed") {
		t.Errorf("unexpected error message: %v", err)
	}
}

func TestCheckAuth_NotLoggedIn(t *testing.T) {
	mockRunner := func(dir string, stdin string, name string, args ...string) ([]byte, []byte, int, error) {
		output := `github.com
  X Failed to log in to github.com account linchi07 (default)
  - The token in default is invalid.
  - To re-authenticate, run: gh auth login -h github.com`
		return nil, []byte(output), 1, nil
	}

	client := NewClient(".").WithRunner(mockRunner)
	status, err := client.CheckAuth()
	if err == nil {
		t.Fatalf("expected error when not logged in")
	}
	if status.IsLoggedIn {
		t.Fatalf("expected IsLoggedIn false")
	}
	if !strings.Contains(err.Error(), "gh auth login") {
		t.Errorf("expected guidance to run gh auth login in error: %v", err)
	}
}

func TestSetSecret(t *testing.T) {
	var capturedStdin string
	var capturedArgs []string

	mockRunner := func(dir string, stdin string, name string, args ...string) ([]byte, []byte, int, error) {
		capturedStdin = stdin
		capturedArgs = args
		return []byte("✓ Set secret EVERUP_COMMON_SECRETS for repo"), nil, 0, nil
	}

	client := NewClient(".").WithRunner(mockRunner)
	err := client.SetSecret("EVERUP_COMMON_SECRETS", `{"s3_bucket":"test"}`)
	if err != nil {
		t.Fatalf("SetSecret failed: %v", err)
	}

	if len(capturedArgs) < 3 || capturedArgs[0] != "secret" || capturedArgs[1] != "set" || capturedArgs[2] != "EVERUP_COMMON_SECRETS" {
		t.Errorf("unexpected args: %v", capturedArgs)
	}
	if capturedStdin != `{"s3_bucket":"test"}` {
		t.Errorf("unexpected stdin: %q", capturedStdin)
	}
}

func TestGetRepository(t *testing.T) {
	mockRunner := func(dir string, stdin string, name string, args ...string) ([]byte, []byte, int, error) {
		return []byte("linchi07/ever_up_to_date\n"), nil, 0, nil
	}

	client := NewClient(".").WithRunner(mockRunner)
	repo, err := client.GetRepository()
	if err != nil {
		t.Fatalf("GetRepository failed: %v", err)
	}
	if repo != "linchi07/ever_up_to_date" {
		t.Errorf("expected repo linchi07/ever_up_to_date, got %q", repo)
	}
}

func TestListSecrets(t *testing.T) {
	mockRunner := func(dir string, stdin string, name string, args ...string) ([]byte, []byte, int, error) {
		return []byte("EVERUP_COMMON_SECRETS\nEVERUP_ANDROID_SECRETS\n"), nil, 0, nil
	}

	client := NewClient(".").WithRunner(mockRunner)
	list, err := client.ListSecrets()
	if err != nil {
		t.Fatalf("ListSecrets failed: %v", err)
	}
	if len(list) != 2 || list[0] != "EVERUP_COMMON_SECRETS" || list[1] != "EVERUP_ANDROID_SECRETS" {
		t.Errorf("unexpected secret list: %v", list)
	}
}
