package com.niulai.pet;

import android.animation.Animator;
import android.animation.AnimatorListenerAdapter;
import android.animation.ValueAnimator;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.graphics.PixelFormat;
import android.graphics.drawable.Icon;
import android.media.MediaPlayer;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.SystemClock;
import android.provider.Settings;
import android.view.Gravity;
import android.view.WindowManager;

import java.time.DayOfWeek;
import java.time.LocalTime;
import java.time.ZonedDateTime;
import java.time.ZoneId;
import java.util.Locale;
import java.util.Random;
import java.util.HashSet;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class PetOverlayService extends Service implements PetOverlayView.Controller {
    static final String ACTION_START = "com.niulai.pet.START";
    static final String ACTION_STOP = "com.niulai.pet.STOP";
    static final String ACTION_APPLY = "com.niulai.pet.APPLY";
    static final String ACTION_REFRESH = "com.niulai.pet.REFRESH";
    private static final String CHANNEL_ID = "niulai_market";
    private static final int NOTIFICATION_ID = 1001;

    private static final String[] IDLE_QUOTES = {
            "我没摸鱼，我在研究牛市。", "你盯盘，我盯着你盯盘。", "本牛没有内幕，只有一肚子牢骚。",
            "横盘也是盘，煎一下应该挺香。", "牛市什么时候来？我不是已经来了吗。", "K线不说话，但它挺会气人。"
    };
    private static final String[] UP_QUOTES = {
            "卧槽！卧槽！又涨了！", "别睡了，都涨上天了！", "牛来了！谁也别拦我！",
            "红线踩油门了，快扶住我！", "再涨我就申请飞行执照了！"
    };
    private static final String[] DOWN_QUOTES = {
            "他妈的！又套在山顶了！", "楼太高！我看不见！", "我要找牛妈妈寻安慰！",
            "这不是回调，这是跳楼机！", "妈妈，这根K线欺负牛！"
    };

    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService network = Executors.newSingleThreadExecutor();
    private final MarketClient market = new MarketClient();
    private final Random random = new Random();
    private final Runnable pollRunnable = this::pollNow;
    private final Runnable idleQuoteRunnable = new Runnable() {
        @Override public void run() {
            if (overlay != null && overlay.getState() == PetOverlayView.State.IDLE) {
                overlay.showCaption(IDLE_QUOTES[random.nextInt(IDLE_QUOTES.length)], 4500);
            }
            main.postDelayed(this, 75_000 + random.nextInt(75_000));
        }
    };

    private WindowManager windowManager;
    private WindowManager.LayoutParams windowParams;
    private PetOverlayView overlay;
    private PetSettings settings;
    private final Set<MediaPlayer> activePlayers = new HashSet<>();
    private long lastSuccess;
    private long lastReaction;
    private long manualAwakeUntil;
    private long tapWindowStarted;
    private int tapCount;
    private boolean destroyed;
    private boolean polling;
    private ValueAnimator movement;
    private PetOverlayView.State stateBeforeDrag = PetOverlayView.State.IDLE;

    @Override
    public void onCreate() {
        super.onCreate();
        settings = PetSettings.load(this);
        createChannel();
        startForeground(NOTIFICATION_ID, notification("行情连接中"));
        if (Settings.canDrawOverlays(this)) attachOverlay();
        main.post(idleQuoteRunnable);
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        String action = intent == null ? ACTION_START : intent.getAction();
        if (ACTION_STOP.equals(action)) {
            stopSelf();
            return START_NOT_STICKY;
        }
        if (ACTION_APPLY.equals(action)) {
            settings = PetSettings.load(this);
            resizeOverlay();
        }
        if (!Settings.canDrawOverlays(this)) {
            updateNotification("请先授予悬浮窗权限");
            return START_NOT_STICKY;
        }
        if (overlay == null) attachOverlay();
        if (ACTION_REFRESH.equals(action)) {
            main.removeCallbacks(pollRunnable);
            pollNow();
        } else {
            schedulePoll(250);
        }
        return START_STICKY;
    }

    private void attachOverlay() {
        if (overlay != null || !Settings.canDrawOverlays(this)) return;
        windowManager = (WindowManager) getSystemService(WINDOW_SERVICE);
        overlay = new PetOverlayView(this);
        overlay.setController(this);
        windowParams = new WindowManager.LayoutParams(
                overlayWidth(), overlayHeight(),
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                        | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                PixelFormat.TRANSLUCENT);
        windowParams.gravity = Gravity.TOP | Gravity.START;
        int screenWidth = getResources().getDisplayMetrics().widthPixels;
        int screenHeight = getResources().getDisplayMetrics().heightPixels;
        windowParams.x = Math.max(0, screenWidth - overlayWidth() - dp(12));
        windowParams.y = Math.max(dp(36), screenHeight - overlayHeight() - dp(70));
        windowManager.addView(overlay, windowParams);
        overlay.setMedium("medium".equals(settings.petSize));
    }

    private void resizeOverlay() {
        if (overlay == null || windowManager == null) return;
        windowParams.width = overlayWidth();
        windowParams.height = overlayHeight();
        clampPosition();
        windowManager.updateViewLayout(overlay, windowParams);
        overlay.setMedium("medium".equals(settings.petSize));
    }

    private int overlayWidth() {
        return dp("medium".equals(settings.petSize) ? 205 : 170);
    }

    private int overlayHeight() {
        return dp("medium".equals(settings.petSize) ? 230 : 205);
    }

    private void pollNow() {
        if (destroyed || polling || overlay == null) return;
        polling = true;
        PetSettings snapshot = settings;
        network.execute(() -> {
            try {
                MarketQuote quote = market.fetch(snapshot);
                main.post(() -> handleQuote(quote));
            } catch (Exception error) {
                main.post(() -> handleError(error));
            }
        });
    }

    private void handleQuote(MarketQuote quote) {
        polling = false;
        if (destroyed || overlay == null) return;
        lastSuccess = System.currentTimeMillis();
        overlay.setQuote(quote);
        updateNotification(quote.name + "  " + String.format(Locale.US, "%+.2f%%", quote.percent));

        String closedLabel = marketClosedLabel();
        if ("eastmoney".equals(settings.provider) && closedLabel != null
                && System.currentTimeMillis() > manualAwakeUntil) {
            overlay.setStatus(closedLabel);
            overlay.setState(PetOverlayView.State.SLEEP);
            overlay.showCaption(closedLabel, 4000);
        } else if (System.currentTimeMillis() - lastReaction > 25_000) {
            if (quote.percent >= settings.riseThreshold) reactUp();
            else if (quote.percent <= settings.fallThreshold) reactDown();
            else if (overlay.getState() == PetOverlayView.State.SLEEP) overlay.setState(PetOverlayView.State.IDLE);
        }
        schedulePoll(settings.pollSeconds * 1000L);
    }

    private void handleError(Exception error) {
        polling = false;
        if (destroyed || overlay == null) return;
        overlay.setStatus("重连中");
        if (lastSuccess == 0) lastSuccess = System.currentTimeMillis();
        if (System.currentTimeMillis() - lastSuccess >= settings.staleSleepMinutes * 60_000L) {
            overlay.setState(PetOverlayView.State.SLEEP);
            overlay.showCaption("行情走丢了，本牛先睡会儿…", 4200);
        }
        updateNotification("行情重连中");
        schedulePoll(Math.max(5000, settings.pollSeconds * 1000L));
    }

    private void schedulePoll(long delayMs) {
        main.removeCallbacks(pollRunnable);
        if (!destroyed) main.postDelayed(pollRunnable, delayMs);
    }

    private void reactUp() {
        lastReaction = System.currentTimeMillis();
        overlay.setState(PetOverlayView.State.RUN);
        overlay.showCaption(UP_QUOTES[random.nextInt(UP_QUOTES.length)], 5000);
        if (settings.voiceEnabled) play(settings.niulaiSoundUri, R.raw.niulai, 1f);
        if (settings.soundEnabled) main.postDelayed(() -> play(settings.mieSoundUri, R.raw.mie, .92f), 1350);
        runAcrossScreen();
    }

    private void reactDown() {
        lastReaction = System.currentTimeMillis();
        cancelMovement();
        overlay.setState(PetOverlayView.State.DOWN);
        overlay.showCaption(DOWN_QUOTES[random.nextInt(DOWN_QUOTES.length)], 5800);
        if (settings.voiceEnabled) play(settings.mamaSoundUri, R.raw.mama, 1f);
        if (settings.soundEnabled) main.postDelayed(() -> play(settings.mieSoundUri, R.raw.mie, .88f), 900);
        main.postDelayed(() -> {
            if (overlay != null && overlay.getState() == PetOverlayView.State.DOWN) {
                overlay.setState(PetOverlayView.State.IDLE);
            }
        }, 8500);
    }

    private void runAcrossScreen() {
        cancelMovement();
        int maxX = Math.max(0, getResources().getDisplayMetrics().widthPixels - overlayWidth());
        int maxY = Math.max(dp(36), getResources().getDisplayMetrics().heightPixels - overlayHeight() - dp(34));
        final float startX = windowParams.x;
        final float startY = windowParams.y;
        final float[][] points = new float[4][2];
        points[0][0] = startX;
        points[0][1] = startY;
        for (int i = 1; i < points.length; i++) {
            float radius = dp("medium".equals(settings.petSize) ? 120 : 140);
            points[i][0] = clamp(startX + (random.nextFloat() * 2 - 1) * radius, 0, maxX);
            points[i][1] = clamp(startY + (random.nextFloat() * 2 - 1) * radius, dp(36), maxY);
        }
        movement = ValueAnimator.ofFloat(0f, points.length - 1f);
        movement.setDuration(6100);
        movement.setInterpolator(new android.view.animation.AccelerateDecelerateInterpolator());
        movement.addUpdateListener(animator -> {
            if (overlay == null || windowManager == null) return;
            float value = (float) animator.getAnimatedValue();
            int segment = Math.min(points.length - 2, (int) value);
            float t = value - segment;
            t = t * t * (3 - 2 * t);
            windowParams.x = Math.round(points[segment][0] + (points[segment + 1][0] - points[segment][0]) * t);
            windowParams.y = Math.round(points[segment][1] + (points[segment + 1][1] - points[segment][1]) * t);
            safeUpdateLayout();
        });
        movement.addListener(new AnimatorListenerAdapter() {
            @Override public void onAnimationEnd(Animator animation) {
                if (overlay != null && overlay.getState() == PetOverlayView.State.RUN) {
                    overlay.setState(PetOverlayView.State.IDLE);
                }
            }
        });
        movement.start();
    }

    @Override public void moveBy(float dx, float dy) {
        if (windowParams == null) return;
        windowParams.x += Math.round(dx);
        windowParams.y += Math.round(dy);
        clampPosition();
        safeUpdateLayout();
    }

    @Override public void onDragStart() {
        cancelMovement();
        stateBeforeDrag = overlay.getState();
        overlay.setState(PetOverlayView.State.DRAG);
        overlay.showCaption("轻点拎，我有点委屈…", 3500);
    }

    @Override public void onDragEnd() {
        overlay.setState(stateBeforeDrag == PetOverlayView.State.SLEEP
                ? PetOverlayView.State.SLEEP : PetOverlayView.State.IDLE);
    }

    @Override public void onTap() {
        long now = SystemClock.uptimeMillis();
        if (now - tapWindowStarted > 1500) {
            tapWindowStarted = now;
            tapCount = 0;
        }
        tapCount++;
        if (tapCount >= 5) {
            tapCount = 0;
            overlay.showCaption("牛来！", 2200);
            if (settings.voiceEnabled) play(settings.niulaiSoundUri, R.raw.niulai, 1f);
        }
    }

    @Override public void onDoubleTap() {
        manualAwakeUntil = System.currentTimeMillis() + 5 * 60_000L;
        overlay.setState(PetOverlayView.State.IDLE);
        overlay.showCaption("醒了醒了，别戳了！", 2800);
        schedulePoll(0);
    }

    @Override public void onRefresh() {
        overlay.showCaption("本牛正在刷新行情…", 1800);
        schedulePoll(0);
    }

    @Override public void onOpenSettings() {
        Intent intent = new Intent(this, MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        startActivity(intent);
    }

    @Override public void onToggleSound() {
        settings.soundEnabled = !settings.soundEnabled;
        settings.voiceEnabled = settings.soundEnabled;
        settings.save(this);
        overlay.showCaption(settings.soundEnabled ? "声音已打开" : "本牛静音了", 1800);
    }

    @Override public void onClose() {
        stopSelf();
    }

    private void clampPosition() {
        int maxX = Math.max(0, getResources().getDisplayMetrics().widthPixels - overlayWidth());
        int maxY = Math.max(dp(36), getResources().getDisplayMetrics().heightPixels - overlayHeight());
        windowParams.x = Math.max(0, Math.min(maxX, windowParams.x));
        windowParams.y = Math.max(dp(24), Math.min(maxY, windowParams.y));
    }

    private void safeUpdateLayout() {
        try {
            if (overlay != null && overlay.isAttachedToWindow()) windowManager.updateViewLayout(overlay, windowParams);
        } catch (IllegalArgumentException ignored) {
        }
    }

    private void cancelMovement() {
        if (movement != null) {
            movement.cancel();
            movement = null;
        }
    }

    private void play(String uriValue, int fallbackResource, float volume) {
        MediaPlayer player = null;
        if (uriValue != null && !uriValue.isEmpty()) {
            try {
                player = MediaPlayer.create(this, android.net.Uri.parse(uriValue));
            } catch (Exception ignored) {
            }
        }
        if (player == null) player = MediaPlayer.create(this, fallbackResource);
        if (player == null) {
            if (overlay != null) overlay.showCaption("音频加载失败，请在设置中重新选择", 3500);
            return;
        }
        final MediaPlayer playing = player;
        activePlayers.add(playing);
        playing.setVolume(volume, volume);
        playing.setOnCompletionListener(value -> releasePlayer(value));
        playing.setOnErrorListener((value, what, extra) -> {
            releasePlayer(value);
            return true;
        });
        try {
            playing.start();
        } catch (IllegalStateException error) {
            releasePlayer(playing);
        }
    }

    private void releasePlayer(MediaPlayer player) {
        activePlayers.remove(player);
        try { player.release(); } catch (Exception ignored) { }
    }

    private String marketClosedLabel() {
        ZonedDateTime now = ZonedDateTime.now(ZoneId.of("Asia/Shanghai"));
        DayOfWeek day = now.getDayOfWeek();
        if (day == DayOfWeek.SATURDAY || day == DayOfWeek.SUNDAY) return "A股休市";
        LocalTime time = now.toLocalTime();
        if (!time.isBefore(LocalTime.of(9, 30)) && !time.isAfter(LocalTime.of(11, 30))) return null;
        if (!time.isBefore(LocalTime.of(13, 0)) && time.isBefore(LocalTime.of(15, 0))) return null;
        if (time.isAfter(LocalTime.of(11, 30)) && time.isBefore(LocalTime.of(13, 0))) return "午间休市";
        return "A股休市";
    }

    private void createChannel() {
        NotificationChannel channel = new NotificationChannel(CHANNEL_ID,
                getString(R.string.channel_name), NotificationManager.IMPORTANCE_LOW);
        channel.setDescription(getString(R.string.channel_description));
        channel.setShowBadge(false);
        getSystemService(NotificationManager.class).createNotificationChannel(channel);
    }

    private Notification notification(String content) {
        Intent open = new Intent(this, MainActivity.class);
        PendingIntent openIntent = PendingIntent.getActivity(this, 1, open,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        Intent stop = new Intent(this, PetOverlayService.class).setAction(ACTION_STOP);
        PendingIntent stopIntent = PendingIntent.getService(this, 2, stop,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        return new Notification.Builder(this, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle("牛来行情桌宠运行中")
                .setContentText(content)
                .setContentIntent(openIntent)
                .setOngoing(true)
                .setCategory(Notification.CATEGORY_SERVICE)
                .addAction(new Notification.Action.Builder(
                        Icon.createWithResource(this, R.drawable.ic_notification), "退出", stopIntent).build())
                .build();
    }

    private void updateNotification(String content) {
        getSystemService(NotificationManager.class).notify(NOTIFICATION_ID, notification(content));
    }

    private int dp(float value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private static float clamp(float value, float min, float max) {
        return Math.max(min, Math.min(max, value));
    }

    @Override
    public void onDestroy() {
        destroyed = true;
        main.removeCallbacksAndMessages(null);
        cancelMovement();
        if (overlay != null && windowManager != null) {
            try { windowManager.removeView(overlay); } catch (IllegalArgumentException ignored) { }
        }
        overlay = null;
        for (MediaPlayer player : new HashSet<>(activePlayers)) releasePlayer(player);
        network.shutdownNow();
        super.onDestroy();
    }

    @Override public IBinder onBind(Intent intent) {
        return null;
    }
}
