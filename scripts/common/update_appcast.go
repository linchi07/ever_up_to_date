package main

import (
	"crypto/ed25519"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"strings"
	"time"
)

type PlatformTarget struct {
	Type             string   `json:"type"`
	URL              string   `json:"url"`
	SHA256           string   `json:"sha256,omitempty"`
	SignatureEd25519 string   `json:"signature_ed25519,omitempty"`
	FileSize         int64    `json:"file_size,omitempty"`
	InstallerArgs    []string `json:"installer_args,omitempty"`
}

type ChannelInfo struct {
	Version      string                    `json:"version"`
	BuildNumber  int                       `json:"build_number,omitempty"`
	Mandatory    bool                      `json:"mandatory"`
	PubDate      string                    `json:"pub_date"`
	ReleaseNotes map[string]string         `json:"release_notes"`
	Platforms    map[string]PlatformTarget `json:"platforms"`
}

type Manifest struct {
	Version  int                    `json:"version"`
	AppID    string                 `json:"app_id,omitempty"`
	Channels map[string]ChannelInfo `json:"channels"`
}

func main() {
	manifestPath := flag.String("manifest", "appcast.json", "Path to appcast.json")
	channel := flag.String("channel", "stable", "Target channel (stable, beta, etc.)")
	version := flag.String("version", "1.0.0", "New release version string")
	buildNumber := flag.Int("build-number", 1, "New release build number")
	platform := flag.String("platform", "android", "Platform (android, windows, ios, macos)")
	pkgType := flag.String("type", "direct_apk", "Package type (direct_apk, inno_setup, etc.)")
	filePath := flag.String("file", "", "Local path to binary artifact (for hash & signature calculation)")
	url := flag.String("url", "", "Remote download or store URL on S3/OSS")
	privateKeyStr := flag.String("private-key", "", "Base64 encoded Ed25519 private key")
	notes := flag.String("notes", "", "Release notes description")
	mandatory := flag.Bool("mandatory", false, "Whether update is mandatory")
	flag.Parse()

	if *url == "" {
		fmt.Fprintf(os.Stderr, "Error: --url is required\n")
		os.Exit(1)
	}

	var sha256Hex string
	var signatureBase64 string
	var fileSize int64

	if *filePath != "" {
		data, err := os.ReadFile(*filePath)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error reading file: %v\n", err)
			os.Exit(1)
		}
		fileSize = int64(len(data))

		hash := sha256.Sum256(data)
		sha256Hex = hex.EncodeToString(hash[:])

		if *privateKeyStr != "" {
			privBytes, err := base64.StdEncoding.DecodeString(strings.TrimSpace(*privateKeyStr))
			if err != nil {
				fmt.Fprintf(os.Stderr, "Error decoding private key: %v\n", err)
				os.Exit(1)
			}
			if len(privBytes) == ed25519.PrivateKeySize {
				sig := ed25519.Sign(privBytes, data)
				signatureBase64 = base64.StdEncoding.EncodeToString(sig)
			}
		}
	}

	manifest := Manifest{
		Version:  1,
		Channels: make(map[string]ChannelInfo),
	}

	if data, err := os.ReadFile(*manifestPath); err == nil {
		_ = json.Unmarshal(data, &manifest)
		if manifest.Channels == nil {
			manifest.Channels = make(map[string]ChannelInfo)
		}
	}

	chInfo, exists := manifest.Channels[*channel]
	if !exists || chInfo.Version != *version {
		chInfo = ChannelInfo{
			Version:      *version,
			BuildNumber:  *buildNumber,
			Mandatory:    *mandatory,
			PubDate:      time.Now().UTC().Format(time.RFC3339),
			ReleaseNotes: make(map[string]string),
			Platforms:    make(map[string]PlatformTarget),
		}
	}

	if *notes != "" {
		if chInfo.ReleaseNotes == nil {
			chInfo.ReleaseNotes = make(map[string]string)
		}
		chInfo.ReleaseNotes["default"] = *notes
	}

	if chInfo.Platforms == nil {
		chInfo.Platforms = make(map[string]PlatformTarget)
	}

	target := PlatformTarget{
		Type:             *pkgType,
		URL:              *url,
		SHA256:           sha256Hex,
		SignatureEd25519: signatureBase64,
		FileSize:         fileSize,
	}

	if *pkgType == "inno_setup" {
		target.InstallerArgs = []string{"/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/SP-"}
	}

	chInfo.Platforms[*platform] = target
	manifest.Channels[*channel] = chInfo

	outJSON, err := json.MarshalIndent(manifest, "", "  ")
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error formatting JSON: %v\n", err)
		os.Exit(1)
	}

	if err := os.WriteFile(*manifestPath, outJSON, 0644); err != nil {
		fmt.Fprintf(os.Stderr, "Error writing manifest: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("==> Updated manifest at %s (channel: %s, platform: %s, version: %s)\n", *manifestPath, *channel, *platform, *version)
}
