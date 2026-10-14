package crypto

import (
	"crypto/ed25519"
	"encoding/base64"
	"fmt"
	"os/exec"
	"strings"
)

// KeyPair represents a Base64-encoded Ed25519 public and private key.
type KeyPair struct {
	PublicKey  string
	PrivateKey string
}

// GenerateEd25519KeyPair generates a new random Ed25519 key pair.
func GenerateEd25519KeyPair() (*KeyPair, error) {
	pub, priv, err := ed25519.GenerateKey(nil)
	if err != nil {
		return nil, fmt.Errorf("failed to generate Ed25519 key: %w", err)
	}

	return &KeyPair{
		PublicKey:  base64.StdEncoding.EncodeToString(pub),
		PrivateKey: base64.StdEncoding.EncodeToString(priv),
	}, nil
}

// IsGhAvailable checks if GitHub CLI is installed on the host.
func IsGhAvailable() bool {
	_, err := exec.LookPath("gh")
	return err == nil
}

// SetGitHubSecret sets a secret in the current GitHub repository using gh CLI.
func SetGitHubSecret(secretName, secretValue string) error {
	cmd := exec.Command("gh", "secret", "set", secretName, "-b", secretValue)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("gh secret set failed: %s (%w)", strings.TrimSpace(string(out)), err)
	}
	return nil
}
