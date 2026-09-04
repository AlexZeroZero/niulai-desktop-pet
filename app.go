package main

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"math/rand"
	"mime"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	goruntime "runtime"
	"strconv"
	"strings"
	"sync"
	"time"
	_ "time/tzdata"

	"github.com/wailsapp/wails/v2/pkg/runtime"
	"github.com/zalando/go-keyring"
)

type Settings struct {
	Provider          string  `json:"provider"`
	MarketType        string  `json:"marketType"`
	Symbol            string  `json:"symbol"`
	DisplayName       string  `json:"displayName"`
	CryptoSymbol      string  `json:"cryptoSymbol"`
	CustomURL         string  `json:"customUrl"`
	CustomHeaders     string  `json:"customHeaders"`
	CustomValuePath   string  `json:"customValuePath"`
	CustomPercentPath string  `json:"customPercentPath"`
	PollSeconds       int     `json:"pollSeconds"`
	RiseThreshold     float64 `json:"riseThreshold"`
	FallThreshold     float64 `json:"fallThreshold"`
	SoundEnabled      bool    `json:"soundEnabled"`
	VoiceEnabled      bool    `json:"voiceEnabled"`
	CustomUpSound     string  `json:"customUpSound"`
	CustomDownSound   string  `json:"customDownSound"`
	CustomCowSound    string  `json:"customCowSound"`
	Volume            float64 `json:"volume"`
	AlwaysOnTop       bool    `json:"alwaysOnTop"`
	RunOnStartup      bool    `json:"runOnStartup"`
	PetSize           string  `json:"petSize"`
	StaleSleepMinutes int     `json:"staleSleepMinutes"`
}

type Quote struct {
	Provider  string  `json:"provider"`
	Name      string  `json:"name"`
	Symbol    string  `json:"symbol"`
	Price     float64 `json:"price"`
	Percent   float64 `json:"percent"`
	Change    float64 `json:"change"`
	Phase     string  `json:"phase"`
	Timestamp int64   `json:"timestamp"`
}

type App struct {
	ctx        context.Context
	mu         sync.RWMutex
	settings   Settings
	client     *http.Client
	dashCancel context.CancelFunc
}

func defaults() Settings {
	return Settings{Provider: "eastmoney", MarketType: "index", Symbol: "1.000001", DisplayName: "上证指数", CryptoSymbol: "BTCUSDT", CustomHeaders: "{}", CustomValuePath: "data.price", CustomPercentPath: "data.percent", PollSeconds: 15, RiseThreshold: .15, FallThreshold: -.15, SoundEnabled: true, VoiceEnabled: true, Volume: .85, AlwaysOnTop: true, PetSize: "small", StaleSleepMinutes: 3}
}

func NewApp() *App {
	return &App{settings: defaults(), client: &http.Client{Timeout: 9 * time.Second}}
}

func (a *App) startup(ctx context.Context) {
	a.ctx = ctx
	a.loadSettings()
	go func() { time.Sleep(180 * time.Millisecond); a.applyPetWindow(true) }()
}
func (a *App) shutdown(ctx context.Context) { a.StopDash() }

