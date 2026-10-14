package loader

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// ScriptItem represents a discovered script file.
type ScriptItem struct {
	Name     string
	Path     string
	Category string // "flutter", "common", etc.
}

// TemplateItem represents a discovered template file.
type TemplateItem struct {
	Name     string
	Path     string
	Category string // "github-actions", "inno-setup", "xcode-cloud"
}

// Catalog holds all dynamically scanned scripts and templates.
type Catalog struct {
	Scripts   []ScriptItem
	Templates []TemplateItem
}

// LoadCatalog scans the given root directory for scripts and templates.
func LoadCatalog(rootDir string) (*Catalog, error) {
	cat := &Catalog{
		Scripts:   make([]ScriptItem, 0),
		Templates: make([]TemplateItem, 0),
	}

	scriptsDir := filepath.Join(rootDir, "scripts")
	if info, err := os.Stat(scriptsDir); err == nil && info.IsDir() {
		_ = filepath.Walk(scriptsDir, func(path string, info os.FileInfo, err error) error {
			if err != nil || info.IsDir() {
				return nil
			}
			rel, _ := filepath.Rel(scriptsDir, path)
			parts := strings.Split(rel, string(os.PathSeparator))
			category := "misc"
			if len(parts) > 1 {
				category = parts[0]
			}
			cat.Scripts = append(cat.Scripts, ScriptItem{
				Name:     info.Name(),
				Path:     path,
				Category: category,
			})
			return nil
		})
	}

	templatesDir := filepath.Join(rootDir, "templates")
	if info, err := os.Stat(templatesDir); err == nil && info.IsDir() {
		_ = filepath.Walk(templatesDir, func(path string, info os.FileInfo, err error) error {
			if err != nil || info.IsDir() {
				return nil
			}
			rel, _ := filepath.Rel(templatesDir, path)
			parts := strings.Split(rel, string(os.PathSeparator))
			category := "misc"
			if len(parts) > 1 {
				category = parts[0]
			}
			cat.Templates = append(cat.Templates, TemplateItem{
				Name:     info.Name(),
				Path:     path,
				Category: category,
			})
			return nil
		})
	}

	return cat, nil
}

// PrintSummary outputs a human-readable table of discovered scripts and templates.
func (c *Catalog) PrintSummary() {
	fmt.Printf("==> Discovered Scripts (%d):\n", len(c.Scripts))
	for _, s := range c.Scripts {
		fmt.Printf("  • [%s] %s\n", s.Category, s.Name)
	}

	fmt.Printf("\n==> Discovered Templates (%d):\n", len(c.Templates))
	for _, t := range c.Templates {
		fmt.Printf("  • [%s] %s\n", t.Category, t.Name)
	}
}
