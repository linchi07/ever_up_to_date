package secrets

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"ever_up_builder/internal/model"
)

// CommonSecrets contains universal S3 storage credentials and the EverUp release signing key.
type CommonSecrets struct {
	S3AccessKeyID     string `json:"s3_access_key_id"`
	S3SecretAccessKey string `json:"s3_secret_access_key"`
	SigningPrivateKey string `json:"signing_private_key"`
}

// AndroidSecrets contains the Android release keystore and signing credentials.
type AndroidSecrets struct {
	KeystoreBase64   string `json:"keystore_base64"`
	KeystorePassword string `json:"keystore_password"`
	KeyAlias         string `json:"key_alias"`
	KeyPassword      string `json:"key_password"`
}

// WindowsSecrets contains the Windows Authenticode code-signing certificate credentials.
type WindowsSecrets struct {
	CertificateBase64   string `json:"certificate_base64"`
	CertificatePassword string `json:"certificate_password"`
}

// MacOSSecrets contains Apple Developer ID certificates and notarization credentials.
type MacOSSecrets struct {
	CertificateBase64   string `json:"certificate_base64"`
	CertificatePassword string `json:"certificate_password"`
	SigningIdentity     string `json:"signing_identity"`
	AppleID             string `json:"apple_id"`
	AppleAppPassword    string `json:"apple_app_password"`
	AppleTeamID         string `json:"apple_team_id"`
}

// LocalSecretStore represents the combined secrets saved securely in .everup/secrets.json.
type LocalSecretStore struct {
	Common  *CommonSecrets  `json:"common,omitempty"`
	Android *AndroidSecrets `json:"android,omitempty"`
	Windows *WindowsSecrets `json:"windows,omitempty"`
	MacOS   *MacOSSecrets   `json:"macos,omitempty"`
}

// LocalSecretsPath returns the path to .everup/secrets.json in the project root.
func LocalSecretsPath(root string) string {
	return filepath.Join(root, ".everup", "secrets.json")
}

// LoadLocalSecrets loads .everup/secrets.json if it exists.
func LoadLocalSecrets(root string) (*LocalSecretStore, error) {
	path := LocalSecretsPath(root)
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var store LocalSecretStore
	if err := json.Unmarshal(data, &store); err != nil {
		return nil, fmt.Errorf("failed to parse local secrets: %w", err)
	}
	return &store, nil
}

// SaveLocalSecrets securely writes secrets to .everup/secrets.json with 0600 permissions.
func SaveLocalSecrets(root string, store *LocalSecretStore) error {
	dir := filepath.Join(root, ".everup")
	if err := os.MkdirAll(dir, 0700); err != nil {
		return err
	}
	ignorePath := filepath.Join(root, ".gitignore")
	existing, err := os.ReadFile(ignorePath)
	if err == nil && !strings.Contains(string(existing), "/.everup/") {
		_ = os.WriteFile(ignorePath, append(existing, []byte("\n/.everup/\n")...), 0644)
	}

	data, err := json.MarshalIndent(store, "", "  ")
	if err != nil {
		return err
	}
	path := LocalSecretsPath(root)
	return os.WriteFile(path, append(data, '\n'), 0600)
}

// FileToBase64 reads any binary file (JKS, PFX, P12) and encodes it to a Base64 string.
func FileToBase64(filePath string) (string, error) {
	data, err := os.ReadFile(filePath)
	if err != nil {
		return "", fmt.Errorf("failed to read file %q: %w", filePath, err)
	}
	return base64.StdEncoding.EncodeToString(data), nil
}

