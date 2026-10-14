package loader

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoadCatalog(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "everup_catalog_test")
	if err != nil {
		t.Fatalf("failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	// Create sample scripts
	flutterDir := filepath.Join(tempDir, "scripts", "flutter")
	_ = os.MkdirAll(flutterDir, 0755)
	_ = os.WriteFile(filepath.Join(flutterDir, "build_android.sh"), []byte("#!/bin/bash"), 0755)

	commonDir := filepath.Join(tempDir, "scripts", "common")
	_ = os.MkdirAll(commonDir, 0755)
	_ = os.WriteFile(filepath.Join(commonDir, "s3_upload.sh"), []byte("#!/bin/bash"), 0755)

	// Create sample template
	tplDir := filepath.Join(tempDir, "templates", "github-actions")
	_ = os.MkdirAll(tplDir, 0755)
	_ = os.WriteFile(filepath.Join(tplDir, "release.yml.tpl"), []byte("name: test"), 0644)

	cat, err := LoadCatalog(tempDir)
	if err != nil {
		t.Fatalf("LoadCatalog failed: %v", err)
	}

	if len(cat.Scripts) != 2 {
		t.Errorf("expected 2 scripts, got %d", len(cat.Scripts))
	}
	if len(cat.Templates) != 1 {
		t.Errorf("expected 1 template, got %d", len(cat.Templates))
	}
}
