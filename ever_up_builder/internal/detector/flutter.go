package detector

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"

	"ever_up_builder/internal/model"
)

// DetectFlutterProject reads existing configuration and auto-detects Flutter project metadata.
func DetectFlutterProject(root string) model.ProjectConfig {
	cfg := model.DefaultConfig()

	// 1. If everup.json exists, load any existing values as defaults.
	configPath := filepath.Join(root, model.ConfigName)
	if data, err := os.ReadFile(configPath); err == nil {
		_ = json.Unmarshal(data, &cfg)
	}

	// 2. Detect AppName and Version from pubspec.yaml.
	pubspecPath := filepath.Join(root, "pubspec.yaml")
	if data, err := os.ReadFile(pubspecPath); err == nil {
		lines := strings.Split(string(data), "\n")
		for _, line := range lines {
			trimmed := strings.TrimSpace(line)
			if strings.HasPrefix(trimmed, "name:") && (cfg.AppName == "EverUpApp" || cfg.AppName == "") {
				cfg.AppName = strings.TrimSpace(strings.TrimPrefix(trimmed, "name:"))
			}
			if strings.HasPrefix(trimmed, "version:") && (cfg.Version == "1.0.0" || cfg.Version == "") {
				ver := strings.TrimSpace(strings.TrimPrefix(trimmed, "version:"))
				if parts := strings.Split(ver, "+"); len(parts) > 0 {
					cfg.Version = parts[0]
				}
			}
		}
	}

	// 3. Detect AppID (applicationId / bundle identifier) from Android / iOS / macOS.
	if cfg.AppID == "com.example.everup" || cfg.AppID == "" {
		if appID := detectAppID(root); appID != "" {
			cfg.AppID = appID
		}
	}

	// 4. Detect available platforms from directory existence (if not explicitly customized in everup.json).
	if _, err := os.Stat(configPath); os.IsNotExist(err) {
		hasAndroid := isDirectory(filepath.Join(root, "android"))
		hasWindows := isDirectory(filepath.Join(root, "windows"))
		hasMacOS := isDirectory(filepath.Join(root, "macos"))
		hasIOS := isDirectory(filepath.Join(root, "ios"))

		if hasAndroid || hasWindows || hasMacOS || hasIOS {
			cfg.EnableAndroid = hasAndroid
			cfg.EnableWindows = hasWindows
			cfg.EnableMacOS = hasMacOS
			cfg.EnableIOS = hasIOS
		}
	}

	// 5. Detect Windows executable name from CMakeLists.txt or app name.
	if cfg.ExecutableName == "app.exe" || cfg.ExecutableName == "" {
		if exe := detectWindowsExecutable(root); exe != "" {
			cfg.ExecutableName = exe
		} else if cfg.AppName != "" && cfg.AppName != "EverUpApp" {
			cfg.ExecutableName = cfg.AppName + ".exe"
		}
	}

	// 6. Detect publisher from git config user.name.
	if cfg.Publisher == "EverUp Team" || cfg.Publisher == "" {
		cmd := exec.Command("git", "config", "user.name")
		cmd.Dir = root
		if out, err := cmd.Output(); err == nil {
			if user := strings.TrimSpace(string(out)); user != "" {
				cfg.Publisher = user
			}
		}
	}

	// 7. Detect existing public key if generated previously.
	if cfg.PublicKeyEd25519 == "" {
		publicKeyPath := filepath.Join(root, ".everup", "signing-public.key")
		if data, err := os.ReadFile(publicKeyPath); err == nil {
			cfg.PublicKeyEd25519 = strings.TrimSpace(string(data))
		}
	}

	return cfg
}

func detectAppID(root string) string {
	// Try android/app/build.gradle.kts
	if data, err := os.ReadFile(filepath.Join(root, "android", "app", "build.gradle.kts")); err == nil {
		re := regexp.MustCompile(`(?:applicationId|namespace)\s*=\s*"([^"]+)"`)
		if m := re.FindStringSubmatch(string(data)); len(m) > 1 {
			return m[1]
		}
	}

	// Try android/app/build.gradle
	if data, err := os.ReadFile(filepath.Join(root, "android", "app", "build.gradle")); err == nil {
		re := regexp.MustCompile(`(?:applicationId|namespace)\s*=?\s*['"]([^'"]+)['"]`)
		if m := re.FindStringSubmatch(string(data)); len(m) > 1 {
			return m[1]
		}
	}

	// Try android/app/src/main/AndroidManifest.xml
	if data, err := os.ReadFile(filepath.Join(root, "android", "app", "src", "main", "AndroidManifest.xml")); err == nil {
		re := regexp.MustCompile(`package\s*=\s*"([^"]+)"`)
		if m := re.FindStringSubmatch(string(data)); len(m) > 1 {
			return m[1]
		}
	}

	// Try ios/Runner.xcodeproj/project.pbxproj
	if data, err := os.ReadFile(filepath.Join(root, "ios", "Runner.xcodeproj", "project.pbxproj")); err == nil {
		re := regexp.MustCompile(`PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([a-zA-Z0-9._-]+);`)
		if m := re.FindStringSubmatch(string(data)); len(m) > 1 && !strings.Contains(m[1], "$") {
			return m[1]
		}
	}

	// Try macos/Runner.xcodeproj/project.pbxproj
	if data, err := os.ReadFile(filepath.Join(root, "macos", "Runner.xcodeproj", "project.pbxproj")); err == nil {
		re := regexp.MustCompile(`PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([a-zA-Z0-9._-]+);`)
		if m := re.FindStringSubmatch(string(data)); len(m) > 1 && !strings.Contains(m[1], "$") {
			return m[1]
		}
	}

	return ""
}

func detectWindowsExecutable(root string) string {
	cmakePath := filepath.Join(root, "windows", "CMakeLists.txt")
	if data, err := os.ReadFile(cmakePath); err == nil {
		re := regexp.MustCompile(`set\(BINARY_NAME\s+"?([^"\s\)]+)"?\)`)
		if m := re.FindStringSubmatch(string(data)); len(m) > 1 {
			exe := m[1]
			if !strings.HasSuffix(strings.ToLower(exe), ".exe") {
				exe += ".exe"
			}
			return exe
		}
	}
	return ""
}

func isDirectory(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.IsDir()
}
