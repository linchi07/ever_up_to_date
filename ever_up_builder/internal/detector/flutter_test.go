package detector

import (
	"os"
	"path/filepath"
	"testing"
)

func TestDetectFlutterProject(t *testing.T) {
	root := t.TempDir()

	// 1. Create pubspec.yaml
	pubspec := `name: my_test_app
description: A new Flutter project.
version: 2.1.3+42
`
	if err := os.WriteFile(filepath.Join(root, "pubspec.yaml"), []byte(pubspec), 0644); err != nil {
		t.Fatal(err)
	}

	// 2. Create android app build.gradle
	androidDir := filepath.Join(root, "android", "app")
	if err := os.MkdirAll(androidDir, 0755); err != nil {
		t.Fatal(err)
	}
	gradle := `
android {
    namespace = "com.sample.autodetect"
    defaultConfig {
        applicationId = "com.sample.autodetect"
    }
}
`
	if err := os.WriteFile(filepath.Join(androidDir, "build.gradle.kts"), []byte(gradle), 0644); err != nil {
		t.Fatal(err)
	}

	// 3. Create windows/CMakeLists.txt
	windowsDir := filepath.Join(root, "windows")
	if err := os.MkdirAll(windowsDir, 0755); err != nil {
		t.Fatal(err)
	}
	cmake := `
cmake_minimum_required(VERSION 3.14)
set(BINARY_NAME "custom_runner")
`
	if err := os.WriteFile(filepath.Join(windowsDir, "CMakeLists.txt"), []byte(cmake), 0644); err != nil {
		t.Fatal(err)
	}

	cfg := DetectFlutterProject(root)

	if cfg.AppName != "my_test_app" {
		t.Errorf("expected AppName my_test_app, got %q", cfg.AppName)
	}
	if cfg.Version != "2.1.3" {
		t.Errorf("expected Version 2.1.3, got %q", cfg.Version)
	}
	if cfg.AppID != "com.sample.autodetect" {
		t.Errorf("expected AppID com.sample.autodetect, got %q", cfg.AppID)
	}
	if cfg.ExecutableName != "custom_runner.exe" {
		t.Errorf("expected ExecutableName custom_runner.exe, got %q", cfg.ExecutableName)
	}
	if !cfg.EnableAndroid {
		t.Errorf("expected EnableAndroid to be true")
	}
	if !cfg.EnableWindows {
		t.Errorf("expected EnableWindows to be true")
	}
	if cfg.EnableMacOS {
		t.Errorf("expected EnableMacOS to be false because macos dir not created")
	}
}