func settingsFile() string {
	base, err := os.UserConfigDir()
	if err != nil {
		base = "."
	}
	return filepath.Join(base, "NiulaiPet", "settings.json")
}
func (a *App) loadSettings() {
	b, err := os.ReadFile(settingsFile())
	if err == nil {
		_ = json.Unmarshal(b, &a.settings)
	}
	if a.settings.PetSize == "" {
		a.settings.PetSize = "small"
	}
	if a.settings.StaleSleepMinutes < 1 {
		a.settings.StaleSleepMinutes = 3
	}
	if secret, err := keyring.Get("NiulaiPet", "customHeaders"); err == nil && secret != "" {
		a.settings.CustomHeaders = secret
	}
}
func (a *App) GetSettings() Settings { a.mu.RLock(); defer a.mu.RUnlock(); return a.settings }
func (a *App) SaveSettings(next Settings) (Settings, error) {
	if next.PetSize != "medium" {
		next.PetSize = "small"
	}
	if next.PollSeconds < 5 {
		next.PollSeconds = 5
	}
	if next.PollSeconds > 3600 {
		next.PollSeconds = 3600
	}
	if next.StaleSleepMinutes < 1 {
		next.StaleSleepMinutes = 1
	}
	if next.StaleSleepMinutes > 120 {
		next.StaleSleepMinutes = 120
	}
	next.CryptoSymbol = normalizeCryptoSymbol(next.CryptoSymbol)
	if next.Provider == "eastmoney" {
		var err error
		next.Symbol, err = normalizeStockSymbol(next.Symbol)
		if err != nil {
			return next, err
		}
		if strings.TrimSpace(next.DisplayName) == "" {
			next.DisplayName = strings.TrimPrefix(strings.TrimPrefix(next.Symbol, "0."), "1.")
		}
	}
	if next.Volume < 0 {
		next.Volume = 0
	}
	if next.Volume > 1 {
		next.Volume = 1
	}
	a.mu.Lock()
	a.settings = next
	a.mu.Unlock()
	stored := next
	if next.CustomHeaders != "" && next.CustomHeaders != "{}" {
		if keyring.Set("NiulaiPet", "customHeaders", next.CustomHeaders) == nil {
			stored.CustomHeaders = "{}"
		}
	}
	b, _ := json.MarshalIndent(stored, "", "  ")
	file := settingsFile()
	if err := os.MkdirAll(filepath.Dir(file), 0700); err != nil {
		return next, err
	}
	if err := os.WriteFile(file, b, 0600); err != nil {
		return next, err
	}
	_ = setAutoStart(next.RunOnStartup)
	runtime.WindowSetAlwaysOnTop(a.ctx, next.AlwaysOnTop)
	return next, nil
}

func setAutoStart(enabled bool) error {
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	if goruntime.GOOS == "windows" {
		key := `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`
		if enabled {
			return exec.Command("reg", "add", key, "/v", "NiulaiPet", "/t", "REG_SZ", "/d", `"`+exe+`"`, "/f").Run()
		}
		return exec.Command("reg", "delete", key, "/v", "NiulaiPet", "/f").Run()
	}
	if goruntime.GOOS == "darwin" {
		home, err := os.UserHomeDir()
		if err != nil {
			return err
		}
		file := filepath.Join(home, "Library", "LaunchAgents", "com.niulai.desktop-pet.plist")
		if !enabled {
			if err := os.Remove(file); err != nil && !os.IsNotExist(err) {
				return err
			}
			return nil
		}
		if err := os.MkdirAll(filepath.Dir(file), 0700); err != nil {
			return err
		}
		content := `<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>Label</key><string>com.niulai.desktop-pet</string><key>ProgramArguments</key><array><string>` + strings.ReplaceAll(exe, "&", "&amp;") + `</string></array><key>RunAtLoad</key><true/></dict></plist>`
		return os.WriteFile(file, []byte(content), 0600)
	}
	return nil
}

func petDimensions(size string) (int, int) {
	if size == "medium" {
		return 226, 224
	}
	return 190, 180
}

func (a *App) applyPetWindow(place bool) {
	s := a.GetSettings()
	w, h := petDimensions(s.PetSize)
	runtime.WindowSetSize(a.ctx, w, h)
	runtime.WindowSetAlwaysOnTop(a.ctx, s.AlwaysOnTop)
	if place {
		a.placeBottomRight(w, h)
	}
}
func (a *App) placeBottomRight(w, h int) {
	screens, err := runtime.ScreenGetAll(a.ctx)
	if err != nil || len(screens) == 0 {
		return
	}
	s := screens[0]
	for _, candidate := range screens {
		if candidate.IsCurrent || candidate.IsPrimary {
			s = candidate
			if candidate.IsCurrent {
				break
			}
		}
	}
	runtime.WindowSetPosition(a.ctx, s.Size.Width-w-18, s.Size.Height-h-54)
}
func (a *App) OpenSettings() {
	a.StopDash()
	runtime.WindowSetSize(a.ctx, 520, 640)
	runtime.WindowCenter(a.ctx)
}
func (a *App) CloseSettings() { a.applyPetWindow(true) }
func (a *App) Quit()          { runtime.Quit(a.ctx) }
func (a *App) OpenSponsor()   { runtime.BrowserOpenURL(a.ctx, "https://www.aitroys.com/") }

func customAudioDirectory() string {
	return filepath.Join(filepath.Dir(settingsFile()), "audio")
}

func soundLabel(kind string) (string, bool) {
	switch kind {
	case "up":
		return "上涨台词", true
	case "down":
		return "下跌台词", true
	case "cow":
		return "牛叫音效", true
	default:
		return "", false
	}
}

