# 配置说明

建议通过桌宠设置窗口修改配置。保存后立即生效，程序会自动校验范围并规范化股票或币种代码。

## 配置文件位置

- Windows：`%APPDATA%\NiulaiPet\settings.json`
- macOS：`~/Library/Application Support/NiulaiPet/settings.json`
- 自定义声音：配置目录下的 `audio` 文件夹

自定义 API 的请求头在系统安全存储可用时不会明文保留在 JSON 中：

- Windows：凭据管理器，服务名 `NiulaiPet`，项目 `customHeaders`
- macOS：钥匙串，服务名 `NiulaiPet`，项目 `customHeaders`

配置不会上传到 GitHub。删除 `settings.json` 后重启程序可恢复默认设置。

## 字段

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `provider` | 字符串 | `eastmoney`（A 股）、`binance`（数字币，多接口回退）或 `custom` |
| `marketType` | 字符串 | 当前保留字段，默认 `index` |
| `symbol` | 字符串 | A 股代码；内部格式如 `1.000001`，设置页也接受 `600519`、`SH600519`、`SZ000001` |
| `displayName` | 字符串 | 行情卡片显示名称；自定义 API 也使用此名称 |
| `cryptoSymbol` | 字符串 | 数字币交易对；只输入 `BTC` 会自动转换成 `BTCUSDT` |
| `customUrl` | 字符串 | 自定义行情 HTTPS 地址 |
| `customHeaders` | JSON 字符串 | 请求头对象，例如 `{"Authorization":"Bearer xxx"}` |
| `customValuePath` | 字符串 | 价格字段路径，例如 `data.price` |
| `customPercentPath` | 字符串 | 涨跌幅字段路径，例如 `data.percent` |
| `pollSeconds` | 整数 | 刷新间隔，范围 5–3600 秒 |
| `riseThreshold` | 数字 | 达到该涨幅百分比时触发上涨动作 |
| `fallThreshold` | 数字 | 低于或等于该涨幅百分比时触发下跌动作 |
| `soundEnabled` | 布尔值 | 是否播放牛叫等音效 |
| `voiceEnabled` | 布尔值 | 是否播放“牛来”“妈妈”等台词 |
| `customUpSound` | 字符串 | 自定义上涨台词文件路径 |
| `customDownSound` | 字符串 | 自定义下跌台词文件路径 |
| `customCowSound` | 字符串 | 自定义牛叫文件路径 |
| `volume` | 数字 | 音量，范围 0–1 |
| `alwaysOnTop` | 布尔值 | 是否让桌宠保持置顶 |
| `runOnStartup` | 布尔值 | 是否登录系统后自动启动 |
| `petSize` | 字符串 | `small` 或 `medium` |
| `staleSleepMinutes` | 整数 | 连续无行情多少分钟后睡觉，范围 1–120 |

## 行情配置

### A 股

设置页可直接选上证指数、深证成指和创业板指，也可以输入六位股票代码。

- `600519` 或 `SH600519` → `1.600519`
- `000001` 或 `SZ000001` → `0.000001`
- 北京证券交易所代码可使用 `BJ` 前缀

### 数字货币

默认使用 USDT 交易对。程序依次尝试 OKX、Gate.io、火币、Binance 多域名，并对常见币种提供 CoinGecko 回退，因此不需要填写交易所 API Key。

- 输入 `BTC` → `BTCUSDT`
- 输入 `SOL/USDT` → `SOLUSDT`
- 已输入 `ETHUSDC` 时会保留原交易对

### 自定义 HTTPS API

假设接口返回：

```json
{
  "data": {
    "price": 103.87,
    "percent": 3.22
  }
}
```

设置：

```text
API 地址：https://api.example.com/ticker
价格字段路径：data.price
涨跌幅字段路径：data.percent
请求头 JSON：{"Authorization":"Bearer YOUR_TOKEN"}
```

`percent` 必须是百分数，例如上涨 3.22% 应返回 `3.22`，不是 `0.0322`。

## 自定义声音

在“声音配置”中选择本地音频即可。程序会把文件复制到自己的配置目录，单个文件最大 12 MB：

- 上涨台词：替换“牛来”
- 下跌台词：替换“妈妈”
- 牛叫音效：替换“咩”

点击“默认”可恢复内置声音。关闭“台词声音”只关闭台词；关闭“牛叫音效”只关闭附加音效。
