package model

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

const ConfigName = "everup.json"

type ProjectConfig struct {
	RolloutPercentage      int    `json:"rollout_percentage"`
	AppName                string `json:"app_name"`
	AppID                  string `json:"app_id"`
	Version                string `json:"version"`
	Publisher              string `json:"publisher"`
	ExecutableName         string `json:"executable_name"`
	EnableAndroid          bool   `json:"enable_android"`
	EnableWindows          bool   `json:"enable_windows"`
	EnableMacOS            bool   `json:"enable_macos"`
	EnableIOS              bool   `json:"enable_ios"`
	S3Bucket               string `json:"s3_bucket"`
	S3Endpoint             string `json:"s3_endpoint"`
	S3Region               string `json:"s3_region"`
	S3Prefix               string `json:"s3_prefix"`
	ManifestURL            string `json:"manifest_url"`
	PublicKeyEd25519       string `json:"public_key_ed25519"`
	IconPath               string `json:"icon_path"`
	IOSStoreURL            string `json:"ios_store_url,omitempty"`
	IOSPackageType         string `json:"ios_package_type,omitempty"`
	RequirePlatformSigning bool   `json:"require_platform_signing"`
}

func DefaultConfig() ProjectConfig {
	return ProjectConfig{RolloutPercentage: 100, AppName: "EverUpApp", AppID: "com.example.everup", Version: "1.0.0", Publisher: "EverUp Team",
		ExecutableName: "app.exe", S3Region: "us-east-1", IconPath: `runner\resources\app_icon.ico`, IOSPackageType: "testflight", RequirePlatformSigning: true}
}
func LoadConfig(root string) (ProjectConfig, error) {
	cfg := DefaultConfig()
	data, err := os.ReadFile(filepath.Join(root, ConfigName))
	if err != nil {
		return cfg, err
	}
	decoder := json.NewDecoder(strings.NewReader(string(data)))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&cfg); err != nil {
		return cfg, err
	}
	return cfg, cfg.Validate()
}
func (cfg ProjectConfig) Validate() error {
	if cfg.RolloutPercentage < 0 || cfg.RolloutPercentage > 100 {
		return errors.New("rollout_percentage must be between 0 and 100")
	}
	for name, value := range map[string]string{"app_name": cfg.AppName, "publisher": cfg.Publisher, "executable_name": cfg.ExecutableName} {
		if value == "" || strings.ContainsAny(value, "\r\n\";<>|/\\:*?") {
			return fmt.Errorf("invalid %s", name)
		}
	}
	if !regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._-]+$`).MatchString(cfg.AppID) {
		return errors.New("invalid app_id")
	}
	if !regexp.MustCompile(`^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$`).MatchString(cfg.Version) {
		return errors.New("invalid version")
	}
	if !cfg.EnableAndroid && !cfg.EnableWindows && !cfg.EnableMacOS && !cfg.EnableIOS {
		return errors.New("select at least one platform")
	}
	if !regexp.MustCompile(`^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$`).MatchString(cfg.S3Bucket) {
		return errors.New("invalid s3_bucket")
	}
	validateURL := func(value string) error {
		uri, err := url.Parse(value)
		if err != nil || uri.Host == "" || (uri.Scheme != "https" && uri.Scheme != "http") || uri.RawQuery != "" || uri.Fragment != "" || uri.User != nil {
			return fmt.Errorf("invalid URL: %q", value)
		}
		return nil
	}
	if err := validateURL(cfg.ManifestURL); err != nil {
		return err
	}
	if !strings.HasSuffix(cfg.ManifestURL, "/appcast.json") {
		return errors.New("manifest_url must end with /appcast.json")
	}
	if cfg.S3Endpoint != "" {
		if err := validateURL(cfg.S3Endpoint); err != nil {
			return err
		}
	}
	if cfg.S3Region == "" {
		return errors.New("s3_region is required")
	}
	if cfg.S3Prefix != "" && !regexp.MustCompile(`^[a-zA-Z0-9_-]+(/[a-zA-Z0-9_-]+)*$`).MatchString(cfg.S3Prefix) {
		return errors.New("invalid s3_prefix")
	}
	if cfg.EnableIOS {
		if cfg.IOSPackageType != "app_store" && cfg.IOSPackageType != "testflight" {
			return errors.New("invalid ios_package_type")
		}
		if err := validateURL(cfg.IOSStoreURL); err != nil {
			return err
		}
	}
	key, err := base64.StdEncoding.DecodeString(cfg.PublicKeyEd25519)
	if err != nil || len(key) != 32 {
		return errors.New("public_key_ed25519 must be a Base64 32-byte public key")
	}
	if strings.ContainsAny(cfg.IconPath, "\r\n\";") {
		return errors.New("invalid icon_path")
	}
	return nil
}
func (cfg ProjectConfig) Save(root string) error {
	if err := cfg.Validate(); err != nil {
		return err
	}
	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(root, ConfigName), append(data, '\n'), 0644)
}

type TemplateContext struct {
	RolloutPercentage      int
	AppName                string
	AppID                  string
	Version                string
	Publisher              string
	ExecutableName         string
	SourceDir              string
	IconPath               string
	EnableAndroid          bool
	EnableWindows          bool
	EnableMacOS            bool
	EnableIOS              bool
	S3Bucket               string
	S3Endpoint             string
	S3Region               string
	S3Prefix               string
	ManifestURL            string
	IOSStoreURL            string
	IOSPackageType         string
	RequirePlatformSigning bool
}

func (cfg ProjectConfig) Context() TemplateContext {
	return TemplateContext{RolloutPercentage: cfg.RolloutPercentage, AppName: cfg.AppName, AppID: cfg.AppID, Version: cfg.Version, Publisher: cfg.Publisher,
		ExecutableName: cfg.ExecutableName, SourceDir: `..\build\windows\x64\runner\Release`, IconPath: cfg.IconPath,
		EnableAndroid: cfg.EnableAndroid, EnableWindows: cfg.EnableWindows, EnableMacOS: cfg.EnableMacOS, EnableIOS: cfg.EnableIOS,
		S3Bucket: cfg.S3Bucket, S3Endpoint: cfg.S3Endpoint, S3Region: cfg.S3Region, S3Prefix: cfg.S3Prefix,
		ManifestURL: cfg.ManifestURL, IOSStoreURL: cfg.IOSStoreURL, IOSPackageType: cfg.IOSPackageType, RequirePlatformSigning: cfg.RequirePlatformSigning}
}
