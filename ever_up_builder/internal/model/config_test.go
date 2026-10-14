package model

import (
	"encoding/base64"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestConfigRoundTripAndValidation(t *testing.T) {
	cfg := DefaultConfig()
	cfg.EnableAndroid = true
	cfg.S3Bucket = "updates-bucket"
	cfg.ManifestURL = "https://example.com/appcast.json"
	cfg.PublicKeyEd25519 = base64.StdEncoding.EncodeToString(make([]byte, 32))
	root := t.TempDir()
	if err := cfg.Save(root); err != nil {
		t.Fatal(err)
	}
	loaded, err := LoadConfig(root)
	if err != nil {
		t.Fatal(err)
	}
	if loaded != cfg {
		t.Fatal("configuration did not round trip")
	}
	data, _ := os.ReadFile(filepath.Join(root, ConfigName))
	if strings.Contains(string(data), "private_key") {
		t.Fatal("configuration contains private material")
	}
	cfg.ExecutableName = "bad\n[Files]"
	if cfg.Validate() == nil {
		t.Fatal("accepted template injection")
	}
}
