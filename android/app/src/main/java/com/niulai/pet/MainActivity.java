package com.niulai.pet;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.media.MediaPlayer;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.AdapterView;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Spinner;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONObject;

import java.util.Locale;

public final class MainActivity extends Activity {
    private static final int REQUEST_OVERLAY = 2101;
    private static final int REQUEST_NOTIFICATIONS = 2102;
    private static final int REQUEST_AUDIO = 2103;
    private final int red = Color.rgb(230, 64, 80);
    private final int panel = Color.rgb(20, 23, 33);
    private final int field = Color.rgb(10, 13, 21);
    private final int muted = Color.rgb(157, 166, 181);
    private final Handler main = new Handler(Looper.getMainLooper());

    private Spinner providerSpinner;
    private Spinner sizeSpinner;
    private LinearLayout stockPanel;
    private LinearLayout cryptoPanel;
    private LinearLayout customPanel;
    private EditText stockCode;
    private EditText stockName;
    private EditText cryptoCode;
    private EditText customName;
    private EditText customUrl;
    private EditText customHeaders;
    private EditText customValuePath;
    private EditText customPercentPath;
    private EditText pollSeconds;
    private EditText riseThreshold;
    private EditText fallThreshold;
    private EditText staleMinutes;
    private CheckBox soundEnabled;
    private CheckBox voiceEnabled;
    private CheckBox autoStart;
    private TextView permissionStatus;
    private TextView audioStatus;
    private String pickingSound;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().setStatusBarColor(Color.rgb(8, 12, 19));
        getWindow().setNavigationBarColor(Color.rgb(8, 12, 19));
        setContentView(buildContent());
        loadForm();
    }

    @Override
    protected void onResume() {
        super.onResume();
        updatePermissionStatus();
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != REQUEST_AUDIO || resultCode != RESULT_OK || data == null || data.getData() == null) return;
        Uri uri = data.getData();
        try {
            getContentResolver().takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION);
        } catch (SecurityException ignored) {
        }
        PetSettings s = PetSettings.load(this);
        if ("niulai".equals(pickingSound)) s.niulaiSoundUri = uri.toString();
        else if ("mama".equals(pickingSound)) s.mamaSoundUri = uri.toString();
        else if ("mie".equals(pickingSound)) s.mieSoundUri = uri.toString();
        s.save(this);
        updateAudioStatus(s);
        if (Settings.canDrawOverlays(this)) startServiceIntent(PetOverlayService.ACTION_APPLY);
        Toast.makeText(this, "自定义声音已保存", Toast.LENGTH_SHORT).show();
        previewAudio(pickingSound);
    }

    private View buildContent() {
        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.setBackgroundColor(Color.rgb(8, 12, 19));
        scroll.setPadding(dp(10), dp(10), dp(10), dp(16));
        scroll.setClipToPadding(false);
        LinearLayout root = column();
        root.setPadding(dp(14), dp(12), dp(14), dp(24));
        root.setBackground(rounded(Color.rgb(11, 15, 24), Color.rgb(112, 35, 48), 22));
        scroll.addView(root, matchWrap());

        TextView sponsor = text("✦ 本插件由 aitroys.com 赞助开发 ✦", 12, Color.rgb(255, 205, 210));
        sponsor.setGravity(Gravity.CENTER);
        sponsor.setPadding(dp(8), dp(9), dp(8), dp(9));
        sponsor.setBackground(rounded(Color.rgb(79, 24, 35), Color.rgb(178, 49, 66), 12));
        sponsor.setOnClickListener(v -> startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse("https://www.aitroys.com/"))));
        root.addView(sponsor, matchHeight(dp(38)));

        LinearLayout header = new LinearLayout(this);
        header.setOrientation(LinearLayout.HORIZONTAL);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(4), dp(14), dp(4), dp(11));
        ImageView logo = new ImageView(this);
        logo.setImageResource(R.drawable.ic_launcher);
        logo.setScaleType(ImageView.ScaleType.CENTER_CROP);
        header.addView(logo, new LinearLayout.LayoutParams(dp(50), dp(50)));
        LinearLayout titleBox = column();
        titleBox.setPadding(dp(12), 0, 0, 0);
        TextView title = text("牛来设置中心", 21, Color.WHITE);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        titleBox.addView(title);
        titleBox.addView(text("行情 · 动作 · 声音一站式配置", 12, muted));
        header.addView(titleBox, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));
        root.addView(header);

        LinearLayout permissionCard = card("悬浮宠物");
        permissionStatus = text("正在检查权限…", 13, muted);
        permissionCard.addView(permissionStatus);
        LinearLayout permissionButtons = row();
        Button permission = actionButton("授权悬浮窗", false);
        permission.setOnClickListener(v -> requestOverlayPermission());
        Button start = actionButton("启动牛来", true);
        start.setOnClickListener(v -> startPet());
        Button stop = actionButton("停止", false);
        stop.setOnClickListener(v -> stopPet());
        permissionButtons.addView(permission, weight());
        permissionButtons.addView(start, weightWithMargin());
        permissionButtons.addView(stop, weightWithMargin());
        permissionCard.addView(permissionButtons);
        root.addView(permissionCard, cardParams());

        LinearLayout sourceCard = card("行情来源");
        providerSpinner = spinner(new String[]{"A 股", "数字货币", "自定义 API"});
        providerSpinner.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener() {
            @Override public void onItemSelected(AdapterView<?> parent, View view, int position, long id) { showProvider(position); }
            @Override public void onNothingSelected(AdapterView<?> parent) { }
        });
        sourceCard.addView(providerSpinner, matchHeight(dp(48)));

        stockPanel = column();
        stockCode = edit(stockPanel, "股票代码", "例如：600519、SH600519 或 1.000001", false);
        stockName = edit(stockPanel, "显示名称", "例如：贵州茅台", false);
        sourceCard.addView(stockPanel);

        cryptoPanel = column();
        cryptoCode = edit(cryptoPanel, "币种/交易对", "输入 BTC 自动使用 BTCUSDT", false);
        sourceCard.addView(cryptoPanel);

        customPanel = column();
        customName = edit(customPanel, "显示名称", "自定义行情", false);
        customUrl = edit(customPanel, "HTTPS API 地址", "https://api.example.com/ticker", false);
        customValuePath = edit(customPanel, "价格字段路径", "data.price", false);
        customPercentPath = edit(customPanel, "涨跌幅字段路径", "data.percent", false);
        customHeaders = edit(customPanel, "请求头 JSON", "{\"Authorization\":\"Bearer ...\"}", false);
        customHeaders.setMinLines(2);
        sourceCard.addView(customPanel);
        root.addView(sourceCard, cardParams());

        LinearLayout rules = card("动作规则");
        LinearLayout thresholds = row();
        LinearLayout up = column();
        riseThreshold = edit(up, "上涨触发 %", "0.15", true);
        LinearLayout down = column();
        fallThreshold = edit(down, "下跌触发 %", "-0.15", true);
        thresholds.addView(up, wrapWeight());
        thresholds.addView(down, wrapWeightWithMargin());
        rules.addView(thresholds);
        pollSeconds = edit(rules, "行情刷新间隔（秒）", "15", true);
        staleMinutes = edit(rules, "无行情后睡眠（分钟）", "3", true);
        root.addView(rules, cardParams());

        LinearLayout preferences = card("显示与声音");
        label(preferences, "宠物大小");
        sizeSpinner = spinner(new String[]{"小巧", "中等"});
        preferences.addView(sizeSpinner, matchHeight(dp(48)));
        soundEnabled = check("牛叫音效");
        voiceEnabled = check("台词声音");
        autoStart = check("开机自动启动");
        LinearLayout switches = row();
        soundEnabled.setTextSize(12);
        voiceEnabled.setTextSize(12);
        autoStart.setTextSize(12);
        switches.addView(soundEnabled, wrapWeight());
        switches.addView(voiceEnabled, wrapWeight());
        preferences.addView(switches, matchWrap());
        preferences.addView(autoStart);
        label(preferences, "自定义声音（MP3 / WAV / OGG）");
        audioStatus = text("当前使用内置声音 · 播放走手机媒体音量", 12, muted);
        audioStatus.setPadding(dp(2), 0, 0, dp(6));
        preferences.addView(audioStatus);
        LinearLayout audioChoices = row();
        Button chooseNiulai = actionButton("选择牛来", false);
        chooseNiulai.setOnClickListener(v -> pickAudio("niulai"));
        audioChoices.addView(chooseNiulai, weight());
        Button chooseMama = actionButton("选择妈妈", false);
        chooseMama.setOnClickListener(v -> pickAudio("mama"));
        audioChoices.addView(chooseMama, weightWithMargin());
        Button chooseMie = actionButton("选择牛叫声", false);
        chooseMie.setOnClickListener(v -> pickAudio("mie"));
        audioChoices.addView(chooseMie, weightWithMargin());
        preferences.addView(audioChoices);
        LinearLayout audioActions = row();
        Button previewAudio = actionButton("试听全部声音", true);
        previewAudio.setOnClickListener(v -> previewAllAudio());
        audioActions.addView(previewAudio, weight());
        Button resetAudio = actionButton("恢复全部内置声音", false);
        resetAudio.setOnClickListener(v -> resetAudio());
        audioActions.addView(resetAudio, weightWithMargin());
        LinearLayout.LayoutParams audioActionParams = matchHeight(dp(46));
        audioActionParams.setMargins(0, dp(7), 0, 0);
        preferences.addView(audioActions, audioActionParams);
        root.addView(preferences, cardParams());

        Button save = actionButton("保存并应用设置", true);
        save.setTextSize(15);
        save.setOnClickListener(v -> saveForm(true));
        root.addView(save, matchHeight(dp(52)));

        TextView hint = text("提示：拖动牛来可以调整位置；点击显示工具栏；双击可从睡眠中唤醒。上涨采用红色，下跌采用绿色。", 12, muted);
        hint.setPadding(dp(4), dp(13), dp(4), 0);
        root.addView(hint);
        return scroll;
    }

    private void loadForm() {
        PetSettings s = PetSettings.load(this);
        providerSpinner.setSelection("crypto".equals(s.provider) ? 1 : "custom".equals(s.provider) ? 2 : 0);
        sizeSpinner.setSelection("medium".equals(s.petSize) ? 1 : 0);
        stockCode.setText(s.symbol);
        stockName.setText(s.displayName);
        cryptoCode.setText(s.cryptoSymbol);
        customName.setText(s.displayName);
        customUrl.setText(s.customUrl);
        customHeaders.setText(s.customHeaders);
        customValuePath.setText(s.customValuePath);
        customPercentPath.setText(s.customPercentPath);
        pollSeconds.setText(String.valueOf(s.pollSeconds));
        riseThreshold.setText(trimFloat(s.riseThreshold));
        fallThreshold.setText(trimFloat(s.fallThreshold));
        staleMinutes.setText(String.valueOf(s.staleSleepMinutes));
        soundEnabled.setChecked(s.soundEnabled);
        voiceEnabled.setChecked(s.voiceEnabled);
        autoStart.setChecked(s.autoStart);
        updateAudioStatus(s);
        showProvider(providerSpinner.getSelectedItemPosition());
    }

    private void pickAudio(String type) {
        pickingSound = type;
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT)
                .setType("audio/*")
                .addCategory(Intent.CATEGORY_OPENABLE)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
        startActivityForResult(intent, REQUEST_AUDIO);
    }

    private void resetAudio() {
        PetSettings s = PetSettings.load(this);
        s.niulaiSoundUri = "";
        s.mamaSoundUri = "";
        s.mieSoundUri = "";
        s.save(this);
        updateAudioStatus(s);
        if (Settings.canDrawOverlays(this)) startServiceIntent(PetOverlayService.ACTION_APPLY);
        Toast.makeText(this, "已恢复内置声音", Toast.LENGTH_SHORT).show();
    }

    private void previewAllAudio() {
        previewAudio("niulai");
        main.postDelayed(() -> previewAudio("mie"), 1350);
    }

    private void previewAudio(String type) {
        PetSettings s = PetSettings.load(this);
        String uriValue;
        int fallback;
        if ("mama".equals(type)) {
            uriValue = s.mamaSoundUri;
            fallback = R.raw.mama;
        } else if ("mie".equals(type)) {
            uriValue = s.mieSoundUri;
            fallback = R.raw.mie;
        } else {
            uriValue = s.niulaiSoundUri;
            fallback = R.raw.niulai;
        }
        MediaPlayer player = null;
        if (!uriValue.isEmpty()) {
            try { player = MediaPlayer.create(this, Uri.parse(uriValue)); } catch (Exception ignored) { }
        }
        if (player == null) player = MediaPlayer.create(this, fallback);
        if (player == null) {
            Toast.makeText(this, "音频加载失败，请重新选择音频文件", Toast.LENGTH_LONG).show();
            return;
        }
        player.setVolume(1f, 1f);
        player.setOnCompletionListener(MediaPlayer::release);
        player.setOnErrorListener((value, what, extra) -> {
            value.release();
            return true;
        });
        player.start();
    }

    private void updateAudioStatus(PetSettings s) {
        if (audioStatus == null) return;
        int count = (s.niulaiSoundUri.isEmpty() ? 0 : 1)
                + (s.mamaSoundUri.isEmpty() ? 0 : 1)
                + (s.mieSoundUri.isEmpty() ? 0 : 1);
        audioStatus.setText(count == 0
                ? "当前使用内置声音 · 播放走手机媒体音量"
                : "已配置 " + count + " 项自定义声音 · 播放走手机媒体音量");
    }

    private boolean saveForm(boolean notifyService) {
        try {
            PetSettings s = PetSettings.load(this);
            int provider = providerSpinner.getSelectedItemPosition();
            s.provider = provider == 1 ? "crypto" : provider == 2 ? "custom" : "eastmoney";
            s.symbol = stockCode.getText().toString();
            s.cryptoSymbol = cryptoCode.getText().toString();
            s.displayName = provider == 2 ? customName.getText().toString() : stockName.getText().toString();
            s.customUrl = customUrl.getText().toString();
            s.customHeaders = customHeaders.getText().toString();
            s.customValuePath = customValuePath.getText().toString();
            s.customPercentPath = customPercentPath.getText().toString();
            s.pollSeconds = integer(pollSeconds, 15);
            s.riseThreshold = decimal(riseThreshold, .15f);
            s.fallThreshold = decimal(fallThreshold, -.15f);
            s.staleSleepMinutes = integer(staleMinutes, 3);
            s.petSize = sizeSpinner.getSelectedItemPosition() == 1 ? "medium" : "small";
            s.soundEnabled = soundEnabled.isChecked();
            s.voiceEnabled = voiceEnabled.isChecked();
            s.autoStart = autoStart.isChecked();
            if ("custom".equals(s.provider)) {
                if (!s.customUrl.trim().startsWith("https://")) throw new IllegalArgumentException("自定义 API 必须使用 HTTPS");
                new JSONObject(s.customHeaders.trim().isEmpty() ? "{}" : s.customHeaders.trim());
                if (s.customValuePath.trim().isEmpty() || s.customPercentPath.trim().isEmpty()) {
                    throw new IllegalArgumentException("请填写价格和涨跌幅字段路径");
                }
            }
            if (s.fallThreshold >= s.riseThreshold) throw new IllegalArgumentException("下跌阈值必须小于上涨阈值");
            s.save(this);
            if (notifyService) {
                startServiceIntent(PetOverlayService.ACTION_APPLY);
                Toast.makeText(this, "设置已保存", Toast.LENGTH_SHORT).show();
            }
            return true;
        } catch (Exception error) {
            Toast.makeText(this, error.getMessage(), Toast.LENGTH_LONG).show();
            return false;
        }
    }

    private void startPet() {
        if (!saveForm(false)) return;
        if (!Settings.canDrawOverlays(this)) {
            requestOverlayPermission();
            Toast.makeText(this, "授权后再次点击“启动牛来”", Toast.LENGTH_LONG).show();
            return;
        }
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, REQUEST_NOTIFICATIONS);
        }
        startServiceIntent(PetOverlayService.ACTION_START);
        Toast.makeText(this, "牛来已经出现在屏幕上", Toast.LENGTH_SHORT).show();
        moveTaskToBack(true);
    }

    private void stopPet() {
        startService(new Intent(this, PetOverlayService.class).setAction(PetOverlayService.ACTION_STOP));
        Toast.makeText(this, "牛来已退出", Toast.LENGTH_SHORT).show();
    }

    private void startServiceIntent(String action) {
        Intent intent = new Intent(this, PetOverlayService.class).setAction(action);
        startForegroundService(intent);
    }

    private void requestOverlayPermission() {
        Intent intent = new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:" + getPackageName()));
        startActivityForResult(intent, REQUEST_OVERLAY);
    }

    private void updatePermissionStatus() {
        if (permissionStatus == null) return;
        boolean granted = Settings.canDrawOverlays(this);
        permissionStatus.setText(granted
                ? "✓ 悬浮窗权限已授予，可以启动桌面宠物"
                : "需要“在其他应用上层显示”权限才能显示牛来");
        permissionStatus.setTextColor(granted ? Color.rgb(75, 220, 151) : Color.rgb(255, 153, 162));
    }

    private void showProvider(int index) {
        if (stockPanel == null) return;
        stockPanel.setVisibility(index == 0 ? View.VISIBLE : View.GONE);
        cryptoPanel.setVisibility(index == 1 ? View.VISIBLE : View.GONE);
        customPanel.setVisibility(index == 2 ? View.VISIBLE : View.GONE);
    }

    private LinearLayout card(String title) {
        LinearLayout layout = column();
        layout.setPadding(dp(14), dp(13), dp(14), dp(14));
        layout.setBackground(rounded(panel, Color.rgb(91, 37, 50), 16));
        LinearLayout headingRow = row();
        View accent = new View(this);
        accent.setBackground(rounded(red, red, 4));
        headingRow.addView(accent, new LinearLayout.LayoutParams(dp(4), dp(20)));
        TextView heading = text(title, 16, Color.rgb(248, 241, 243));
        heading.setTypeface(Typeface.DEFAULT_BOLD);
        heading.setPadding(dp(9), 0, 0, 0);
        headingRow.addView(heading, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));
        LinearLayout.LayoutParams headingParams = matchWrap();
        headingParams.setMargins(0, 0, 0, dp(8));
        layout.addView(headingRow, headingParams);
        return layout;
    }

    private EditText edit(LinearLayout parent, String title, String hint, boolean number) {
        label(parent, title);
        EditText value = new EditText(this);
        value.setHint(hint);
        value.setHintTextColor(Color.rgb(98, 106, 121));
        value.setTextColor(Color.WHITE);
        value.setTextSize(14);
        value.setSingleLine(!title.contains("JSON"));
        value.setPadding(dp(12), 0, dp(12), 0);
        value.setBackground(rounded(field, Color.rgb(69, 38, 48), 11));
        if (number) value.setInputType(InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_FLAG_DECIMAL | InputType.TYPE_NUMBER_FLAG_SIGNED);
        parent.addView(value, matchHeight(title.contains("JSON") ? dp(72) : dp(48)));
        return value;
    }

    private void label(LinearLayout parent, String value) {
        TextView label = text(value, 12, Color.rgb(180, 187, 199));
        label.setPadding(dp(2), dp(8), 0, dp(4));
        parent.addView(label);
    }

    private Spinner spinner(String[] values) {
        Spinner spinner = new Spinner(this);
        ArrayAdapter<String> adapter = new ArrayAdapter<String>(this, android.R.layout.simple_spinner_dropdown_item, values) {
            @Override public View getView(int position, View convertView, ViewGroup parent) {
                TextView view = (TextView) super.getView(position, convertView, parent);
                view.setTextColor(Color.WHITE);
                view.setTextSize(14);
                view.setPadding(dp(12), 0, dp(8), 0);
                return view;
            }
            @Override public View getDropDownView(int position, View convertView, ViewGroup parent) {
                TextView view = (TextView) super.getDropDownView(position, convertView, parent);
                view.setTextColor(Color.WHITE);
                view.setTextSize(14);
                view.setBackgroundColor(panel);
                view.setPadding(dp(14), dp(12), dp(14), dp(12));
                return view;
            }
        };
        spinner.setAdapter(adapter);
        spinner.setPopupBackgroundDrawable(rounded(panel, Color.rgb(70, 80, 96), 8));
        spinner.setBackground(rounded(field, Color.rgb(69, 38, 48), 11));
        return spinner;
    }

    private CheckBox check(String value) {
        CheckBox box = new CheckBox(this);
        box.setText(value);
        box.setTextColor(Color.rgb(232, 237, 245));
        box.setTextSize(14);
        box.setButtonTintList(new android.content.res.ColorStateList(
                new int[][]{new int[]{android.R.attr.state_checked}, new int[]{}},
                new int[]{red, Color.rgb(105, 116, 132)}));
        box.setPadding(dp(3), dp(6), 0, dp(4));
        return box;
    }

    private Button actionButton(String value, boolean primary) {
        Button button = new Button(this);
        button.setText(value);
        button.setTextColor(Color.WHITE);
        button.setTextSize(12);
        button.setAllCaps(false);
        button.setPadding(dp(4), 0, dp(4), 0);
        button.setBackground(rounded(primary ? red : Color.rgb(28, 36, 49),
                primary ? Color.rgb(255, 111, 123) : Color.rgb(66, 78, 95), 11));
        return button;
    }

    private TextView text(String value, float size, int color) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(size);
        view.setTextColor(color);
        return view;
    }

    private LinearLayout column() {
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        return layout;
    }

    private LinearLayout row() {
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.HORIZONTAL);
        layout.setGravity(Gravity.CENTER_VERTICAL);
        return layout;
    }

    private GradientDrawable rounded(int background, int stroke, int radiusDp) {
        GradientDrawable shape = new GradientDrawable();
        shape.setColor(background);
        shape.setCornerRadius(dp(radiusDp));
        shape.setStroke(dp(1), stroke);
        return shape;
    }

    private LinearLayout.LayoutParams cardParams() {
        LinearLayout.LayoutParams p = matchWrap();
        p.setMargins(0, 0, 0, dp(12));
        return p;
    }

    private LinearLayout.LayoutParams weight() {
        return new LinearLayout.LayoutParams(0, dp(46), 1);
    }

    private LinearLayout.LayoutParams weightWithMargin() {
        LinearLayout.LayoutParams p = weight();
        p.setMargins(dp(7), 0, 0, 0);
        return p;
    }

    private LinearLayout.LayoutParams wrapWeight() {
        return new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1);
    }

    private LinearLayout.LayoutParams wrapWeightWithMargin() {
        LinearLayout.LayoutParams p = wrapWeight();
        p.setMargins(dp(8), 0, 0, 0);
        return p;
    }

    private LinearLayout.LayoutParams matchWrap() {
        return new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
    }

    private LinearLayout.LayoutParams matchHeight(int height) {
        return new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, height);
    }

    private int dp(float value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private static int integer(EditText value, int fallback) {
        String text = value.getText().toString().trim();
        return text.isEmpty() ? fallback : Integer.parseInt(text);
    }

    private static float decimal(EditText value, float fallback) {
        String text = value.getText().toString().trim();
        return text.isEmpty() ? fallback : Float.parseFloat(text);
    }

    private static String trimFloat(float value) {
        return String.format(Locale.US, "%s", value);
    }
}
