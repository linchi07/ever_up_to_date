package resources

import (
	"embed"
	"io/fs"
	"os"
	"path/filepath"
)

//go:generate go run ./sync
//go:embed scripts templates
var Files embed.FS

// Export installs bundled resources in a target project. Existing overrides are preserved.
func Export(root string) error {
	return fs.WalkDir(Files, ".", func(name string, entry fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if entry.IsDir() {
			return nil
		}
		path := filepath.Join(root, filepath.FromSlash(name))
		if _, err := os.Stat(path); err == nil {
			return nil
		} else if !os.IsNotExist(err) {
			return err
		}
		data, err := Files.ReadFile(name)
		if err != nil {
			return err
		}
		if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
			return err
		}
		return os.WriteFile(path, data, 0644)
	})
}