// PickCustomSound copies the chosen file into NiulaiPet's private config
// directory. This keeps the setting valid even if the original file moves.
func (a *App) PickCustomSound(kind string) (string, error) {
	label, ok := soundLabel(kind)
	if !ok {
		return "", errors.New("未知声音类型")
	}
	selected, err := runtime.OpenFileDialog(a.ctx, runtime.OpenDialogOptions{
		Title: "选择" + label,
		Filters: []runtime.FileFilter{{
			DisplayName: "音频文件 (*.mp3;*.wav;*.ogg;*.m4a;*.aac)",
			Pattern:     "*.mp3;*.wav;*.ogg;*.m4a;*.aac",
		}},
	})
	if err != nil || selected == "" {
		return "", err
	}
	ext := strings.ToLower(filepath.Ext(selected))
	allowed := map[string]bool{".mp3": true, ".wav": true, ".ogg": true, ".m4a": true, ".aac": true}
	if !allowed[ext] {
		return "", errors.New("请选择 MP3、WAV、OGG、M4A 或 AAC 音频")
	}
	info, err := os.Stat(selected)
	if err != nil {
		return "", err
	}
	if info.Size() > 12<<20 {
		return "", errors.New("自定义声音不能超过 12 MB")
	}
	data, err := os.ReadFile(selected)
	if err != nil {
		return "", err
	}
	directory := customAudioDirectory()
	if err = os.MkdirAll(directory, 0700); err != nil {
		return "", err
	}
	destination := filepath.Join(directory, kind+ext)
	if err = os.WriteFile(destination, data, 0600); err != nil {
		return "", err
	}
	return destination, nil
}

// LoadCustomSound returns a browser-safe data URL, but only for files copied
// into the app-owned audio directory by PickCustomSound.
func (a *App) LoadCustomSound(path string) (string, error) {
	if strings.TrimSpace(path) == "" {
		return "", nil
	}
	root, err := filepath.Abs(customAudioDirectory())
	if err != nil {
		return "", err
	}
	absolute, err := filepath.Abs(path)
	if err != nil {
		return "", err
	}
	relative, err := filepath.Rel(root, absolute)
	if err != nil || relative == ".." || strings.HasPrefix(relative, ".."+string(os.PathSeparator)) {
		return "", errors.New("自定义声音路径无效")
	}
	data, err := os.ReadFile(absolute)
	if err != nil {
		return "", err
	}
	if len(data) > 12<<20 {
		return "", errors.New("自定义声音不能超过 12 MB")
	}
	mediaType := mime.TypeByExtension(strings.ToLower(filepath.Ext(absolute)))
	if mediaType == "" {
		mediaType = "audio/mpeg"
	}
	return "data:" + mediaType + ";base64," + base64.StdEncoding.EncodeToString(data), nil
}

