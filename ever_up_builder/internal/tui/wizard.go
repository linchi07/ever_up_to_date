package tui

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/charmbracelet/huh"
	"github.com/charmbracelet/lipgloss"

	"ever_up_builder/internal/crypto"
	"ever_up_builder/internal/generator"
	"ever_up_builder/internal/loader"
	"ever_up_builder/internal/model"
)

var (
	titleStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(lipgloss.Color("#6366f1")).
			MarginBottom(1)

	successStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(lipgloss.Color("#22c55e"))

	mutedStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#94a3b8"))
)

// RunInitWizard launches the interactive terminal wizard for EverUp.
func RunInitWizard(rootDir string) error {
	fmt.Println(titleStyle.Render("🚀 EverUp Builder — 跨平台流水线与发布脚手架"))
	fmt.Println(mutedStyle.Render("正在扫描本地脚本与模板目录...\n"))

	catalog, err := loader.LoadCatalog(rootDir)
	if err == nil {
		catalog.PrintSummary()
		fmt.Println()
	}

	cfg := model.ProjectConfig{
		AppName:        "EverUpApp",
		AppID:          "com.example.everup",
		Version:        "1.0.0",
		Publisher:      "EverUp Team",
		ExecutableName: "app.exe",
		S3Bucket:       "my-updates-bucket",
		ManifestURL:    "https://my-bucket.s3.amazonaws.com/appcast.json",
	}

	var selectedPlatforms []string
	autoGenKeys := true
	autoInjectGhSecret := true

	form := huh.NewForm(
		huh.NewGroup(
			huh.NewInput().
				Title("应用名称 (App Name)").
				Value(&cfg.AppName),

			huh.NewInput().
				Title("应用唯一标识 (App ID / Bundle ID)").
				Value(&cfg.AppID),

			huh.NewInput().
				Title("开发者 / 发布者名称 (Publisher)").
				Value(&cfg.Publisher),
		),

		huh.NewGroup(
			huh.NewMultiSelect[string]().
				Title("选择构建目标平台 (Target Platforms)").
				Options(
					huh.NewOption("Android (APK 直装)", "android").Selected(true),
					huh.NewOption("Windows (Inno Setup 现代静默安装)", "windows").Selected(true),
					huh.NewOption("macOS (DMG 镜像打包)", "macos").Selected(true),
					huh.NewOption("iOS (TestFlight / App Store 导流)", "ios"),
				).
				Value(&selectedPlatforms),
		),

		huh.NewGroup(
			huh.NewInput().
				Title("S3 兼容存储桶名称 (Bucket Name)").
				Value(&cfg.S3Bucket),

			huh.NewInput().
				Title("S3 自定义 Endpoint (可选，如 Cloudflare R2 / 阿里云 OSS)").
				Value(&cfg.S3Endpoint),

			huh.NewInput().
				Title("静态 Appcast Manifest 线上访问地址").
				Value(&cfg.ManifestURL),
		),

		huh.NewGroup(
			huh.NewConfirm().
				Title("是否自动生成 Ed25519 签名密钥对？").
				Description("用于防止安装包被恶意篡改，客户端将严格验证此数字签名。").
				Value(&autoGenKeys),

			huh.NewConfirm().
				Title("是否使用 gh CLI 自动将私钥注入到 GitHub Secrets？").
				Description("自动执行 `gh secret set EVERUP_SIGNING_PRIVATE_KEY`").
				Value(&autoInjectGhSecret),
		),
	)

	if err := form.Run(); err != nil {
		return fmt.Errorf("wizard cancelled: %w", err)
	}

	for _, p := range selectedPlatforms {
		switch p {
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

	fmt.Println("\n==> 正在生成配置与脚本...")

	if autoGenKeys {
		kp, err := crypto.GenerateEd25519KeyPair()
		if err != nil {
			fmt.Printf("⚠️ 生成密钥对失败: %v\n", err)
		} else {
			cfg.PublicKeyEd25519 = kp.PublicKey
			cfg.PrivateKeyEd25519 = kp.PrivateKey
			fmt.Printf("✓ 已生成 Ed25519 公钥: %s\n", kp.PublicKey)

			if autoInjectGhSecret && crypto.IsGhAvailable() {
				if err := crypto.SetGitHubSecret("EVERUP_SIGNING_PRIVATE_KEY", kp.PrivateKey); err != nil {
					fmt.Printf("⚠️ 注入 GitHub Secret 失败: %v\n", err)
				} else {
					fmt.Println("✓ 已通过 gh CLI 成功注入 GitHub Secret: EVERUP_SIGNING_PRIVATE_KEY")
				}
			}
		}
	}

	tmplCtx := model.TemplateContext{
		AppName:        cfg.AppName,
		AppID:          cfg.AppID,
		Version:        cfg.Version,
		Publisher:      cfg.Publisher,
		ExecutableName: cfg.ExecutableName,
		SourceDir:      `build\windows\runner\Release`,
		IconPath:       `windows\runner\resources\app_icon.ico`,
		EnableAndroid:  cfg.EnableAndroid,
		EnableWindows:  cfg.EnableWindows,
		EnableMacOS:    cfg.EnableMacOS,
		EnableIOS:      cfg.EnableIOS,
		S3Bucket:       cfg.S3Bucket,
		S3Endpoint:     cfg.S3Endpoint,
	}

	// 1. Generate GitHub Actions workflow
	if err := generator.GenerateGitHubWorkflow(rootDir, tmplCtx); err != nil {
		fmt.Printf("⚠️ 生成 GitHub Actions 失败: %v\n", err)
	} else {
		fmt.Println("✓ 已生成流水线: .github/workflows/everup_release.yml")
	}

	// 2. Generate Inno Setup script if Windows enabled
	if cfg.EnableWindows {
		if err := generator.GenerateInnoScript(rootDir, tmplCtx); err != nil {
			fmt.Printf("⚠️ 生成 Inno Setup 脚本失败: %v\n", err)
		} else {
			fmt.Println("✓ 已生成安装器脚本: build/windows/installer.iss")
		}
	}

	// 3. Generate initial appcast.json if missing
	appcastPath := filepath.Join(rootDir, "appcast.json")
	if _, err := os.Stat(appcastPath); os.IsNotExist(err) {
		initialJSON := fmt.Sprintf(`{
  "version": 1,
  "app_id": "%s",
  "channels": {
    "beta": {
      "version": "1.0.0",
      "build_number": 1,
      "mandatory": false,
      "pub_date": "2026-10-14T12:00:00Z",
      "release_notes": {
        "zh-CN": "1. 初始构建版本发布",
        "en-US": "1. Initial build release"
      },
      "platforms": {}
    }
  }
}
`, cfg.AppID)
		_ = os.WriteFile(appcastPath, []byte(initialJSON), 0644)
		fmt.Println("✓ 已生成初始 Appcast: appcast.json")
	}

	fmt.Println("\n" + successStyle.Render("🎉 EverUp 配置初始化完成！"))
	fmt.Println(mutedStyle.Render("你现在可以使用 `git push` 推送代码到 GitHub 触发自动化构建！"))

	return nil
}
