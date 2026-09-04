package com.niulai.pet;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.Rect;
import android.graphics.RectF;
import android.os.SystemClock;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewConfiguration;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

final class PetOverlayView extends View {
    enum State { IDLE, RUN, DOWN, SLEEP, DRAG }

    interface Controller {
        void moveBy(float dx, float dy);
        void onDragStart();
        void onDragEnd();
        void onTap();
        void onDoubleTap();
        void onRefresh();
        void onOpenSettings();
        void onToggleSound();
        void onClose();
    }

    private static final int CELL = 128;
    private static final int VIDEO_COLUMNS = 24;
    private static final int SPECIAL_COLUMNS = 24;
    private static final int IDLE_FRAMES = 145;
    private static final int RUN_FRAMES = 145;
    private static final int DOWN_FRAMES = 193;
    private static final int FPS = 24;

    private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG | Paint.FILTER_BITMAP_FLAG);
    private final Paint text = new Paint(Paint.ANTI_ALIAS_FLAG | Paint.SUBPIXEL_TEXT_FLAG);
    private final Paint textStroke = new Paint(Paint.ANTI_ALIAS_FLAG | Paint.SUBPIXEL_TEXT_FLAG);
    private final Rect source = new Rect();
    private final RectF destination = new RectF();
    private final RectF marketRect = new RectF();
    private final RectF toolbarRect = new RectF();
    private final Path trendPath = new Path();
    private final List<Double> history = new ArrayList<>();
    private final Bitmap idleAtlas;
    private final Bitmap runAtlas;
    private final Bitmap downAtlas;
    private final Bitmap specialAtlas;
    private final float density;
    private final int touchSlop;

    private Controller controller;
    private State state = State.IDLE;
    private long stateStarted = SystemClock.uptimeMillis();
    private MarketQuote quote;
    private String status = "正在连接行情…";
    private String caption = "";
    private long captionUntil;
    private boolean controlsVisible;
    private long controlsUntil;
    private boolean medium;
    private boolean dragging;
    private float downRawX;
    private float downRawY;
    private float lastRawX;
    private float lastRawY;
    private long lastTap;
    private int rapidTaps;
    private long rapidTapStarted;

    PetOverlayView(Context context) {
        super(context);
        density = getResources().getDisplayMetrics().density;
        touchSlop = ViewConfiguration.get(context).getScaledTouchSlop();
        idleAtlas = BitmapFactory.decodeResource(getResources(), R.drawable.niulai_idle);
        runAtlas = BitmapFactory.decodeResource(getResources(), R.drawable.niulai_run);
        downAtlas = BitmapFactory.decodeResource(getResources(), R.drawable.niulai_down);
        specialAtlas = BitmapFactory.decodeResource(getResources(), R.drawable.niulai_special);
        setLayerType(LAYER_TYPE_HARDWARE, null);
        setBackgroundColor(Color.TRANSPARENT);
        setClickable(true);
        text.setTypeface(android.graphics.Typeface.create("sans-serif", android.graphics.Typeface.BOLD));
        textStroke.setTypeface(text.getTypeface());
        textStroke.setStyle(Paint.Style.STROKE);
        textStroke.setStrokeJoin(Paint.Join.ROUND);
        textStroke.setStrokeWidth(dp(2.4f));
        textStroke.setColor(Color.argb(215, 0, 0, 0));
    }

    void setController(Controller controller) {
        this.controller = controller;
    }

    void setMedium(boolean medium) {
        this.medium = medium;
        invalidate();
    }

    void setState(State next) {
        if (state == next) return;
        state = next;
        stateStarted = SystemClock.uptimeMillis();
        invalidate();
    }

    State getState() {
        return state;
    }

    void setQuote(MarketQuote value) {
        quote = value;
        status = "实时";
        history.add(value.price);
        if (history.size() > 24) history.remove(0);
        invalidate();
    }

    void setStatus(String value) {
        status = value;
        invalidate();
    }

    void showCaption(String value, long durationMs) {
        caption = value == null ? "" : value;
        captionUntil = SystemClock.uptimeMillis() + durationMs;
        invalidate();
    }

    void showControls() {
        controlsVisible = true;
        controlsUntil = SystemClock.uptimeMillis() + 5000;
        invalidate();
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        long now = SystemClock.uptimeMillis();
        if (controlsVisible && now > controlsUntil) controlsVisible = false;
        if (!caption.isEmpty() && now > captionUntil) caption = "";
        drawMarket(canvas);
        drawPet(canvas, now);
        drawCaption(canvas);
        if (state == State.SLEEP) drawSleepFx(canvas, now);
        if (controlsVisible) drawToolbar(canvas);
        postInvalidateOnAnimation();
    }

    private void drawMarket(Canvas canvas) {
        float margin = dp(5);
        marketRect.set(margin, dp(4), getWidth() - margin, dp(58));
        int tone = quote == null ? Color.rgb(224, 64, 78)
                : quote.percent >= 0 ? Color.rgb(255, 88, 101) : Color.rgb(45, 220, 143);

        paint.setStyle(Paint.Style.FILL);
        paint.setColor(Color.argb(244, 13, 18, 27));
        canvas.drawRoundRect(marketRect, dp(15), dp(15), paint);
        paint.setStyle(Paint.Style.STROKE);
        paint.setStrokeWidth(dp(1));
        paint.setColor(withAlpha(tone, 150));
        canvas.drawRoundRect(marketRect, dp(15), dp(15), paint);
        paint.setStyle(Paint.Style.FILL);
        paint.setColor(tone);
        canvas.drawRoundRect(new RectF(margin, dp(10), margin + dp(3), dp(51)), dp(2), dp(2), paint);

        text.setColor(Color.rgb(160, 172, 190));
        text.setTextSize(dp(9));
        String name = quote == null ? "牛来行情" : quote.name;
        canvas.drawText(ellipsize(name, 18), dp(17), dp(20), text);

        text.setColor(tone);
        text.setTextAlign(Paint.Align.RIGHT);
        text.setTextSize(dp(10));
        String percent = quote == null ? "--" : String.format(Locale.US, "%+.2f%%", quote.percent);
        canvas.drawText(percent, getWidth() - dp(14), dp(20), text);
        text.setTextAlign(Paint.Align.LEFT);
        text.setTextSize(dp(16));
        String price = quote == null ? "--" : formatPrice(quote.price);
        canvas.drawText(price, dp(17), dp(43), text);

        float chartLeft = Math.max(dp(92), getWidth() * .43f);
        drawTrend(canvas, chartLeft, dp(28), getWidth() - dp(14), dp(46), tone);
        text.setTextSize(dp(7));
        text.setColor(Color.rgb(112, 126, 145));
        text.setTextAlign(Paint.Align.RIGHT);
        canvas.drawText(status, getWidth() - dp(14), dp(54), text);
        text.setTextAlign(Paint.Align.LEFT);
    }

    private void drawTrend(Canvas canvas, float left, float top, float right, float bottom, int tone) {
        paint.setStyle(Paint.Style.STROKE);
        paint.setStrokeWidth(dp(1));
        paint.setColor(Color.argb(45, 255, 255, 255));
        canvas.drawLine(left, bottom, right, bottom, paint);
        if (history.size() < 2) return;
        double min = Double.MAX_VALUE;
        double max = -Double.MAX_VALUE;
        for (double value : history) {
            min = Math.min(min, value);
            max = Math.max(max, value);
        }
        double range = max - min;
        if (range == 0) range = Math.max(Math.abs(max) * .001, 1);
        trendPath.reset();
        for (int i = 0; i < history.size(); i++) {
            float x = left + (right - left) * i / (history.size() - 1f);
            float y = bottom - dp(2) - (float) ((history.get(i) - min) / range) * (bottom - top - dp(3));
            if (i == 0) trendPath.moveTo(x, y); else trendPath.lineTo(x, y);
        }
        paint.setColor(tone);
        paint.setStrokeWidth(dp(1.6f));
        paint.setShadowLayer(dp(4), 0, 0, tone);
        canvas.drawPath(trendPath, paint);
        paint.clearShadowLayer();
    }

    private void drawPet(Canvas canvas, long now) {
        int frame;
        Bitmap atlas;
        int columns;
        int rowOffset = 0;
        long elapsed = Math.max(0, now - stateStarted);
        switch (state) {
            case RUN:
                atlas = runAtlas;
                columns = VIDEO_COLUMNS;
                frame = Math.min(RUN_FRAMES - 1, (int) (elapsed * FPS / 1000));
                break;
            case DOWN:
                atlas = downAtlas;
                columns = VIDEO_COLUMNS;
                frame = Math.min(DOWN_FRAMES - 1, (int) (elapsed * FPS / 1000));
                break;
            case SLEEP:
                atlas = specialAtlas;
                columns = SPECIAL_COLUMNS;
                frame = (int) (elapsed * FPS / 1000) % 48;
                break;
            case DRAG:
                atlas = specialAtlas;
                columns = SPECIAL_COLUMNS;
                rowOffset = 2;
                frame = (int) (elapsed * FPS / 1000) % 48;
                break;
            default:
                atlas = idleAtlas;
                columns = VIDEO_COLUMNS;
                int pingPong = (IDLE_FRAMES - 1) * 2;
                int phase = (int) (elapsed * FPS / 1000) % pingPong;
                frame = phase < IDLE_FRAMES ? phase : pingPong - phase;
                break;
        }
        if (atlas == null) return;
        int col = frame % columns;
        int row = frame / columns + rowOffset;
        source.set(col * CELL, row * CELL, (col + 1) * CELL, (row + 1) * CELL);
        float size = medium ? Math.min(dp(123), getWidth() - dp(18)) : Math.min(dp(98), getWidth() - dp(18));
        float left = (getWidth() - size) / 2f;
        float top = dp(64);
        destination.set(left, top, left + size, top + size);
        paint.setAlpha(255);
        paint.setStyle(Paint.Style.FILL);
        canvas.drawBitmap(atlas, source, destination, paint);
    }

    private void drawCaption(Canvas canvas) {
        if (caption.isEmpty()) return;
        String value = ellipsize(caption, 24);
        float y = dp(77);
        float max = getWidth() - dp(12);
        text.setTextSize(dp(10));
        text.setTextAlign(Paint.Align.CENTER);
        text.setColor(Color.WHITE);
        textStroke.setTextSize(text.getTextSize());
        textStroke.setTextAlign(Paint.Align.CENTER);
        while (text.measureText(value) > max && value.length() > 4) value = value.substring(0, value.length() - 2) + "…";
        canvas.drawText(value, getWidth() / 2f, y, textStroke);
        canvas.drawText(value, getWidth() / 2f, y, text);
        text.setTextAlign(Paint.Align.LEFT);
    }

    private void drawSleepFx(Canvas canvas, long now) {
        long phase = (now - stateStarted) % 2400;
        text.setTypeface(android.graphics.Typeface.DEFAULT_BOLD);
        text.setColor(Color.argb((int) (90 + 120 * Math.abs(Math.sin(phase / 500.0))), 215, 234, 255));
        text.setTextSize(dp(14));
        canvas.drawText("Z", getWidth() * .66f, dp(106) - phase / 130f, text);
        text.setTextSize(dp(10));
        canvas.drawText("Z", getWidth() * .74f, dp(95) - phase / 160f, text);
        text.setTypeface(android.graphics.Typeface.create("sans-serif", android.graphics.Typeface.BOLD));
    }

    private void drawToolbar(Canvas canvas) {
        float width = Math.min(getWidth() - dp(20), dp(174));
        float left = (getWidth() - width) / 2f;
        toolbarRect.set(left, getHeight() - dp(39), left + width, getHeight() - dp(6));
        paint.setStyle(Paint.Style.FILL);
        paint.setColor(Color.argb(245, 12, 17, 25));
        canvas.drawRoundRect(toolbarRect, dp(13), dp(13), paint);
        paint.setStyle(Paint.Style.STROKE);
        paint.setStrokeWidth(dp(1));
        paint.setColor(Color.argb(50, 255, 255, 255));
        canvas.drawRoundRect(toolbarRect, dp(13), dp(13), paint);
        String[] labels = {"刷", "设", "声", "关"};
        text.setTextAlign(Paint.Align.CENTER);
        text.setTextSize(dp(10));
        text.setColor(Color.rgb(226, 232, 241));
        for (int i = 0; i < labels.length; i++) {
            float x = toolbarRect.left + toolbarRect.width() * (i + .5f) / labels.length;
            canvas.drawText(labels[i], x, toolbarRect.centerY() + dp(3.5f), text);
        }
        text.setTextAlign(Paint.Align.LEFT);
    }

    @Override
    public boolean onTouchEvent(MotionEvent event) {
        if (controller == null) return true;
        switch (event.getActionMasked()) {
            case MotionEvent.ACTION_DOWN:
                downRawX = lastRawX = event.getRawX();
                downRawY = lastRawY = event.getRawY();
                dragging = false;
                return true;
            case MotionEvent.ACTION_MOVE:
                float totalX = event.getRawX() - downRawX;
                float totalY = event.getRawY() - downRawY;
                if (!dragging && Math.hypot(totalX, totalY) > touchSlop) {
                    dragging = true;
                    controller.onDragStart();
                }
                if (dragging) {
                    controller.moveBy(event.getRawX() - lastRawX, event.getRawY() - lastRawY);
                    lastRawX = event.getRawX();
                    lastRawY = event.getRawY();
                }
                return true;
            case MotionEvent.ACTION_UP:
                if (dragging) {
                    controller.onDragEnd();
                    dragging = false;
                    return true;
                }
                performClick();
                if (controlsVisible && toolbarRect.contains(event.getX(), event.getY())) {
                    int index = Math.max(0, Math.min(3,
                            (int) ((event.getX() - toolbarRect.left) / (toolbarRect.width() / 4f))));
                    if (index == 0) controller.onRefresh();
                    else if (index == 1) controller.onOpenSettings();
                    else if (index == 2) controller.onToggleSound();
                    else controller.onClose();
                    controlsUntil = SystemClock.uptimeMillis() + 5000;
                    return true;
                }
                long now = SystemClock.uptimeMillis();
                trackRapidTap(now);
                controller.onTap();
                if (now - lastTap < 320) {
                    lastTap = 0;
                    controller.onDoubleTap();
                } else {
                    lastTap = now;
                    showControls();
                }
                return true;
            case MotionEvent.ACTION_CANCEL:
                if (dragging) controller.onDragEnd();
                dragging = false;
                return true;
            default:
                return true;
        }
    }

    @Override
    public boolean performClick() {
        super.performClick();
        return true;
    }

    private void trackRapidTap(long now) {
        if (now - rapidTapStarted > 1600) {
            rapidTapStarted = now;
            rapidTaps = 0;
        }
        rapidTaps++;
        if (rapidTaps >= 5) {
            rapidTaps = 0;
            showCaption("牛来！", 1800);
        }
    }

    private float dp(float value) {
        return value * density;
    }

    private static int withAlpha(int color, int alpha) {
        return Color.argb(alpha, Color.red(color), Color.green(color), Color.blue(color));
    }

    private static String ellipsize(String value, int maxChars) {
        if (value == null) return "";
        return value.length() <= maxChars ? value : value.substring(0, maxChars - 1) + "…";
    }

    private static String formatPrice(double value) {
        if (Math.abs(value) >= 1000) return String.format(Locale.US, "%,.2f", value);
        if (Math.abs(value) >= 1) return String.format(Locale.US, "%.2f", value);
        return String.format(Locale.US, "%.6f", value);
    }
}
