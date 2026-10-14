package main

import (
	"crypto/ed25519"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"math"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
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
	RolloutPercentage *float64                  `json:"rollout_percentage,omitempty"`
	RolloutSeed       string                    `json:"rollout_seed,omitempty"`
	Withdrawn         bool                      `json:"withdrawn,omitempty"`
	Version           string                    `json:"version"`
	BuildNumber       int                       `json:"build_number,omitempty"`
	Mandatory         bool                      `json:"mandatory"`
	PubDate           string                    `json:"pub_date"`
	MinOSVersion      string                    `json:"min_os_version,omitempty"`
	ReleaseNotes      map[string]string         `json:"release_notes"`
	Platforms         map[string]PlatformTarget `json:"platforms"`
}
type Manifest struct {
	Version  int                    `json:"version"`
	AppID    string                 `json:"app_id,omitempty"`
	Channels map[string]ChannelInfo `json:"channels"`
}

var versionPattern = regexp.MustCompile(`^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$`)

func normalizeVersion(value string) (string, error) {
	value = strings.TrimPrefix(strings.TrimSpace(value), "v")
	if !versionPattern.MatchString(value) {
		return "", fmt.Errorf("invalid semantic version: %q", value)
	}
	base := strings.SplitN(value, "+", 2)[0]
	if parts := strings.SplitN(base, "-", 2); len(parts) == 2 {
		for _, identifier := range strings.Split(parts[1], ".") {
			if regexp.MustCompile(`^0[0-9]+$`).MatchString(identifier) {
				return "", errors.New("prerelease number has a leading zero")
			}
		}
	}
	return value, nil
}
func compareVersion(a, b string) int {
	// Both inputs have been validated. Build metadata does not affect ordering.
	split := func(v string) ([]string, []string) {
		v = strings.SplitN(v, "+", 2)[0]
		parts := strings.SplitN(v, "-", 2)
		var pre []string
		if len(parts) == 2 {
			pre = strings.Split(parts[1], ".")
		}
		return strings.Split(parts[0], "."), pre
	}
	number := func(x, y string) int {
		if len(x) < len(y) {
			return -1
		}
		if len(x) > len(y) {
			return 1
		}
		return strings.Compare(x, y)
	}
	aa, ap := split(a)
	bb, bp := split(b)
	for i := range aa {
		if n := number(aa[i], bb[i]); n != 0 {
			return n
		}
	}
	if len(ap) == 0 && len(bp) > 0 {
		return 1
	}
	if len(bp) == 0 && len(ap) > 0 {
		return -1
	}
	numeric := regexp.MustCompile(`^[0-9]+$`)
	for i := 0; i < len(ap) && i < len(bp); i++ {
		an, bn := numeric.MatchString(ap[i]), numeric.MatchString(bp[i])
		var n int
		if an && bn {
			n = number(ap[i], bp[i])
		} else if an {
			n = -1
		} else if bn {
			n = 1
		} else {
			n = strings.Compare(ap[i], bp[i])
		}
		if n != 0 {
			return n
		}
	}
	return len(ap) - len(bp)
}