// GenerateSecretTemplates returns a map of secret name to pretty-printed JSON string template.
func GenerateSecretTemplates(root string, cfg model.ProjectConfig) map[string]string {
	result := make(map[string]string)
	localStore, _ := LoadLocalSecrets(root)

	// 1. EVERUP_COMMON_SECRETS
	common := CommonSecrets{
		S3AccessKeyID:     "YOUR_S3_ACCESS_KEY_ID",
		S3SecretAccessKey: "YOUR_S3_SECRET_ACCESS_KEY",
	}
	if localStore != nil && localStore.Common != nil {
		common = *localStore.Common
	}
	if common.SigningPrivateKey == "" || common.SigningPrivateKey == "BASE64_ED25519_PRIVATE_KEY" {
		privateKeyPath := filepath.Join(root, ".everup", "signing-private.key")
		if data, err := os.ReadFile(privateKeyPath); err == nil {
			common.SigningPrivateKey = strings.TrimSpace(string(data))
		} else {
			common.SigningPrivateKey = "BASE64_ED25519_PRIVATE_KEY"
		}
	}
	if jsonStr, err := json.MarshalIndent(common, "", "  "); err == nil {
		result["EVERUP_COMMON_SECRETS"] = string(jsonStr)
	}

	// 2. EVERUP_ANDROID_SECRETS
	if cfg.EnableAndroid {
		android := AndroidSecrets{
			KeystoreBase64:   "BASE64_ENCODED_RELEASE_JKS",
			KeystorePassword: "YOUR_KEYSTORE_PASSWORD",
			KeyAlias:         "YOUR_KEY_ALIAS",
			KeyPassword:      "YOUR_KEY_PASSWORD",
		}
		if localStore != nil && localStore.Android != nil {
			android = *localStore.Android
		}
		if jsonStr, err := json.MarshalIndent(android, "", "  "); err == nil {
			result["EVERUP_ANDROID_SECRETS"] = string(jsonStr)
		}
	}

	// 3. EVERUP_WINDOWS_SECRETS
	if cfg.EnableWindows {
		windows := WindowsSecrets{
			CertificateBase64:   "BASE64_ENCODED_PFX_CERTIFICATE",
			CertificatePassword: "YOUR_CERTIFICATE_PASSWORD",
		}
		if localStore != nil && localStore.Windows != nil {
			windows = *localStore.Windows
		}
		if jsonStr, err := json.MarshalIndent(windows, "", "  "); err == nil {
			result["EVERUP_WINDOWS_SECRETS"] = string(jsonStr)
		}
	}

	// 4. EVERUP_MACOS_SECRETS
	if cfg.EnableMacOS {
		macOS := MacOSSecrets{
			CertificateBase64:   "BASE64_ENCODED_DEVELOPER_ID_P12",
			CertificatePassword: "YOUR_CERTIFICATE_PASSWORD",
			SigningIdentity:     "Developer ID Application: Your Company (TEAMID)",
			AppleID:             "developer@example.com",
			AppleAppPassword:    "abcd-efgh-ijkl-mnop",
			AppleTeamID:         "TEAMID1234",
		}
		if localStore != nil && localStore.MacOS != nil {
			macOS = *localStore.MacOS
		}
		if jsonStr, err := json.MarshalIndent(macOS, "", "  "); err == nil {
			result["EVERUP_MACOS_SECRETS"] = string(jsonStr)
		}
	}

	return result
}

// PackAndroidSecrets loads a JKS keystore file and packages it into AndroidSecrets JSON.
func PackAndroidSecrets(keystorePath, keystorePassword, keyAlias, keyPassword string) (string, error) {
	b64, err := FileToBase64(keystorePath)
	if err != nil {
		return "", err
	}
	data, err := json.MarshalIndent(AndroidSecrets{
		KeystoreBase64:   b64,
		KeystorePassword: keystorePassword,
		KeyAlias:         keyAlias,
		KeyPassword:      keyPassword,
	}, "", "  ")
	if err != nil {
		return "", err
	}
	return string(data), nil
}

// PackWindowsSecrets loads a PFX/P12 file and packages it into WindowsSecrets JSON.
func PackWindowsSecrets(certPath, certPassword string) (string, error) {
	b64, err := FileToBase64(certPath)
	if err != nil {
		return "", err
	}
	data, err := json.MarshalIndent(WindowsSecrets{
		CertificateBase64:   b64,
		CertificatePassword: certPassword,
	}, "", "  ")
	if err != nil {
		return "", err
	}
	return string(data), nil
}

// PackMacOSSecrets loads a P12 file and packages it into MacOSSecrets JSON.
func PackMacOSSecrets(certPath, certPassword, identity, appleID, appPassword, teamID string) (string, error) {
	b64, err := FileToBase64(certPath)
	if err != nil {
		return "", err
	}
	data, err := json.MarshalIndent(MacOSSecrets{
		CertificateBase64:   b64,
		CertificatePassword: certPassword,
		SigningIdentity:     identity,
		AppleID:             appleID,
		AppleAppPassword:    appPassword,
		AppleTeamID:         teamID,
	}, "", "  ")
	if err != nil {
		return "", err
	}
	return string(data), nil
}

// FormatSecretsSummary renders instructions with copy-pasteable blocks for GitHub repository secrets.
func FormatSecretsSummary(bundles map[string]string) string {
	var sb strings.Builder
	sb.WriteString("================================================================================\n")
	sb.WriteString("EverUp GitHub Secrets 配置指南（JSON 密钥架构）\n")
	sb.WriteString("前往 GitHub 仓库 -> Settings -> Secrets and variables -> Actions\n")
	sb.WriteString("点击 \"New repository secret\"，将下列各组 JSON 整体复制到对应的 Secret 中：\n")
	sb.WriteString("================================================================================\n\n")

	keys := []string{"EVERUP_COMMON_SECRETS", "EVERUP_ANDROID_SECRETS", "EVERUP_WINDOWS_SECRETS", "EVERUP_MACOS_SECRETS"}
	for _, key := range keys {
		if content, ok := bundles[key]; ok {
			sb.WriteString(fmt.Sprintf("▶ Secret 名称: %s\n", key))
			sb.WriteString("内容 (JSON):\n")
			sb.WriteString(content)
			sb.WriteString("\n\n--------------------------------------------------------------------------------\n\n")
		}
	}
	return sb.String()
}