func (a *App) MoveBy(dx, dy int) {
	x, y := runtime.WindowGetPosition(a.ctx)
	runtime.WindowSetPosition(a.ctx, x+dx, y+dy)
}
func (a *App) StartDash(direction int) {
	a.StopDash()
	if direction >= 0 {
		direction = 1
	} else {
		direction = -1
	}
	ctx, cancel := context.WithCancel(context.Background())
	a.mu.Lock()
	a.dashCancel = cancel
	a.mu.Unlock()
	go func(dir int) {
		ticker := time.NewTicker(16 * time.Millisecond)
		defer ticker.Stop()
		// Match the authored 6.04-second Vidu run reaction. Keeping the native
		// window movement and sprite playback aligned avoids a final static slide.
		timer := time.NewTimer(6 * time.Second)
		defer timer.Stop()
		random := rand.New(rand.NewSource(time.Now().UnixNano()))
		x, y := runtime.WindowGetPosition(a.ctx)
		w, h := runtime.WindowGetSize(a.ctx)
		screenWidth, screenHeight := 1920, 1080
		if screens, err := runtime.ScreenGetAll(a.ctx); err == nil {
			for _, screen := range screens {
				if screen.IsCurrent || screen.IsPrimary {
					screenWidth, screenHeight = screen.Size.Width, screen.Size.Height
					if screen.IsCurrent {
						break
					}
				}
			}
		}
		minX, minY := 8.0, 8.0
		maxX := math.Max(minX, float64(screenWidth-w-8))
		// Leave the taskbar area clear while still allowing visible vertical runs.
		maxY := math.Max(minY, float64(screenHeight-h-48))
		px := math.Max(minX, math.Min(maxX, float64(x)))
		py := math.Max(minY, math.Min(maxY, float64(y)))
		heading := 0.0
		if dir < 0 {
			heading = math.Pi
		}
		targetHeading := heading
		speed := 54.0
		changeCourseAt := time.Now()
		lastTick := time.Now()
		lastFacing := dir

		chooseCourse := func(now time.Time) {
			// Bias each choice toward a gentle curve instead of a sudden reversal.
			targetHeading = heading + (random.Float64()*2-1)*1.35
			if px < minX+70 {
				targetHeading = (random.Float64() - .5) * 1.35
			} else if px > maxX-70 {
				targetHeading = math.Pi + (random.Float64()-.5)*1.35
			}
			if py < minY+60 && math.Sin(targetHeading) < 0 {
				targetHeading = -targetHeading
			} else if py > maxY-60 && math.Sin(targetHeading) > 0 {
				targetHeading = -targetHeading
			}
			speed = 46 + random.Float64()*16
			changeCourseAt = now.Add(time.Duration(900+random.Intn(501)) * time.Millisecond)
		}
		chooseCourse(time.Now())
		for {
			select {
			case <-ctx.Done():
				return
			case <-timer.C:
				a.StopDash()
				return
			case <-ticker.C:
				now := time.Now()
				dt := now.Sub(lastTick).Seconds()
				lastTick = now
				if dt <= 0 || dt > .08 {
					dt = .016
				}
				if !now.Before(changeCourseAt) {
					chooseCourse(now)
				}
				delta := math.Mod(targetHeading-heading+math.Pi*3, math.Pi*2) - math.Pi
				maxTurn := 1.45 * dt
				if delta > maxTurn {
					delta = maxTurn
				} else if delta < -maxTurn {
					delta = -maxTurn
				}
				heading += delta
				nextX := px + math.Cos(heading)*speed*dt
				nextY := py + math.Sin(heading)*speed*dt
				if nextX < minX || nextX > maxX {
					heading = math.Pi - heading
					targetHeading = math.Pi - targetHeading
					nextX = math.Max(minX, math.Min(maxX, nextX))
				}
				if nextY < minY || nextY > maxY {
					heading = -heading
					targetHeading = -targetHeading
					nextY = math.Max(minY, math.Min(maxY, nextY))
				}
				px, py = nextX, nextY
				newFacing := 1
				if math.Cos(heading) < 0 {
					newFacing = -1
				}
				if newFacing != lastFacing {
					lastFacing = newFacing
					runtime.EventsEmit(a.ctx, "pet-direction", newFacing)
				}
				runtime.WindowSetPosition(a.ctx, int(math.Round(px)), int(math.Round(py)))
			}
		}
	}(direction)
}
func (a *App) StopDash() {
	a.mu.Lock()
	if a.dashCancel != nil {
		a.dashCancel()
		a.dashCancel = nil
	}
	a.mu.Unlock()
}

func chinaPhase(now time.Time) string {
	loc, _ := time.LoadLocation("Asia/Shanghai")
	n := now.In(loc)
	if n.Weekday() == time.Saturday || n.Weekday() == time.Sunday {
		return "closed"
	}
	m := n.Hour()*60 + n.Minute()
	if m >= 690 && m < 780 {
		return "lunch"
	}
	if (m >= 570 && m < 690) || (m >= 780 && m < 900) {
		return "open"
	}
	return "closed"
}
func (a *App) getJSON(rawURL string, headers map[string]string) (any, error) {
	req, err := http.NewRequest(http.MethodGet, rawURL, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "NiulaiDesktopPet/0.3")
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	resp, err := a.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("HTTP %d", resp.StatusCode)
	}
	b, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if err != nil {
		return nil, err
	}
	var value any
	if err = json.Unmarshal(b, &value); err != nil {
		return nil, err
	}
	return value, nil
}
func number(v any) float64 {
	switch n := v.(type) {
	case float64:
		return n
	case json.Number:
		f, _ := n.Float64()
		return f
	case string:
		f, _ := strconv.ParseFloat(n, 64)
		return f
	}
	return 0
}
func str(v any) string {
	if s, ok := v.(string); ok {
		return s
	}
	return fmt.Sprint(v)
}
func mapAt(v any, path string) any {
	cur := v
	for _, key := range strings.Split(path, ".") {
		m, ok := cur.(map[string]any)
		if !ok {
			return nil
		}
		cur = m[key]
	}
	return cur
}

