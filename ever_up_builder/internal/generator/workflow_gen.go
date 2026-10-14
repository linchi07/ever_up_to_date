package generator

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"text/template"

	"ever_up_builder/internal/model"
)

// GenerateGitHubWorkflow renders the release_matrix.yml template and writes it to .github/workflows/
func GenerateGitHubWorkflow(rootDir string, ctx model.TemplateContext) error {
	tplPath := filepath.Join(rootDir, "templates", "github-actions", "release_matrix.yml.tpl")
	tplBytes, err := os.ReadFile(tplPath)
	if err != nil {
		return fmt.Errorf("failed to read workflow template at %s: %w", tplPath, err)
	}

	tpl, err := template.New("release_matrix").Parse(string(tplBytes))
	if err != nil {
		return fmt.Errorf("failed to parse template: %w", err)
	}

	var buf bytes.Buffer
	if err := tpl.Execute(&buf, ctx); err != nil {
		return fmt.Errorf("failed to execute template: %w", err)
	}

	outDir := filepath.Join(rootDir, ".github", "workflows")
	if err := os.MkdirAll(outDir, 0755); err != nil {
		return fmt.Errorf("failed to create workflows directory: %w", err)
	}

	outPath := filepath.Join(outDir, "everup_release.yml")
	if err := os.WriteFile(outPath, buf.Bytes(), 0644); err != nil {
		return fmt.Errorf("failed to write workflow file: %w", err)
	}

	return nil
}

// GenerateInnoScript renders the modern Inno Setup template and writes it to windows/installer.iss
func GenerateInnoScript(rootDir string, ctx model.TemplateContext) error {
	tplPath := filepath.Join(rootDir, "templates", "inno-setup", "everup_modern.iss.tpl")
	tplBytes, err := os.ReadFile(tplPath)
	if err != nil {
		return fmt.Errorf("failed to read Inno template at %s: %w", tplPath, err)
	}

	tpl, err := template.New("inno_script").Parse(string(tplBytes))
	if err != nil {
		return fmt.Errorf("failed to parse template: %w", err)
	}

	var buf bytes.Buffer
	if err := tpl.Execute(&buf, ctx); err != nil {
		return fmt.Errorf("failed to execute template: %w", err)
	}

	outDir := filepath.Join(rootDir, "build", "windows")
	if err := os.MkdirAll(outDir, 0755); err != nil {
		return fmt.Errorf("failed to create build/windows directory: %w", err)
	}

	outPath := filepath.Join(outDir, "installer.iss")
	if err := os.WriteFile(outPath, buf.Bytes(), 0644); err != nil {
		return fmt.Errorf("failed to write Inno script: %w", err)
	}

	return nil
}
