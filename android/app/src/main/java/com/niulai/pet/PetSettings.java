package com.niulai.pet;

import android.content.Context;
import android.content.SharedPreferences;

import java.util.Locale;

final class PetSettings {
    static final String PREFS = "niulai_settings";

    String provider = "eastmoney";
    String symbol = "1.000001";
    String displayName = "上证指数";
    String cryptoSymbol = "BTCUSDT";
    String customUrl = "";
    String customHeaders = "{}";
    String customValuePath = "data.price";
    String customPercentPath = "data.percent";
    int pollSeconds = 15;
    float riseThreshold = 0.15f;
    float fallThreshold = -0.15f;
    boolean soundEnabled = true;
    boolean voiceEnabled = true;
    boolean autoStart = false;
    String petSize = "small";
    int staleSleepMinutes = 3;
    String niulaiSoundUri = "";
    String mamaSoundUri = "";
    String mieSoundUri = "";

    static PetSettings load(Context context) {
        SharedPreferences p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        PetSettings s = new PetSettings();
        s.provider = p.getString("provider", s.provider);
        s.symbol = p.getString("symbol", s.symbol);
        s.displayName = p.getString("displayName", s.displayName);
        s.cryptoSymbol = p.getString("cryptoSymbol", s.cryptoSymbol);
        s.customUrl = p.getString("customUrl", s.customUrl);
        s.customHeaders = p.getString("customHeaders", s.customHeaders);
        s.customValuePath = p.getString("customValuePath", s.customValuePath);
        s.customPercentPath = p.getString("customPercentPath", s.customPercentPath);
        s.pollSeconds = clamp(p.getInt("pollSeconds", s.pollSeconds), 5, 3600);
        s.riseThreshold = p.getFloat("riseThreshold", s.riseThreshold);
        s.fallThreshold = p.getFloat("fallThreshold", s.fallThreshold);
        s.soundEnabled = p.getBoolean("soundEnabled", s.soundEnabled);
        s.voiceEnabled = p.getBoolean("voiceEnabled", s.voiceEnabled);
        s.autoStart = p.getBoolean("autoStart", s.autoStart);
        s.petSize = p.getString("petSize", s.petSize);
        s.staleSleepMinutes = clamp(p.getInt("staleSleepMinutes", s.staleSleepMinutes), 1, 120);
        s.niulaiSoundUri = p.getString("niulaiSoundUri", "");
        s.mamaSoundUri = p.getString("mamaSoundUri", "");
        s.mieSoundUri = p.getString("mieSoundUri", "");
        return s;
    }

    void save(Context context) {
        provider = normalizeProvider(provider);
        symbol = normalizeStock(symbol);
        cryptoSymbol = normalizeCrypto(cryptoSymbol);
        pollSeconds = clamp(pollSeconds, 5, 3600);
        staleSleepMinutes = clamp(staleSleepMinutes, 1, 120);
        if (!"medium".equals(petSize)) petSize = "small";
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString("provider", provider)
                .putString("symbol", symbol)
                .putString("displayName", displayName.trim())
                .putString("cryptoSymbol", cryptoSymbol)
                .putString("customUrl", customUrl.trim())
                .putString("customHeaders", customHeaders.trim().isEmpty() ? "{}" : customHeaders.trim())
                .putString("customValuePath", customValuePath.trim())
                .putString("customPercentPath", customPercentPath.trim())
                .putInt("pollSeconds", pollSeconds)
                .putFloat("riseThreshold", riseThreshold)
                .putFloat("fallThreshold", fallThreshold)
                .putBoolean("soundEnabled", soundEnabled)
                .putBoolean("voiceEnabled", voiceEnabled)
                .putBoolean("autoStart", autoStart)
                .putString("petSize", petSize)
                .putInt("staleSleepMinutes", staleSleepMinutes)
                .putString("niulaiSoundUri", niulaiSoundUri)
                .putString("mamaSoundUri", mamaSoundUri)
                .putString("mieSoundUri", mieSoundUri)
                .apply();
    }

    static String normalizeProvider(String value) {
        if ("crypto".equals(value) || "custom".equals(value)) return value;
        return "eastmoney";
    }

    static String normalizeCrypto(String value) {
        String compact = value == null ? "" : value.toUpperCase(Locale.ROOT)
                .replace("/", "").replace("-", "").replace("_", "").replace(" ", "");
        if (compact.isEmpty()) return "BTCUSDT";
        if (!compact.endsWith("USDT") && !compact.endsWith("USDC")) compact += "USDT";
        return compact;
    }

    static String normalizeStock(String value) {
        String compact = value == null ? "" : value.toUpperCase(Locale.ROOT).trim();
        if (compact.matches("[01]\\.\\d{6}")) return compact;
        compact = compact.replace(".", "").replace(" ", "");
        String market = "";
        if (compact.startsWith("SH")) {
            market = "1";
            compact = compact.substring(2);
        } else if (compact.startsWith("SZ") || compact.startsWith("BJ")) {
            market = "0";
            compact = compact.substring(2);
        }
        compact = compact.replaceAll("\\D", "");
        if (compact.length() != 6) return "1.000001";
        if (market.isEmpty()) market = compact.startsWith("6") ? "1" : "0";
        return market + "." + compact;
    }

    private static int clamp(int value, int min, int max) {
        return Math.max(min, Math.min(max, value));
    }
}
