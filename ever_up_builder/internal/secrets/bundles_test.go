package secrets

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"ever_up_builder/internal/model"
)

func TestGenerateSecretTemplates(t *testing.T) {
	root := t.TempDir()

	// Write mock private key in .everup/
	everupDir := filepath.Join(root, ".everup")
	if err := os.MkdirAll(everupDir, 0700); err != nil {
		t.Fatal(err)
	}
	mockKey := "mock_private_key_base64"
	if err := os.WriteFile(filepath.Join(everupDir, "signing-private.key"), []byte(mockKey+"\n"), 0600); err != nil {
		t.Fatal(err)
	}

	cfg := model.DefaultConfig()
	cfg.EnableAndroid = true
	cfg.EnableWindows = true
	cfg.EnableMacOS = false

	bundles := GenerateSecretTemplates(root, cfg)

	// Check EVERUP_COMMON_SECRETS
	commonRaw, ok := bundles["EVERUP_COMMON_SECRETS"]
	if !ok {
		t.Fatal("missing EVERUP_COMMON_SECRETS")
	}
	var common CommonSecrets
	if err := json.Unmarshal([]byte(commonRaw), &common); err != nil {
		t.Fatalf("failed to parse common secrets JSON: %v", err)
	}
	if common.SigningPrivateKey != mockKey {
		t.Errorf("expected signing_private_key %q, got %q", mockKey, common.SigningPrivateKey)
	}

	// Check EVERUP_ANDROID_SECRETS
	if _, ok := bundles["EVERUP_ANDROID_SECRETS"]; !ok {
		t.Fatal("missing EVERUP_ANDROID_SECRETS")
	}

	// Check EVERUP_WINDOWS_SECRETS
	if _, ok := bundles["EVERUP_WINDOWS_SECRETS"]; !ok {
		t.Fatal("missing EVERUP_WINDOWS_SECRETS")
	}

	// EVERUP_MACOS_SECRETS should not be present because EnableMacOS is false
	if _, ok := bundles["EVERUP_MACOS_SECRETS"]; ok {
		t.Fatal("EVERUP_MACOS_SECRETS should not be present")
	}

	summary := FormatSecretsSummary(bundles)
	if !strings.Contains(summary, "EVERUP_COMMON_SECRETS") || !strings.Contains(summary, "EVERUP_ANDROID_SECRETS") {
		t.Errorf("summary missing expected secret names: %s", summary)
	}
}

func TestPackSecrets(t *testing.T) {
	root := t.TempDir()
	certFile := filepath.Join(root, "test.p12")
	if err := os.WriteFile(certFile, []byte("certificate bytes"), 0600); err != nil {
		t.Fatal(err)
	}

	jsonStr, err := PackWindowsSecrets(certFile, "secret123")
	if err != nil {
		t.Fatalf("PackWindowsSecrets failed: %v", err)
	}
	var win WindowsSecrets
	if err := json.Unmarshal([]byte(jsonStr), &win); err != nil {
		t.Fatalf("failed to unmarshal windows secrets: %v", err)
	}
	if win.CertificatePassword != "secret123" {
		t.Errorf("expected password secret123, got %q", win.CertificatePassword)
	}
	if win.CertificateBase64 == "" {
		t.Errorf("expected non-empty certificate base64")
	}
}
