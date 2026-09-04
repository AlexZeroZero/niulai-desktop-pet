package com.niulai.pet;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.Iterator;
import java.util.Locale;

final class MarketClient {
    MarketQuote fetch(PetSettings settings) throws Exception {
        switch (settings.provider) {
            case "crypto":
                return fetchCrypto(settings);
            case "custom":
                return fetchCustom(settings);
            default:
                return fetchAStock(settings);
        }
    }

    private MarketQuote fetchAStock(PetSettings settings) throws Exception {
        String secid = PetSettings.normalizeStock(settings.symbol);
        String url = "https://push2.eastmoney.com/api/qt/stock/get?secid="
                + URLEncoder.encode(secid, "UTF-8")
                + "&fields=f43,f58,f59,f170";
        JSONObject data = new JSONObject(get(url, null)).getJSONObject("data");
        int digits = Math.max(0, data.optInt("f59", 2));
        double price = number(data.get("f43")) / Math.pow(10, digits);
        double percent = number(data.get("f170")) / 100.0;
        String name = data.optString("f58", settings.displayName);
        return checked(name, price, percent);
    }

    private MarketQuote fetchCrypto(PetSettings settings) throws Exception {
        String pair = PetSettings.normalizeCrypto(settings.cryptoSymbol);
        Exception lastError = null;
        try {
            String instrument = pair.substring(0, pair.length() - 4) + "-" + pair.substring(pair.length() - 4);
            JSONObject ticker = new JSONObject(get("https://www.okx.com/api/v5/market/ticker?instId=" + instrument, null))
                    .getJSONArray("data").getJSONObject(0);
            double price = number(ticker.get("last"));
            double open = number(ticker.get("open24h"));
            return checked(pair, price, percent(price, open));
        } catch (Exception error) {
            lastError = error;
        }
        try {
            String gatePair = pair.substring(0, pair.length() - 4) + "_" + pair.substring(pair.length() - 4);
            JSONObject ticker = new JSONArray(get("https://api.gateio.ws/api/v4/spot/tickers?currency_pair=" + gatePair, null))
                    .getJSONObject(0);
            return checked(pair, number(ticker.get("last")), number(ticker.get("change_percentage")));
        } catch (Exception error) {
            lastError = error;
        }
        try {
            JSONObject tick = new JSONObject(get("https://api.huobi.pro/market/detail/merged?symbol="
                    + pair.toLowerCase(Locale.ROOT), null)).getJSONObject("tick");
            double price = number(tick.get("close"));
            return checked(pair, price, percent(price, number(tick.get("open"))));
        } catch (Exception error) {
            lastError = error;
        }
        String[] binanceHosts = {
                "https://data-api.binance.vision",
                "https://api.binance.com",
                "https://api1.binance.com",
                "https://api2.binance.com",
                "https://api3.binance.com"
        };
        for (String host : binanceHosts) {
            try {
                JSONObject ticker = new JSONObject(get(host + "/api/v3/ticker/24hr?symbol=" + pair, null));
                return checked(pair, number(ticker.get("lastPrice")), number(ticker.get("priceChangePercent")));
            } catch (Exception error) {
                lastError = error;
            }
        }
        String base = pair.substring(0, pair.length() - 4);
        String coinId = coinGeckoId(base);
        if (coinId != null) {
            try {
                JSONObject value = new JSONObject(get(
                        "https://api.coingecko.com/api/v3/simple/price?ids=" + coinId
                                + "&vs_currencies=usd&include_24hr_change=true", null))
                        .getJSONObject(coinId);
                return checked(pair, number(value.get("usd")), number(value.get("usd_24h_change")));
            } catch (Exception error) {
                lastError = error;
            }
        }
        throw lastError == null ? new IllegalStateException("没有可用的数字货币行情接口") : lastError;
    }

    private MarketQuote fetchCustom(PetSettings settings) throws Exception {
        if (!settings.customUrl.startsWith("https://")) {
            throw new IllegalArgumentException("自定义 API 必须使用 HTTPS");
        }
        JSONObject headers = settings.customHeaders.isEmpty() ? new JSONObject() : new JSONObject(settings.customHeaders);
        JSONObject root = new JSONObject(get(settings.customUrl, headers));
        double price = number(readPath(root, settings.customValuePath));
        double percent = number(readPath(root, settings.customPercentPath));
        String name = settings.displayName.trim().isEmpty() ? "自定义行情" : settings.displayName.trim();
        return checked(name, price, percent);
    }

    private static Object readPath(JSONObject root, String path) throws Exception {
        Object current = root;
        for (String part : path.split("\\.")) {
            if (current instanceof JSONObject) {
                current = ((JSONObject) current).get(part);
            } else if (current instanceof JSONArray && part.matches("\\d+")) {
                current = ((JSONArray) current).get(Integer.parseInt(part));
            } else {
                throw new IllegalArgumentException("字段路径不存在: " + path);
            }
        }
        return current;
    }

    private static String get(String address, JSONObject headers) throws Exception {
        HttpURLConnection connection = (HttpURLConnection) new URL(address).openConnection();
        connection.setConnectTimeout(8000);
        connection.setReadTimeout(8000);
        connection.setRequestMethod("GET");
        connection.setRequestProperty("Accept", "application/json,text/plain,*/*");
        connection.setRequestProperty("User-Agent", "NiulaiPet-Android/0.1");
        if (headers != null) {
            Iterator<String> keys = headers.keys();
            while (keys.hasNext()) {
                String key = keys.next();
                connection.setRequestProperty(key, headers.optString(key));
            }
        }
        int status = connection.getResponseCode();
        InputStream stream = status >= 200 && status < 300 ? connection.getInputStream() : connection.getErrorStream();
        if (stream == null) throw new IllegalStateException("HTTP " + status);
        StringBuilder body = new StringBuilder();
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(stream, StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) body.append(line);
        } finally {
            connection.disconnect();
        }
        if (status < 200 || status >= 300) throw new IllegalStateException("HTTP " + status + ": " + body);
        return body.toString();
    }

    private static double number(Object value) {
        if (value instanceof Number) return ((Number) value).doubleValue();
        String text = String.valueOf(value).replace("%", "").trim();
        if (text.isEmpty() || "-".equals(text) || "--".equals(text)) throw new IllegalArgumentException("行情数值无效");
        return Double.parseDouble(text);
    }

    private static double percent(double current, double open) {
        return open == 0 ? 0 : (current - open) / open * 100.0;
    }

    private static String coinGeckoId(String symbol) {
        switch (symbol) {
            case "BTC": return "bitcoin";
            case "ETH": return "ethereum";
            case "BNB": return "binancecoin";
            case "SOL": return "solana";
            case "XRP": return "ripple";
            case "DOGE": return "dogecoin";
            case "ADA": return "cardano";
            default: return null;
        }
    }

    private static MarketQuote checked(String name, double price, double percent) {
        if (!Double.isFinite(price) || !Double.isFinite(percent)) throw new IllegalArgumentException("行情数值无效");
        return new MarketQuote(name, price, percent);
    }
}
