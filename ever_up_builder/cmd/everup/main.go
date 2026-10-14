package main

import (
	"fmt"
	"os"

	"ever_up_builder/internal/asset"
	"ever_up_builder/internal/crypto"
	"ever_up_builder/internal/loader"
	"ever_up_builder/internal/tui"
)

func printHelp() {
	fmt.Print(`EverUp Builder — 跨平台流水线与发布脚手架

使用方法:
  everup <command> [arguments]

可用命令:
  init                     启动 TUI 交互式向导，配置并动态生成 CI/CD 及安装器脚本
  crop <image>             启动本地可视化 Web 裁剪服务，在浏览器中拖拽裁切主图标
  gen-assets <image> [out] 一键生成全套图标 (.ico, Inno wizard.bmp, 512.png)
  reload-scripts           重新扫描并列出 scripts/ 与 templates/ 目录下的所有脚本与模板
  gen-keys                 生成一对新的 Ed25519 数字签名公私钥

示例:
  everup init
  everup crop logo.png
  everup gen-assets logo.png assets/
`)
}

func main() {
	if len(os.Args) < 2 {
		printHelp()
		return
	}

	cmd := os.Args[1]

	switch cmd {
	case "init":
		rootDir := "."
		if len(os.Args) >= 3 {
			rootDir = os.Args[2]
		}
		if err := tui.RunInitWizard(rootDir); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}

	case "crop":
		if len(os.Args) < 3 {
			fmt.Println("Usage: everup crop <source_image> [output_image]")
			os.Exit(1)
		}
		srcImg := os.Args[2]
		destImg := "app_icon_cropped.png"
		if len(os.Args) >= 4 {
			destImg = os.Args[3]
		}
		if err := asset.StartCropperServer(srcImg, destImg); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}

	case "gen-assets":
		if len(os.Args) < 3 {
			fmt.Println("Usage: everup gen-assets <source_image> [output_dir]")
			os.Exit(1)
		}
		srcImg := os.Args[2]
		outDir := "assets"
		if len(os.Args) >= 4 {
			outDir = os.Args[3]
		}
		if err := asset.GenerateAllAssets(srcImg, outDir); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
		fmt.Printf("==> 成功生成全平台图标素材至目录: %s\n", outDir)

	case "reload-scripts":
		rootDir := "."
		if len(os.Args) >= 3 {
			rootDir = os.Args[2]
		}
		cat, err := loader.LoadCatalog(rootDir)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error loading catalog: %v\n", err)
			os.Exit(1)
		}
		cat.PrintSummary()

	case "gen-keys":
		kp, err := crypto.GenerateEd25519KeyPair()
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
		fmt.Println("==> Ed25519 密钥对已生成:")
		fmt.Printf("公钥 (Public Key / 客户端校验):  %s\n", kp.PublicKey)
		fmt.Printf("私钥 (Private Key / GitHub Secret): %s\n", kp.PrivateKey)

	case "help", "-h", "--help":
		printHelp()

	default:
		fmt.Printf("未知命令: %s\n\n", cmd)
		printHelp()
		os.Exit(1)
	}
}
