package generator

import (
	"encoding/base64"
	"ever_up_builder/internal/model"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestRealTemplatesForPlatformCombinations(t *testing.T) {
	for mask := 1; mask < 16; mask++ {
		root := t.TempDir()
		cfg := model.DefaultConfig()
		cfg.AppName = "TestApp"
		cfg.AppID = "com.example.test"
		cfg.ExecutableName = "test.exe"
		cfg.EnableAndroid = mask&1 != 0
		cfg.EnableWindows = mask&2 != 0
		cfg.EnableMacOS = mask&4 != 0
		cfg.EnableIOS = mask&8 != 0
		cfg.S3Bucket = "test-bucket"
		cfg.ManifestURL = "https://updates.example.com/appcast.json"
		cfg.IOSStoreURL = "https://testflight.apple.com/join/test"
		cfg.PublicKeyEd25519 = base64.StdEncoding.EncodeToString(make([]byte, 32))
		if err := GenerateProject(root, cfg); err != nil {
			t.Fatalf("combination %d: %v", mask, err)
		}
		data, err := os.ReadFile(filepath.Join(root, ".github", "workflows", "everup_release.yml"))
		if err != nil {
			t.Fatal(err)
		}
		workflow := string(data)
		if validator := os.Getenv("EVERUP_ACTIONLINT"); validator != "" {
			command := exec.Command(validator, "-shellcheck=", filepath.Join(root, ".github", "workflows", "everup_release.yml"))
			if output, err := command.CombinedOutput(); err != nil {
				t.Fatalf("combination %d workflow invalid: %s (%v)", mask, output, err)
			}
		}
		for _, required := range []string{"S3_BUCKET: \"test-bucket\"", "MANIFEST_URL: \"https://updates.example.com/appcast.json\"", "scripts/common/publish_release.sh", "cancel-in-progress: false", "needs: [metadata", "${{ needs.metadata.outputs.version }}"} {
			if !strings.Contains(workflow, required) {
				t.Fatalf("combination %d missing %q", mask, required)
			}
		}
		for name, enabled := range map[string]bool{"build-android:": cfg.EnableAndroid, "build-windows:": cfg.EnableWindows, "build-macos:": cfg.EnableMacOS} {
			if strings.Contains(workflow, name) != enabled {
				t.Fatalf("wrong platform jobs: %s", name)
			}
		}
		if cfg.EnableWindows {
			data, err := os.ReadFile(filepath.Join(root, "windows", "installer.iss"))
			if err != nil {
				t.Fatal(err)
			}
			if !strings.Contains(string(data), "OutputDir=..\\build\\windows\\installer") || !strings.Contains(string(data), `#define MyAppExeName "test.exe"`) {
				t.Fatal("incorrect installer paths or executable")
			}
		}
		if cfg.EnableIOS {
			if _, err := os.Stat(filepath.Join(root, "ios", "ci_scripts", "ci_post_clone.sh")); err != nil {
				t.Fatal(err)
			}
		}
		if _, err := model.LoadConfig(root); err != nil {
			t.Fatal(err)
		}
		if _, err := os.Stat(filepath.Join(root, "scripts", "common", "update_appcast.go")); err != nil {
			t.Fatal("missing embedded release script", err)
		}
	}
}
func TestBrokenOverrideFailsGeneration(t *testing.T) {
	root := t.TempDir()
	directory := filepath.Join(root, "templates", "github-actions")
	if err := os.MkdirAll(directory, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(directory, "release_matrix.yml.tpl"), []byte("{{ invalid }}"), 0644); err != nil {
		t.Fatal(err)
	}
	if err := GenerateGitHubWorkflow(root, model.TemplateContext{}); err == nil {
		t.Fatal("accepted broken template")
	}
}
