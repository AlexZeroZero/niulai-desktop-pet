package main

import (
	"os"
	"testing"
)

func TestNormalizeCryptoSymbolDefaultsToUSDT(t *testing.T) {
	tests := map[string]string{
		"":          "BTCUSDT",
		"btc":       "BTCUSDT",
		" eth ":     "ETHUSDT",
		"sol/usdt":  "SOLUSDT",
		"DOGE-USDC": "DOGEUSDC",
		"ETHBTC":    "ETHBTC",
	}
	for input, want := range tests {
		if got := normalizeCryptoSymbol(input); got != want {
			t.Errorf("normalizeCryptoSymbol(%q) = %q, want %q", input, got, want)
		}
	}
}

func TestSplitCryptoSymbol(t *testing.T) {
	base, quote := splitCryptoSymbol("BTCUSDT")
	if base != "BTC" || quote != "USDT" {
		t.Fatalf("splitCryptoSymbol returned %q/%q", base, quote)
	}
}

func TestNormalizeStockSymbol(t *testing.T) {
	tests := map[string]string{
		"600519":   "1.600519",
		"SH600519": "1.600519",
		"000001":   "0.000001",
		"sz300750": "0.300750",
		"BJ920001": "0.920001",
		"1.000001": "1.000001",
	}
	for input, want := range tests {
		got, err := normalizeStockSymbol(input)
		if err != nil {
			t.Fatalf("normalizeStockSymbol(%q) returned error: %v", input, err)
		}
		if got != want {
			t.Errorf("normalizeStockSymbol(%q) = %q, want %q", input, got, want)
		}
	}
	if _, err := normalizeStockSymbol("abc"); err == nil {
		t.Fatal("normalizeStockSymbol should reject invalid codes")
	}
}

func TestLiveCryptoFallbackChain(t *testing.T) {
	if os.Getenv("NIULAI_LIVE_TEST") != "1" {
		t.Skip("set NIULAI_LIVE_TEST=1 to call public market endpoints")
	}
	app := NewApp()
	app.settings.Provider = "binance"
	app.settings.CryptoSymbol = "eth"
	quote, err := app.GetQuote()
	if err != nil {
		t.Fatal(err)
	}
	if quote.Symbol != "ETHUSDT" || quote.Price <= 0 {
		t.Fatalf("unexpected quote: %+v", quote)
	}
	t.Logf("provider=%s symbol=%s price=%f percent=%f", quote.Provider, quote.Symbol, quote.Price, quote.Percent)
}