func run(args []string, output io.Writer) error {
	flags := flag.NewFlagSet("update_appcast", flag.ContinueOnError)
	flags.SetOutput(output)
	manifestPath := flags.String("manifest", "appcast.json", "Appcast path")
	channel := flags.String("channel", "stable", "Release channel")
	version := flags.String("version", "", "Required SemVer release version")
	build := flags.Int("build-number", 1, "Build number")
	platform := flags.String("platform", "", "Required target platform")
	kind := flags.String("type", "", "Required package type")
	file := flags.String("file", "", "Binary to checksum and sign")
	remote := flags.String("url", "", "Download or store URL")
	key := flags.String("private-key", os.Getenv("PRIVATE_KEY"), "Signing key (prefer PRIVATE_KEY environment variable)")
	appID := flags.String("app-id", "", "Expected application ID")
	notes := flags.String("notes", "", "Release notes")
	mandatory := flags.Bool("mandatory", false, "Mandatory release")
	unsigned := flags.Bool("allow-unsigned", false, "Explicitly permit unsigned development binaries")
	downgrade := flags.Bool("allow-downgrade", false, "Explicitly permit restoring an older release")
	percentage := flags.Float64("rollout-percentage", 100, "Percentage of installations eligible for the release")
	seed := flags.String("rollout-seed", "", "Stable cohort seed; defaults to the release version")
	withdraw := flags.Bool("withdraw", false, "Withdraw an existing channel without changing its packages")
	if err := flags.Parse(args); err != nil {
		return err
	}
	if flags.NArg() != 0 {
		return errors.New("unexpected positional arguments")
	}
	if *withdraw {
		return withdrawChannel(*manifestPath, *channel, *version, output)
	}
	if math.IsNaN(*percentage) || math.IsInf(*percentage, 0) || *percentage < 0 || *percentage > 100 {
		return errors.New("rollout-percentage must be between 0 and 100")
	}
	normalized, err := normalizeVersion(*version)
	if err != nil {
		return err
	}
	if !regexp.MustCompile(`^[a-z][a-z0-9_-]*$`).MatchString(*channel) {
		return errors.New("invalid release channel")
	}
	if *build < 1 {
		return errors.New("build-number must be positive")
	}
	valid := map[string]map[string]bool{
		"android": {"direct_apk": true, "google_play": true},
		"windows": {"inno_setup": true, "generic_installer": true, "portable_archive": true},
		"macos":   {"dmg": true, "pkg": true}, "ios": {"app_store": true, "testflight": true}, "linux": {"app_image": true},
	}
	if !valid[*platform][*kind] {
		return fmt.Errorf("unsupported platform/package: %s/%s", *platform, *kind)
	}
	uri, err := url.Parse(*remote)
	if err != nil || uri.Host == "" || (uri.Scheme != "https" && uri.Scheme != "http") {
		return errors.New("--url must be an HTTP(S) URL")
	}
	target := PlatformTarget{Type: *kind, URL: *remote}
	external := *kind == "app_store" || *kind == "testflight" || *kind == "google_play"
	if !external {
		if *file == "" {
			return errors.New("--file is required for binary distributions")
		}
		data, err := os.ReadFile(*file)
		if err != nil {
			return fmt.Errorf("read binary: %w", err)
		}
		if len(data) == 0 {
			return errors.New("binary must not be empty")
		}
		digest := sha256.Sum256(data)
		target.SHA256 = hex.EncodeToString(digest[:])
		target.FileSize = int64(len(data))
		if strings.TrimSpace(*key) == "" {
			if !*unsigned {
				return errors.New("PRIVATE_KEY is required; unsigned packages require --allow-unsigned")
			}
		} else {
			secret, err := base64.StdEncoding.DecodeString(strings.TrimSpace(*key))
			if err != nil {
				return errors.New("invalid Base64 signing key")
			}
			if len(secret) == ed25519.SeedSize {
				secret = ed25519.NewKeyFromSeed(secret)
			}
			if len(secret) != ed25519.PrivateKeySize {
				return errors.New("signing key must be a 32-byte seed or 64-byte private key")
			}
			// Reject inconsistent 64-byte keys rather than silently creating unusable signatures.
			derived := ed25519.NewKeyFromSeed(secret[:ed25519.SeedSize])
			if !ed25519.PrivateKey(secret).Equal(derived) {
				return errors.New("inconsistent Ed25519 private key")
			}
			target.SignatureEd25519 = base64.StdEncoding.EncodeToString(ed25519.Sign(derived, data))
		}
	}
	if *kind == "inno_setup" {
		target.InstallerArgs = []string{"/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/SP-"}
	}
	manifest := Manifest{Version: 1, AppID: *appID, Channels: make(map[string]ChannelInfo)}
	data, err := os.ReadFile(*manifestPath)
	if err == nil {
		if err := json.Unmarshal(data, &manifest); err != nil {
			return fmt.Errorf("invalid existing appcast: %w", err)
		}
		if manifest.Version != 1 || manifest.Channels == nil {
			return errors.New("unsupported or invalid appcast schema")
		}
		if *appID != "" && manifest.AppID != "" && manifest.AppID != *appID {
			return errors.New("app_id mismatch")
		}
		if manifest.AppID == "" {
			manifest.AppID = *appID
		}
	} else if !os.IsNotExist(err) {
		return err
	}
	previous, exists := manifest.Channels[*channel]
	if exists {
		oldVersion, err := normalizeVersion(previous.Version)
		if err != nil {
			return fmt.Errorf("invalid previous version: %w", err)
		}
		order := compareVersion(normalized, oldVersion)
		if !*downgrade && (order < 0 || (order == 0 && *build < previous.BuildNumber)) {
			return errors.New("release would downgrade the published version/build")
		}
	}
	if !exists || previous.Version != normalized || previous.BuildNumber != *build {
		previous = ChannelInfo{Version: normalized, BuildNumber: *build, Mandatory: *mandatory,
			PubDate: time.Now().UTC().Format(time.RFC3339), ReleaseNotes: map[string]string{}, Platforms: map[string]PlatformTarget{}}
	}
	if previous.Platforms == nil {
		previous.Platforms = map[string]PlatformTarget{}
	}
	if previous.ReleaseNotes == nil {
		previous.ReleaseNotes = map[string]string{}
	}
	if *notes != "" {
		previous.ReleaseNotes["default"] = *notes
	}
	previous.Mandatory = *mandatory
	previous.RolloutPercentage = percentage
	previous.RolloutSeed = *seed
	previous.Withdrawn = false
	previous.Platforms[*platform] = target
	manifest.Channels[*channel] = previous
	out, err := json.MarshalIndent(manifest, "", "  ")
	if err != nil {
		return err
	}
	if err := atomicWrite(*manifestPath, append(out, '\n')); err != nil {
		return err
	}
	fmt.Fprintf(output, "Updated %s: %s/%s %s+%s\n", *manifestPath, *channel, *platform, normalized, strconv.Itoa(*build))
	return nil
}
func withdrawChannel(path, channel, expectedVersion string, output io.Writer) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	var manifest Manifest
	if err := json.Unmarshal(data, &manifest); err != nil {
		return err
	}
	if manifest.Version != 1 {
		return errors.New("unsupported manifest schema")
	}
	release, exists := manifest.Channels[channel]
	if !exists {
		return errors.New("channel does not exist")
	}
	if expectedVersion != "" {
		expected, err := normalizeVersion(expectedVersion)
		if err != nil {
			return err
		}
		current, err := normalizeVersion(release.Version)
		if err != nil {
			return err
		}
		if expected != current {
			return errors.New("published version changed; refuse withdrawal")
		}
	}
	release.Withdrawn = true
	manifest.Channels[channel] = release
	out, err := json.MarshalIndent(manifest, "", "  ")
	if err != nil {
		return err
	}
	if err := atomicWrite(path, append(out, '\n')); err != nil {
		return err
	}
	fmt.Fprintf(output, "Withdrew %s %s\n", channel, release.Version)
	return nil
}

func atomicWrite(path string, data []byte) error {
	temp, err := os.CreateTemp(filepath.Dir(path), ".everup-appcast-*")
	if err != nil {
		return err
	}
	defer os.Remove(temp.Name())
	if _, err = temp.Write(data); err != nil {
		temp.Close()
		return err
	}
	if err = temp.Chmod(0644); err != nil {
		temp.Close()
		return err
	}
	if err = temp.Sync(); err != nil {
		temp.Close()
		return err
	}
	if err = temp.Close(); err != nil {
		return err
	}
	return os.Rename(temp.Name(), path)
}
func main() {
	if err := run(os.Args[1:], os.Stdout); err != nil && !errors.Is(err, flag.ErrHelp) {
		fmt.Fprintln(os.Stderr, "Error:", err)
		os.Exit(1)
	}
}
