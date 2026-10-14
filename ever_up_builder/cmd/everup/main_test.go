package main

import (
	"ever_up_builder/internal/crypto"
	"ever_up_builder/internal/model"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestGenerateUsesSavedConfigAndOnlyExportsPublicKey(t *testing.T) {
	root := t.TempDir()
	pair, err := crypto.EnsureKeyPair(root)
	if err != nil {
		t.Fatal(err)
	}
	cfg := model.DefaultConfig()
	cfg.EnableWindows = true
	cfg.S3Bucket = "test-bucket"
	cfg.ManifestURL = "https://updates.example.com/$release/appcast.json"
	cfg.PublicKeyEd25519 = pair.PublicKey
	if err := cfg.Save(root); err != nil {
		t.Fatal(err)
	}
	if err := run([]string{"generate", root}); err != nil {
		t.Fatal(err)
	}
	source, err := os.ReadFile(filepath.Join(root, "lib", "everup_config.dart"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(source), pair.PublicKey) || !strings.Contains(string(source), `\$release`) || strings.Contains(string(source), pair.PrivateKey) {
		t.Fatal("incorrect public client configuration")
	}
	if err := run([]string{"generate", root}); err != nil {
		t.Fatal(err)
	}
	restored, err := crypto.EnsureKeyPair(root)
	if err != nil {
		t.Fatal(err)
	}
	if *restored != *pair {
		t.Fatal("regeneration rotated signing key")
	}
}
func TestCommandFailuresReturnErrors(t *testing.T) {
	for _, command := range []string{"unknown", "generate", "init", "crop", "gen-assets"} {
		arguments := []string{command}
		if command == "generate" || command == "init" {
			arguments = append(arguments, t.TempDir())
		}
		if err := run(arguments); err == nil {
			t.Fatalf("%s silently succeeded", command)
		}
	}
}

func TestSecretsCommand(t *testing.T) {
	root := t.TempDir()
	if err := run([]string{"secrets", root}); err != nil {
		t.Fatalf("secrets failed: %v", err)
	}
}
