package asset

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"runtime"
	"strings"
	"time"

	"ever_up_builder/internal/web"
)

type cropPayload struct {
	ImageData string `json:"image_data"`
}

// StartCropperServer launches a local embedded web server and opens the default browser for cropping.
func StartCropperServer(srcImagePath, destImagePath string) error {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return fmt.Errorf("failed to bind local port: %w", err)
	}
	defer listener.Close()

	port := listener.Addr().(*net.TCPAddr).Port
	url := fmt.Sprintf("http://127.0.0.1:%d", port)

	mux := http.NewServeMux()
	doneChan := make(chan struct{})

	// Serve embedded static files
	staticHandler := http.FileServer(http.FS(web.StaticFS))
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/" {
			r.URL.Path = "/static/index.html"
		} else if !strings.HasPrefix(r.URL.Path, "/static/") {
			r.URL.Path = "/static" + r.URL.Path
		}
		staticHandler.ServeHTTP(w, r)
	})

	// Serve the source image
	mux.HandleFunc("/api/image", func(w http.ResponseWriter, r *http.Request) {
		http.ServeFile(w, r, srcImagePath)
	})

	// Receive cropped image data
	mux.HandleFunc("/api/crop", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}

		bodyBytes, err := io.ReadAll(r.Body)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}

		var payload cropPayload
		if err := json.Unmarshal(bodyBytes, &payload); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}

		// Parse base64 Data URL (e.g., data:image/png;base64,....)
		dataURL := payload.ImageData
		commaIdx := strings.Index(dataURL, ",")
		if commaIdx != -1 {
			dataURL = dataURL[commaIdx+1:]
		}

		imgBytes, err := base64.StdEncoding.DecodeString(dataURL)
		if err != nil {
			http.Error(w, "Failed to decode base64: "+err.Error(), http.StatusBadRequest)
			return
		}

		if err := os.WriteFile(destImagePath, imgBytes, 0644); err != nil {
			http.Error(w, "Failed to write file: "+err.Error(), http.StatusInternalServerError)
			return
		}

		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"status":"ok"}`))

		// Signal done to stop server
		go func() {
			time.Sleep(500 * time.Millisecond)
			close(doneChan)
		}()
	})

	server := &http.Server{Handler: mux}

	go func() {
		_ = server.Serve(listener)
	}()

	fmt.Printf("==> EverUp 图像裁剪服务已启动: %s\n", url)
	fmt.Println("==> 正在唤起系统默认浏览器...")
	openBrowser(url)

	// Wait until crop submitted
	<-doneChan
	_ = server.Shutdown(context.Background())
	fmt.Printf("==> 裁剪素材已保存至: %s\n", destImagePath)

	return nil
}

func openBrowser(url string) {
	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "darwin":
		cmd = exec.Command("open", url)
	case "windows":
		cmd = exec.Command("rundll32", "url.dll,FileProtocolHandler", url)
	default:
		cmd = exec.Command("xdg-open", url)
	}
	_ = cmd.Start()
}