func normalizeStockSymbol(raw string) (string, error) {
	value := strings.ToUpper(strings.TrimSpace(raw))
	value = strings.NewReplacer(" ", "", "-", "", "_", "").Replace(value)
	if len(value) == 8 && (strings.HasPrefix(value, "0.") || strings.HasPrefix(value, "1.")) {
		if _, err := strconv.Atoi(value[2:]); err == nil {
			return value, nil
		}
	}
	market := ""
	for prefix, id := range map[string]string{"SH": "1", "SZ": "0", "BJ": "0"} {
		if strings.HasPrefix(value, prefix) {
			market = id
			value = strings.TrimPrefix(value, prefix)
			break
		}
	}
	if len(value) != 6 {
		return "", errors.New("A股代码应为6位数字，例如 600519、000001 或 SH600519")
	}
	if _, err := strconv.Atoi(value); err != nil {
		return "", errors.New("A股代码应为6位数字，例如 600519、000001 或 SH600519")
	}
	if market == "" {
		if strings.HasPrefix(value, "6") {
			market = "1"
		} else {
			market = "0"
		}
	}
	return market + "." + value, nil
}

func normalizeCryptoSymbol(raw string) string {
	symbol := strings.ToUpper(strings.TrimSpace(raw))
	symbol = strings.NewReplacer("-", "", "_", "", "/", "", " ", "").Replace(symbol)
	if symbol == "" {
		return "BTCUSDT"
	}
	for _, quote := range []string{"FDUSD", "USDT", "USDC", "TUSD", "BUSD", "BTC", "ETH"} {
		if len(symbol) > len(quote) && strings.HasSuffix(symbol, quote) {
			return symbol
		}
	}
	return symbol + "USDT"
}

func splitCryptoSymbol(symbol string) (string, string) {
	for _, quote := range []string{"FDUSD", "USDT", "USDC", "TUSD", "BUSD", "BTC", "ETH"} {
		if len(symbol) > len(quote) && strings.HasSuffix(symbol, quote) {
			return strings.TrimSuffix(symbol, quote), quote
		}
	}
	return strings.TrimSuffix(symbol, "USDT"), "USDT"
}

