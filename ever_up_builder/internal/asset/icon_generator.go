package asset

import (
	"bytes"
	"encoding/binary"
	"fmt"
	"image"
	"image/png"
	"os"
	"path/filepath"

	"github.com/disintegration/imaging"
)

// GenerateAllAssets generates Windows .ico, Inno bitmaps, and app icon from source image.
func GenerateAllAssets(srcPath, outDir string) error {
	srcImg, err := imaging.Open(srcPath)
	if err != nil {
		return fmt.Errorf("failed to open source image at %s: %w", srcPath, err)
	}

	if err := os.MkdirAll(outDir, 0755); err != nil {
		return fmt.Errorf("failed to create output directory: %w", err)
	}

	// 1. Generate 512x512 app_icon.png
	icon512 := imaging.Fit(srcImg, 512, 512, imaging.Lanczos)
	if err := imaging.Save(icon512, filepath.Join(outDir, "app_icon_512.png")); err != nil {
		return fmt.Errorf("failed to save 512x512 icon: %w", err)
	}

	// 2. Generate Windows multi-resolution .ico (16, 32, 48, 64, 128, 256)
	icoPath := filepath.Join(outDir, "app_icon.ico")
	if err := createMultiResIco(srcImg, icoPath); err != nil {
		return fmt.Errorf("failed to create .ico: %w", err)
	}

	// 3. Generate Inno Setup wizard banner (164x314) and small icon (55x58)
	wizardBmp := imaging.Fill(srcImg, 164, 314, imaging.Center, imaging.Lanczos)
	if err := imaging.Save(wizardBmp, filepath.Join(outDir, "wizard.bmp")); err != nil {
		return fmt.Errorf("failed to save wizard.bmp: %w", err)
	}

	wizardSmallBmp := imaging.Fit(srcImg, 55, 58, imaging.Lanczos)
	if err := imaging.Save(wizardSmallBmp, filepath.Join(outDir, "wizard_small.bmp")); err != nil {
		return fmt.Errorf("failed to save wizard_small.bmp: %w", err)
	}

	return nil
}

// createMultiResIco creates a Windows .ico containing PNG streams for standard sizes.
func createMultiResIco(src image.Image, destPath string) error {
	sizes := []int{16, 32, 48, 64, 128, 256}
	var pngBuffers [][]byte

	for _, sz := range sizes {
		resized := imaging.Fit(src, sz, sz, imaging.Lanczos)
		var buf bytes.Buffer
		if err := png.Encode(&buf, resized); err != nil {
			return err
		}
		pngBuffers = append(pngBuffers, buf.Bytes())
	}

	file, err := os.Create(destPath)
	if err != nil {
		return err
	}
	defer file.Close()

	// ICONDIR Header (6 bytes)
	_ = binary.Write(file, binary.LittleEndian, uint16(0)) // Reserved
	_ = binary.Write(file, binary.LittleEndian, uint16(1)) // Type 1 = Icon
	_ = binary.Write(file, binary.LittleEndian, uint16(len(sizes)))

	offset := uint32(6 + len(sizes)*16)

	// ICONDIRENTRY (16 bytes per image)
	for i, sz := range sizes {
		bWidth := byte(sz)
		bHeight := byte(sz)
		if sz == 256 {
			bWidth = 0
			bHeight = 0
		}
		_ = binary.Write(file, binary.LittleEndian, bWidth)
		_ = binary.Write(file, binary.LittleEndian, bHeight)
		_ = binary.Write(file, binary.LittleEndian, byte(0))  // Color count
		_ = binary.Write(file, binary.LittleEndian, byte(0))  // Reserved
		_ = binary.Write(file, binary.LittleEndian, uint16(1)) // Planes
		_ = binary.Write(file, binary.LittleEndian, uint16(32)) // Bit count
		_ = binary.Write(file, binary.LittleEndian, uint32(len(pngBuffers[i])))
		_ = binary.Write(file, binary.LittleEndian, offset)

		offset += uint32(len(pngBuffers[i]))
	}

	// Write PNG image bytes
	for _, data := range pngBuffers {
		if _, err := file.Write(data); err != nil {
			return err
		}
	}

	return nil
}
