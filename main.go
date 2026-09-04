package main

import (
	"embed"

	"github.com/wailsapp/wails/v2"
	"github.com/wailsapp/wails/v2/pkg/options"
	"github.com/wailsapp/wails/v2/pkg/options/assetserver"
	"github.com/wailsapp/wails/v2/pkg/options/mac"
	"github.com/wailsapp/wails/v2/pkg/options/windows"
)

//go:embed all:frontend/dist
var assets embed.FS

func main() {
	pet := NewApp()
	err := wails.Run(&options.App{
		Title:            "牛来行情桌宠",
		Width:            182,
		Height:           204,
		DisableResize:    true,
		Frameless:        true,
		AlwaysOnTop:      true,
		BackgroundColour: &options.RGBA{R: 0, G: 0, B: 0, A: 0},
		AssetServer:      &assetserver.Options{Assets: assets},
		OnStartup:        pet.startup,
		OnShutdown:       pet.shutdown,
		Bind:             []interface{}{pet},
		Windows: &windows.Options{
			WebviewIsTransparent:              true,
			WindowIsTranslucent:               true,
			DisableWindowIcon:                 true,
			DisableFramelessWindowDecorations: true,
			BackdropType:                      windows.None,
		},
		// On macOS WindowIsTranslucent adds an NSVisualEffectView. In light
		// appearance that material becomes the white rectangle behind the pet.
		// Keep the WKWebView transparent and let the alpha-zero window colour
		// provide a genuinely clear desktop-pet background.
		Mac: &mac.Options{WebviewIsTransparent: true, WindowIsTranslucent: false},
	})
	if err != nil {
		println("牛来启动失败:", err.Error())
	}
}
