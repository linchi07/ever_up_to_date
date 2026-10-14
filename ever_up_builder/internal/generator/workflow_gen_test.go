package generator

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"ever_up_builder/internal/model"
)

func TestGenerateWorkflowAndInno(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "everup_gen_test")
	if err != nil {
		t.Fatalf("failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	// Setup template files
	gaDir := filepath.Join(tempDir, "templates", "github-actions")
	_ = os.MkdirAll(gaDir, 0755)
	tplContent := `name: {{ .AppName }} Release
{{ if .EnableAndroid }}android_job: enabled{{ end }}
{{ if .EnableWindows }}windows_job: enabled{{ end }}
`
	_ = os.WriteFile(filepath.Join(gaDir, "release_matrix.yml.tpl"), []byte(tplContent), 0644)

	innoDir := filepath.Join(tempDir, "templates", "inno-setup")
	_ = os.MkdirAll(innoDir, 0755)
	innoContent := `[Setup]
AppName={{ .AppName }}
AppVersion={{ .Version }}
`
	_ = os.WriteFile(filepath.Join(innoDir, "everup_modern.iss.tpl"), []byte(innoContent), 0644)

	ctx := model.TemplateContext{
		AppName:       "TestApp",
		Version:       "1.2.3",
		EnableAndroid: true,
		EnableWindows: false,
	}

	if err := GenerateGitHubWorkflow(tempDir, ctx); err != nil {
		t.Fatalf("GenerateGitHubWorkflow failed: %v", err)
	}

	outWf := filepath.Join(tempDir, ".github", "workflows", "everup_release.yml")
	data, err := os.ReadFile(outWf)
	if err != nil {
		t.Fatalf("workflow file was not created: %v", err)
	}
	if !strings.Contains(string(data), "TestApp Release") || !strings.Contains(string(data), "android_job: enabled") {
		t.Fatalf("unexpected workflow content: %s", string(data))
	}

	if err := GenerateInnoScript(tempDir, ctx); err != nil {
		t.Fatalf("GenerateInnoScript failed: %v", err)
	}

	outInno := filepath.Join(tempDir, "build", "windows", "installer.iss")
	innoData, err := os.ReadFile(outInno)
	if err != nil {
		t.Fatalf("inno file was not created: %v", err)
	}
	if !strings.Contains(string(innoData), "AppName=TestApp") || !strings.Contains(string(innoData), "AppVersion=1.2.3") {
		t.Fatalf("unexpected inno script content: %s", string(innoData))
	}
}
