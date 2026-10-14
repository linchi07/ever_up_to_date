package model

// ProjectConfig contains all configuration parameters for generating release pipelines.
type ProjectConfig struct {
	AppName        string `json:"app_name"`
	AppID          string `json:"app_id"`
	Version        string `json:"version"`
	Publisher      string `json:"publisher"`
	ExecutableName string `json:"executable_name"`

	// Target platforms
	EnableAndroid bool `json:"enable_android"`
	EnableWindows bool `json:"enable_windows"`
	EnableMacOS   bool `json:"enable_macos"`
	EnableIOS     bool `json:"enable_ios"`

	// Storage & Distribution
	S3Bucket    string `json:"s3_bucket"`
	S3Endpoint  string `json:"s3_endpoint"`
	ManifestURL string `json:"manifest_url"`

	// Cryptographic Security
	PublicKeyEd25519  string `json:"public_key_ed25519"`
	PrivateKeyEd25519 string `json:"private_key_ed25519"`

	// Asset Paths
	IconPath string `json:"icon_path"`
}

// TemplateContext is passed to Go text/template for rendering files.
type TemplateContext struct {
	AppName        string
	AppID          string
	Version        string
	Publisher      string
	ExecutableName string
	SourceDir      string
	IconPath       string
	EnableAndroid  bool
	EnableWindows  bool
	EnableMacOS    bool
	EnableIOS      bool
	S3Bucket       string
	S3Endpoint     string
}
