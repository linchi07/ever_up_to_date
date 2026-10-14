package tui

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"ever_up_builder/internal/crypto"
	"ever_up_builder/internal/detector"
	"ever_up_builder/internal/generator"
	"ever_up_builder/internal/secrets"
	"github.com/charmbracelet/huh"
)

func RunInitWizard(root string) error {
	if _, err := os.Stat(filepath.Join(root, "pubspec.yaml")); err != nil {
		return fmt.Errorf("target must be a Flutter project: %w", err)
	}

	// 智能自动检测项目信息（包名、应用名、版本号、已有平台、可执行文件名、发布者及历史配置）
	cfg := detector.DetectFlutterProject(root)

	var platforms []string
	generateKeys := cfg.PublicKeyEd25519 == ""
	injectSecret := false
	fmt.Println("EverUp Builder — 配置跨平台发布（已自动检测并预填项目属性）")
	form := huh.NewForm(
		huh.NewGroup(
			huh.NewInput().Title("应用名称").Value(&cfg.AppName),
			huh.NewInput().Title("App ID / Bundle ID (已自动识别)").Value(&cfg.AppID),
			huh.NewInput().Title("发布者").Value(&cfg.Publisher),
			huh.NewInput().Title("Windows 可执行文件名").Value(&cfg.ExecutableName),
		),
		huh.NewGroup(huh.NewMultiSelect[string]().Title("目标平台").Options(
			huh.NewOption("Android APK", "android").Selected(cfg.EnableAndroid),
			huh.NewOption("Windows Inno Setup", "windows").Selected(cfg.EnableWindows),
			huh.NewOption("macOS DMG", "macos").Selected(cfg.EnableMacOS),
			huh.NewOption("iOS 商店导流", "ios").Selected(cfg.EnableIOS),
		).Value(&platforms)),
		huh.NewGroup(
			huh.NewInput().Title("S3 Bucket").Value(&cfg.S3Bucket),
			huh.NewInput().Title("S3 Endpoint（可选）").Value(&cfg.S3Endpoint),
			huh.NewInput().Title("S3 Region").Value(&cfg.S3Region),
			huh.NewInput().Title("S3 对象前缀（可选）").Value(&cfg.S3Prefix),
			huh.NewInput().Title("Manifest URL（以 /appcast.json 结尾）").Value(&cfg.ManifestURL),
			huh.NewInput().Title("iOS 商店 / TestFlight 地址（启用 iOS 时必填）").Value(&cfg.IOSStoreURL),
		),
		huh.NewGroup(
			huh.NewSelect[int]().Title("灰度发布比例").Options(huh.NewOption("全部设备 (100%)", 100), huh.NewOption("50%", 50), huh.NewOption("25%", 25), huh.NewOption("10%", 10), huh.NewOption("暂停分发 (0%)", 0)).Value(&cfg.RolloutPercentage),
			huh.NewConfirm().Title("发布时要求平台代码签名？").Value(&cfg.RequirePlatformSigning),
			huh.NewConfirm().Title("生成或恢复本地 Ed25519 密钥？").Description("已保存的私钥会保留；不会在终端输出私钥。").Value(&generateKeys),
			huh.NewInput().Title("Ed25519 公钥（使用已有密钥时填写）").Value(&cfg.PublicKeyEd25519),
			huh.NewConfirm().Title("使用 gh CLI 将通用密钥组(包含签名私钥)注入 GitHub Secrets？").Value(&injectSecret),
		),
	)
	if err := form.Run(); err != nil {
		return fmt.Errorf("wizard cancelled: %w", err)
	}
	cfg.EnableAndroid, cfg.EnableWindows, cfg.EnableMacOS, cfg.EnableIOS = false, false, false, false
	for _, platform := range platforms {
		switch platform {
		case "android":
			cfg.EnableAndroid = true
		case "windows":
			cfg.EnableWindows = true
		case "macos":
			cfg.EnableMacOS = true
		case "ios":
			cfg.EnableIOS = true
		}
	}
	if generateKeys {
		kp, err := crypto.EnsureKeyPair(root)
		if err != nil {
			return err
		}
		cfg.PublicKeyEd25519 = kp.PublicKey
		fmt.Printf("公钥: %s\n私钥已保存至 .everup/signing-private.key，请安全备份。\n", kp.PublicKey)
	}
	if err := generator.GenerateProject(root, cfg); err != nil {
		return err
	}

	bundles := secrets.GenerateSecretTemplates(root, cfg)
	fmt.Print("\n" + secrets.FormatSecretsSummary(bundles))

	if injectSecret {
		if !crypto.IsGhAvailable() {
			return fmt.Errorf("gh CLI is required for secret injection; local configuration was saved")
		}
		if commonJSON, ok := bundles["EVERUP_COMMON_SECRETS"]; ok {
			if err := crypto.SetGitHubSecretAt(root, "EVERUP_COMMON_SECRETS", commonJSON); err != nil {
				return err
			}
		}
		private, err := os.ReadFile(filepath.Join(root, ".everup", "signing-private.key"))
		if err == nil {
			_ = crypto.SetGitHubSecretAt(root, "EVERUP_SIGNING_PRIVATE_KEY", strings.TrimSpace(string(private)))
		}
		fmt.Println("已通过 gh CLI 成功注入 EVERUP_COMMON_SECRETS 与 EVERUP_SIGNING_PRIVATE_KEY！")
	}
	fmt.Println("配置和发布文件已生成。请检查 everup.json、配置上述 GitHub Secrets，然后推送 v<版本> 标签或手动运行发布工作流。")
	return nil
}
