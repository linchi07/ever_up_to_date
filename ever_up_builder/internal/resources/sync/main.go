// Copies authoritative repository resources into the binary's embedded bundle.
package main

import (
	"io/fs"
	"os"
	"path/filepath"
	"strings"
)

func main() {
	for _, directory := range []string{"scripts", "templates"} {
		source := filepath.Join("..", "..", "..", directory)
		if err := os.RemoveAll(directory); err != nil {
			panic(err)
		}
		if err := filepath.WalkDir(source, func(path string, entry fs.DirEntry, err error) error {
			if err != nil {
				return err
			}
			if entry.IsDir() || entry.Name() == "go.mod" || strings.HasSuffix(path, "_test.go") || strings.HasSuffix(path, ".py") {
				return nil
			}
			relative, err := filepath.Rel(source, path)
			if err != nil {
				return err
			}
			target := filepath.Join(directory, relative)
			data, err := os.ReadFile(path)
			if err != nil {
				return err
			}
			if err := os.MkdirAll(filepath.Dir(target), 0755); err != nil {
				return err
			}
			return os.WriteFile(target, data, 0644)
		}); err != nil {
			panic(err)
		}
	}
}
