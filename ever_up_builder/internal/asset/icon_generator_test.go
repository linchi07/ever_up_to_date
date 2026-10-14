package asset

import (
	"image"
	"image/color"
	"image/png"
	"os"
	"path/filepath"
	"testing"
)

func TestGenerateAllAssets(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "everup_asset_test")
	if err != nil {
		t.Fatalf("failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	// Create sample 512x512 image
	srcImg := image.NewRGBA(image.Rect(0, 0, 512, 512))
	for y := 0; y < 512; y++ {
		for x := 0; x < 512; x++ {
			srcImg.Set(x, y, color.RGBA{R: 99, G: 102, B: 241, A: 255})
		}
	}
	srcPath := filepath.Join(tempDir, "source.png")
	f, err := os.Create(srcPath)
	if err != nil {
		t.Fatalf("failed to create source image: %v", err)
	}
	_ = png.Encode(f, srcImg)
	_ = f.Close()

	outDir := filepath.Join(tempDir, "output")
	if err := GenerateAllAssets(srcPath, outDir); err != nil {
		t.Fatalf("GenerateAllAssets failed: %v", err)
	}

	expectedFiles := []string{
		"app_icon_512.png",
		"app_icon.ico",
		"wizard.bmp",
		"wizard_small.bmp",
	}

	for _, name := range expectedFiles {
		p := filepath.Join(outDir, name)
		info, err := os.Stat(p)
		if err != nil {
			t.Errorf("expected file %s was not created: %v", name, err)
		} else if info.Size() == 0 {
			t.Errorf("file %s is empty", name)
		}
	}
}
