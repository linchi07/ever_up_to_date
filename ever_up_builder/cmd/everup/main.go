package main

import (
	"ever_up_builder/internal/asset"
	"ever_up_builder/internal/crypto"
	"ever_up_builder/internal/generator"
	"ever_up_builder/internal/loader"
	"ever_up_builder/internal/model"
	"ever_up_builder/internal/tui"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
)

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		os.Exit(1)
	}
}
func run(args []string) error {
	if len(args) == 0 {
		printHelp()
		return nil
	}
	root := "."
	if len(args) > 1 {
		root = args[1]
	}
	switch args[0] {
	case "init":
		return tui.RunInitWizard(root)
	case "generate":
		cfg, err := model.LoadConfig(root)
		if err != nil {
			return err
		}
		if err := generator.GenerateProject(root, cfg); err != nil {
			return err
		}
		fmt.Println("Generated workflow and platform scripts")
	case "doctor":
		failed := false
		if _, err := model.LoadConfig(root); err != nil {
			fmt.Fprintln(os.Stderr, "Configuration:", err)
			failed = true
		}
		for _, name := range []string{"flutter", "git", "go", "aws", "python3"} {
			if path, err := exec.LookPath(name); err != nil {
				fmt.Fprintln(os.Stderr, "Missing:", name)
				failed = true
			} else {
				fmt.Printf("%s: %s\n", name, path)
			}
		}
		if failed {
			return fmt.Errorf("resolve the reported configuration/dependency failures")
		}
	case "gen-keys":
		kp, err := crypto.EnsureKeyPair(root)
		if err != nil {
			return err
		}
		fmt.Printf("Public key: %s\nPrivate key saved in %s\n", kp.PublicKey, filepath.Join(root, ".everup", "signing-private.key"))
	case "crop":
		if len(args) < 2 {
			return fmt.Errorf("usage: everup crop <source_image> [output_image]")
		}
		out := "app_icon_cropped.png"
		if len(args) > 2 {
			out = args[2]
		}
		return asset.StartCropperServer(args[1], out)
	case "gen-assets":
		if len(args) < 2 {
			return fmt.Errorf("usage: everup gen-assets <source_image> [output_directory]")
		}
		out := "assets"
		if len(args) > 2 {
			out = args[2]
		}
		return asset.GenerateAllAssets(args[1], out)
	case "reload-scripts":
		catalog, err := loader.LoadCatalog(root)
		if err != nil {
			return err
		}
		catalog.PrintSummary()
	case "help", "-h", "--help":
		printHelp()
	default:
		return fmt.Errorf("unknown command: %s", args[0])
	}
	return nil
}
func printHelp() {
	fmt.Print(`EverUp Builder

  init [project]            Interactive project configuration
  generate [project]        Regenerate from everup.json
  doctor [project]          Validate configuration and local dependencies
  gen-keys [project]        Save or restore keys in .everup/ (private key is not printed)
  crop <image> [output]     Crop an image locally
  gen-assets <image> [out]  Generate Windows icon and installer assets
  reload-scripts [project]  List project scripts and templates
`)
}
