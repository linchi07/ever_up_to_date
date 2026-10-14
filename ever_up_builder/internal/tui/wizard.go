package tui

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"ever_up_builder/internal/crypto"
	"ever_up_builder/internal/generator"
	"ever_up_builder/internal/model"
	"github.com/charmbracelet/huh"
)

func RunInitWizard(root string) error {
	if _, err := os.Stat(filepath.Join(root, "pubspec.yaml")); err != nil {
		return fmt.Errorf("target must be a Flutter project: %w", err)
	}
	cfg, err := model.LoadConfig(root)
	if err != nil && !os.IsNotExist(err) {
		return err
	}
	if os.IsNotExist(err) {
		cfg = model.DefaultConfig()
		cfg.EnableAndroid, cfg.EnableWindows, cfg.EnableMacOS = true, true, true
		data, err := os.ReadFile(filepath.Join(root, "pubspec.yaml"))
		if err != nil {
			return err
		}
		for _, line := range strings.Split(string(data), "\n") {
			if strings.HasPrefix(line, "name:") {
				name := strings.TrimSpace(strings.TrimPrefix(line, "name:"))
				cfg.AppName, cfg.ExecutableName = name, name+".exe"
				break
			}
		}
	}
	var platforms []string
	generateKeys := cfg.PublicKeyEd25519 == ""
	injectSecret := false
	fmt.Println("EverUp Builder — 配置跨平台发布")
	form := huh.NewForm(
		huh.NewGroup(
			huh.NewInput().Title("应用名称").Value(&cfg.AppName),
			huh.NewInput().Title("App ID / Bundle ID").Value(&cfg.AppID),
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
			huh.NewConfirm().Title("使用 gh CLI 将已保存的私钥注入 GitHub Secrets？").Value(&injectSecret),
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
	if injectSecret {
		if !crypto.IsGhAvailable() {
			return fmt.Errorf("gh CLI is required for secret injection; local configuration was saved")
		}
		private, err := os.ReadFile(filepath.Join(root, ".everup", "signing-private.key"))
		if err != nil {
			return err
		}
		if err := crypto.SetGitHubSecretAt(root, "EVERUP_SIGNING_PRIVATE_KEY", strings.TrimSpace(string(private))); err != nil {
			return err
		}
	}
	fmt.Println("配置和发布文件已生成。请检查 everup.json、配置 GitHub Secrets，然后推送 v<版本> 标签或手动运行发布工作流。")
	return nil
}
