package main

import (
	"bytes"
	"crypto/ed25519"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func releaseArgs(t *testing.T) ([]string, ed25519.PublicKey, []byte) {
	t.Helper()
	root := t.TempDir()
	binary := []byte("release fixture")
	path := filepath.Join(root, "package.bin")
	if err := os.WriteFile(path, binary, 0600); err != nil {
		t.Fatal(err)
	}
	pub, key, err := ed25519.GenerateKey(nil)
	if err != nil {
		t.Fatal(err)
	}
	return []string{"--manifest=" + filepath.Join(root, "appcast.json"), "--app-id=com.example.app", "--channel=stable", "--version=v2.0.0", "--build-number=20", "--platform=windows", "--type=inno_setup", "--file=" + path, "--url=https://example.com/package.exe", "--private-key=" + base64.StdEncoding.EncodeToString(key)}, pub, binary
}
func readManifest(t *testing.T, args []string) Manifest {
	t.Helper()
	data, err := os.ReadFile(strings.TrimPrefix(args[0], "--manifest="))
	if err != nil {
		t.Fatal(err)
	}
	var manifest Manifest
	if err := json.Unmarshal(data, &manifest); err != nil {
		t.Fatal(err)
	}
	return manifest
}
func TestSignedReleaseAndMultiplePlatforms(t *testing.T) {
	args, pub, binary := releaseArgs(t)
	if err := run(args, &bytes.Buffer{}); err != nil {
		t.Fatal(err)
	}
	manifest := readManifest(t, args)
	target := manifest.Channels["stable"].Platforms["windows"]
	digest := sha256.Sum256(binary)
	sig, _ := base64.StdEncoding.DecodeString(target.SignatureEd25519)
	if manifest.AppID != "com.example.app" || manifest.Channels["stable"].Version != "2.0.0" || target.FileSize != int64(len(binary)) || target.SHA256 != hex.EncodeToString(digest[:]) || !ed25519.Verify(pub, binary, sig) {
		t.Fatalf("invalid signed release: %+v", manifest)
	}
	args[5] = "--platform=android"
	args[6] = "--type=direct_apk"
	if err := run(args, &bytes.Buffer{}); err != nil {
		t.Fatal(err)
	}
	if len(readManifest(t, args).Channels["stable"].Platforms) != 2 {
		t.Fatal("lost platform during same-release merge")
	}
}
func TestRejectsInvalidReleaseWithoutChangingManifest(t *testing.T) {
	for _, field := range []string{"--private-key=invalid", "--version=garbage", "--url=", "--file=", "--platform=ios", "--build-number=0"} {
		t.Run(field, func(t *testing.T) {
			args, _, _ := releaseArgs(t)
			if err := run(args, &bytes.Buffer{}); err != nil {
				t.Fatal(err)
			}
			path := strings.TrimPrefix(args[0], "--manifest=")
			before, _ := os.ReadFile(path)
			args = append(args, field)
			if err := run(args, &bytes.Buffer{}); err == nil {
				t.Fatal("accepted invalid release")
			}
			after, _ := os.ReadFile(path)
			if !bytes.Equal(before, after) {
				t.Fatal("changed manifest on failure")
			}
		})
	}
}
func TestRejectsCorruptManifestAndDowngrade(t *testing.T) {
	args, _, _ := releaseArgs(t)
	path := strings.TrimPrefix(args[0], "--manifest=")
	if err := os.WriteFile(path, []byte("{broken"), 0644); err != nil {
		t.Fatal(err)
	}
	if err := run(args, &bytes.Buffer{}); err == nil {
		t.Fatal("overwrote corrupt manifest")
	}
	if err := os.Remove(path); err != nil {
		t.Fatal(err)
	}
	if err := run(args, &bytes.Buffer{}); err != nil {
		t.Fatal(err)
	}
	args = append(args, "--version=1.9.0")
	if err := run(args, &bytes.Buffer{}); err == nil {
		t.Fatal("accepted downgrade")
	}
}
func TestIOSStoreOnlyRelease(t *testing.T) {
	args := []string{"--manifest=" + filepath.Join(t.TempDir(), "appcast.json"), "--version=1.0.0", "--platform=ios", "--type=testflight", "--url=https://testflight.apple.com/join/demo"}
	if err := run(args, &bytes.Buffer{}); err != nil {
		t.Fatal(err)
	}
}
func TestVersionOrdering(t *testing.T) {
	for _, pair := range [][2]string{{"1.0.0", "1.0.0-beta.2"}, {"1.0.0-beta.10", "1.0.0-beta.2"}, {"2.0.0", "1.9.9"}} {
		if compareVersion(pair[0], pair[1]) <= 0 {
			t.Fatal(pair)
		}
	}
}

func TestRolloutAndWithdrawal(t *testing.T) {
	args, _, _ := releaseArgs(t)
	args = append(args, "--rollout-percentage=10")
	if err := run(args, &bytes.Buffer{}); err != nil {
		t.Fatal(err)
	}
	release := readManifest(t, args).Channels["stable"]
	if release.RolloutPercentage == nil || *release.RolloutPercentage != 10 {
		t.Fatal("missing rollout policy")
	}
	path := strings.TrimPrefix(args[0], "--manifest=")
	if err := run([]string{"--manifest=" + path, "--channel=stable", "--version=2.0.0", "--withdraw"}, &bytes.Buffer{}); err != nil {
		t.Fatal(err)
	}
	withdrawn := readManifest(t, args).Channels["stable"]
	if !withdrawn.Withdrawn || len(withdrawn.Platforms) != len(release.Platforms) {
		t.Fatal("withdrawal changed packages")
	}
	if err := run([]string{"--manifest=" + path, "--channel=stable", "--version=3.0.0", "--withdraw"}, &bytes.Buffer{}); err == nil {
		t.Fatal("withdrew unexpected version")
	}
}