func (a *App) GetQuote() (Quote, error) {
	s := a.GetSettings()
	if s.Provider == "eastmoney" {
		endpoint := "https://push2.eastmoney.com/api/qt/stock/get?secid=" + url.QueryEscape(s.Symbol) + "&fields=f43,f57,f58,f86,f169,f170"
		root, err := a.getJSON(endpoint, nil)
		if err != nil {
			return Quote{}, err
		}
		data, ok := mapAt(root, "data").(map[string]any)
		if !ok {
			return Quote{}, errors.New("东方财富未返回该证券数据")
		}
		phase := chinaPhase(time.Now())
		ts := int64(number(data["f86"])) * 1000
		if phase == "open" && ts > 0 && time.Now().UnixMilli()-ts > 20*60*1000 {
			phase = "closed"
		}
		return Quote{Provider: "eastmoney", Name: str(data["f58"]), Symbol: str(data["f57"]), Price: number(data["f43"]) / 100, Percent: number(data["f170"]) / 100, Change: number(data["f169"]) / 100, Phase: phase, Timestamp: ts}, nil
	}
	if s.Provider == "binance" {
		symbol := normalizeCryptoSymbol(s.CryptoSymbol)
		base, quoteCurrency := splitCryptoSymbol(symbol)
		var lastErr error

		// These public spot endpoints are tried before Binance because they are
		// commonly reachable on mainland networks and require no API key.
		okxRoot, err := a.getJSON("https://www.okx.com/api/v5/market/ticker?instId="+url.QueryEscape(base+"-"+quoteCurrency), nil)
		if err == nil {
			if data, ok := mapAt(okxRoot, "data").([]any); ok && len(data) > 0 {
				if ticker, ok := data[0].(map[string]any); ok {
					price, open := number(ticker["last"]), number(ticker["open24h"])
					if price > 0 && open > 0 {
						change := price - open
						return Quote{Provider: "okx", Name: symbol, Symbol: symbol, Price: price, Percent: change / open * 100, Change: change, Phase: "open", Timestamp: time.Now().UnixMilli()}, nil
					}
				}
			}
			lastErr = errors.New("OKX 未返回有效价格")
		} else {
			lastErr = err
		}

		gateRoot, err := a.getJSON("https://api.gateio.ws/api/v4/spot/tickers?currency_pair="+url.QueryEscape(base+"_"+quoteCurrency), nil)
		if err == nil {
			if data, ok := gateRoot.([]any); ok && len(data) > 0 {
				if ticker, ok := data[0].(map[string]any); ok {
					price := number(ticker["last"])
					percent := number(ticker["change_percentage"])
					if price > 0 {
						return Quote{Provider: "gate", Name: symbol, Symbol: symbol, Price: price, Percent: percent, Phase: "open", Timestamp: time.Now().UnixMilli()}, nil
					}
				}
			}
			lastErr = errors.New("Gate.io 未返回有效价格")
		} else {
			lastErr = err
		}

		huobiRoot, err := a.getJSON("https://api.huobi.pro/market/detail/merged?symbol="+url.QueryEscape(strings.ToLower(symbol)), nil)
		if err == nil {
			if ticker, ok := mapAt(huobiRoot, "tick").(map[string]any); ok {
				price, open := number(ticker["close"]), number(ticker["open"])
				if price > 0 && open > 0 {
					change := price - open
					return Quote{Provider: "huobi", Name: symbol, Symbol: symbol, Price: price, Percent: change / open * 100, Change: change, Phase: "open", Timestamp: time.Now().UnixMilli()}, nil
				}
			}
			lastErr = errors.New("火币未返回有效价格")
		} else {
			lastErr = err
		}

		endpoints := []string{
			"https://data-api.binance.vision",
			"https://api.binance.com",
			"https://api1.binance.com",
			"https://api2.binance.com",
			"https://api3.binance.com",
		}
		for _, endpoint := range endpoints {
			root, err := a.getJSON(endpoint+"/api/v3/ticker/24hr?symbol="+url.QueryEscape(symbol), nil)
			if err != nil {
				lastErr = err
				continue
			}
			price := number(mapAt(root, "lastPrice"))
			if price <= 0 {
				lastErr = errors.New("Binance 未返回有效价格")
				continue
			}
			return Quote{Provider: "binance", Name: symbol, Symbol: symbol, Price: price, Percent: number(mapAt(root, "priceChangePercent")), Change: number(mapAt(root, "priceChange")), Phase: "open", Timestamp: time.Now().UnixMilli()}, nil
		}

		coinIDs := map[string]string{"BTC": "bitcoin", "ETH": "ethereum", "BNB": "binancecoin", "SOL": "solana", "XRP": "ripple", "DOGE": "dogecoin", "ADA": "cardano"}
		if coinID, ok := coinIDs[base]; ok && (quoteCurrency == "USDT" || quoteCurrency == "USDC") {
			root, err := a.getJSON("https://api.coingecko.com/api/v3/simple/price?ids="+coinID+"&vs_currencies=usd&include_24hr_change=true", nil)
			if err == nil {
				price := number(mapAt(root, coinID+".usd"))
				if price > 0 {
					return Quote{Provider: "coingecko", Name: symbol, Symbol: symbol, Price: price, Percent: number(mapAt(root, coinID+".usd_24h_change")), Phase: "open", Timestamp: time.Now().UnixMilli()}, nil
				}
			}
			lastErr = err
		}
		if lastErr == nil {
			lastErr = errors.New("数字货币行情暂时不可用")
		}
		return Quote{}, fmt.Errorf("数字货币行情获取失败: %w", lastErr)
	}
	if s.Provider == "custom" {
		u, err := url.Parse(s.CustomURL)
		if err != nil || u.Scheme != "https" {
			return Quote{}, errors.New("自定义 API 必须使用 HTTPS")
		}
		headers := map[string]string{}
		if err = json.Unmarshal([]byte(s.CustomHeaders), &headers); err != nil {
			return Quote{}, errors.New("请求头不是有效 JSON")
		}
		root, err := a.getJSON(s.CustomURL, headers)
		if err != nil {
			return Quote{}, err
		}
		price := number(mapAt(root, s.CustomValuePath))
		percent := number(mapAt(root, s.CustomPercentPath))
		if price == 0 && mapAt(root, s.CustomValuePath) == nil {
			return Quote{}, errors.New("价格字段路径无效")
		}
		return Quote{Provider: "custom", Name: s.DisplayName, Symbol: s.Symbol, Price: price, Percent: percent, Phase: "open", Timestamp: time.Now().UnixMilli()}, nil
	}
	return Quote{}, errors.New("未知行情源")
}
