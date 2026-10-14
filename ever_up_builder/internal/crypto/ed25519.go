package crypto

import (
	"crypto/ed25519"
	"encoding/base64"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
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
	return SetGitHubSecretAt(".", secretName, secretValue)
}

func SetGitHubSecretAt(root, secretName, secretValue string) error {
	cmd := exec.Command("gh", "secret", "set", secretName)
	cmd.Dir = root
	cmd.Stdin = strings.NewReader(secretValue)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("gh secret set failed: %s (%w)", strings.TrimSpace(string(out)), err)
	}
	return nil
}

// EnsureKeyPair preserves existing keys across repeated initialization.
func EnsureKeyPair(root string) (*KeyPair, error) {
	directory := filepath.Join(root, ".everup")
	if err := os.MkdirAll(directory, 0700); err != nil {
		return nil, err
	}
	ignore := filepath.Join(root, ".gitignore")
	existing, err := os.ReadFile(ignore)
	if err != nil && !os.IsNotExist(err) {
		return nil, err
	}
	if !strings.Contains(string(existing), "/.everup/") {
		if err := os.WriteFile(ignore, append(existing, []byte("\n/.everup/\n")...), 0644); err != nil {
			return nil, err
		}
	}
	privatePath := filepath.Join(directory, "signing-private.key")
	data, err := os.ReadFile(privatePath)
	var pair *KeyPair
	if err == nil {
		private, err := base64.StdEncoding.DecodeString(strings.TrimSpace(string(data)))
		if err != nil || len(private) != ed25519.PrivateKeySize {
			return nil, fmt.Errorf("invalid saved private key")
		}
		derived := ed25519.NewKeyFromSeed(private[:ed25519.SeedSize])
		if !ed25519.PrivateKey(private).Equal(derived) {
			return nil, fmt.Errorf("inconsistent saved private key")
		}
		pair = &KeyPair{PublicKey: base64.StdEncoding.EncodeToString(derived.Public().(ed25519.PublicKey)), PrivateKey: base64.StdEncoding.EncodeToString(derived)}
		if err := os.Chmod(privatePath, 0600); err != nil {
			return nil, err
		}
	} else if os.IsNotExist(err) {
		pair, err = GenerateEd25519KeyPair()
		if err != nil {
			return nil, err
		}
		file, err := os.OpenFile(privatePath, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
		if err != nil {
			return nil, err
		}
		if _, err := file.WriteString(pair.PrivateKey + "\n"); err != nil {
			file.Close()
			return nil, err
		}
		if err := file.Close(); err != nil {
			return nil, err
		}
	} else {
		return nil, err
	}
	if err := os.WriteFile(filepath.Join(directory, "signing-public.key"), []byte(pair.PublicKey+"\n"), 0644); err != nil {
		return nil, err
	}
	return pair, nil
}
