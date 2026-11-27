package com.sodapulse.music

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.text.TextPaint
import android.text.TextUtils
import android.util.DisplayMetrics
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import kotlin.math.abs
import kotlin.math.roundToInt

data class WordSeg(
    val text: String,
    val startMs: Long,
    val endMs: Long
)

class KaraokeTextView(context: Context) : View(context) {

    var text: String = ""
        set(value) {
            if (field != value) {
                field = value
                requestLayout()
                invalidate()
            }
        }

    var translation: String? = null
        set(value) {
            if (field != value) {
                field = value
                requestLayout()
                invalidate()
            }
        }

    var words: List<WordSeg> = emptyList()
        set(value) {
            field = value
            invalidate()
        }

    var positionMs: Long = 0L
        set(value) {
            if (field != value) {
                field = value
                invalidate()
            }
        }

    var fontSizeSp: Float = 18f
        set(value) {
            val clamped = value.coerceIn(12f, 36f)
            if (field != clamped) {
                field = clamped
                updatePaintSizes()
                requestLayout()
                invalidate()
            }
        }

    private val basePaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(150, 255, 255, 255)
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
    }

    private val highlightPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#38BDF8")
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        setShadowLayer(6f, 0f, 1f, Color.argb(110, 56, 189, 248))
    }

    private val transPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(200, 226, 232, 240)
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
    }

    init {
        updatePaintSizes()
        val hPad = dpToPx(14f)
        val vPad = dpToPx(8f)
        setPadding(hPad, vPad, hPad, vPad)
    }

    private fun updatePaintSizes() {
        val mainPx = spToPx(fontSizeSp)
        basePaint.textSize = mainPx
        highlightPaint.textSize = mainPx
        transPaint.textSize = spToPx((fontSizeSp * 0.72f).coerceAtLeast(11f))
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val desiredWidth = MeasureSpec.getSize(widthMeasureSpec)
        val mainFm = highlightPaint.fontMetrics
        val mainHeight = (mainFm.descent - mainFm.ascent).roundToInt()

        var totalHeight = paddingTop + paddingBottom + mainHeight
        if (!translation.isNullOrBlank()) {
            val transFm = transPaint.fontMetrics
            val transHeight = (transFm.descent - transFm.ascent).roundToInt()
            totalHeight += dpToPx(4f) + transHeight
        }

        val resolvedHeight = resolveSize(totalHeight, heightMeasureSpec)
        setMeasuredDimension(desiredWidth, resolvedHeight)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)

        val displayLine = when {
            text.isNotEmpty() -> text
            words.isNotEmpty() -> words.joinToString("") { it.text }
            else -> ""
        }

        if (displayLine.isEmpty()) return

        val availWidth = (width - paddingLeft - paddingRight).coerceAtLeast(1).toFloat()
        val totalTextWidth = highlightPaint.measureText(displayLine)

        val highlightWidth = computeHighlightWidth(displayLine, totalTextWidth)

        val startX = if (totalTextWidth <= availWidth) {
            paddingLeft + (availWidth - totalTextWidth) / 2f
        } else {
            val targetScreenX = availWidth * 0.45f
            val rawOffset = paddingLeft + targetScreenX - highlightWidth
            val minX = paddingLeft - (totalTextWidth - availWidth)
            val maxX = paddingLeft.toFloat()
            rawOffset.coerceIn(minX, maxX)
        }

        val mainFm = highlightPaint.fontMetrics
        val baselineY = paddingTop - mainFm.ascent

        canvas.save()
        canvas.clipRect(
            paddingLeft.toFloat(),
            0f,
            (width - paddingRight).toFloat(),
            height.toFloat()
        )

        canvas.drawText(displayLine, startX, baselineY, basePaint)

        if (highlightWidth > 0f) {
            canvas.save()
            canvas.clipRect(
                startX,
                0f,
                startX + highlightWidth,
                height.toFloat()
            )
            canvas.drawText(displayLine, startX, baselineY, highlightPaint)
            canvas.restore()
        }

        canvas.restore()

        val transText = translation
        if (!transText.isNullOrBlank()) {
            val transFm = transPaint.fontMetrics
            val transBaselineY = paddingTop + (mainFm.descent - mainFm.ascent) + dpToPx(4f) - transFm.ascent
            val ellipsized = TextUtils.ellipsize(
                transText,
                transPaint,
                availWidth,
                TextUtils.TruncateAt.END
            ).toString()
            val transWidth = transPaint.measureText(ellipsized)
            val transX = paddingLeft + (availWidth - transWidth).coerceAtLeast(0f) / 2f
            canvas.drawText(ellipsized, transX, transBaselineY, transPaint)
        }
    }

    private fun computeHighlightWidth(displayLine: String, totalTextWidth: Float): Float {
        if (words.isEmpty()) {
            return totalTextWidth
        }

        var accumulated = 0f
        for (word in words) {
            val wordWidth = highlightPaint.measureText(word.text)
            if (positionMs >= word.endMs) {
                accumulated += wordWidth
            } else if (positionMs > word.startMs) {
                val duration = (word.endMs - word.startMs).coerceAtLeast(1L)
                val fraction = ((positionMs - word.startMs).toFloat() / duration.toFloat()).coerceIn(0f, 1f)
                accumulated += wordWidth * fraction
                break
            } else {
                break
            }
        }
        return accumulated.coerceIn(0f, totalTextWidth)
    }

    private fun spToPx(sp: Float): Float {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_SP,
            sp,
            resources.displayMetrics
        )
    }

    private fun dpToPx(dp: Float): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            dp,
            resources.displayMetrics
        ).roundToInt()
    }
}

object KaraokeOverlayController {

    private val mainHandler = Handler(Looper.getMainLooper())

    private var windowManager: WindowManager? = null
    private var containerView: FrameLayout? = null
    private var karaokeView: KaraokeTextView? = null
    private var layoutParams: WindowManager.LayoutParams? = null

    private var isEnabled: Boolean = false
    private var isLocked: Boolean = false
    private var currentFontSizeSp: Float = 18f
    private var currentYOffsetPx: Int = 120

    private var cachedText: String = ""
    private var cachedTranslation: String? = null
    private var cachedWords: List<WordSeg> = emptyList()
    private var cachedPositionMs: Long = 0L

    fun canDrawOverlays(context: Context): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(context.applicationContext)
        } else {
            true
        }
    }

    fun requestOverlayPermission(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !canDrawOverlays(context)) {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:${context.packageName}")
            ).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
        }
    }

    fun configure(
        context: Context,
        enabled: Boolean,
        locked: Boolean,
        fontSizeSp: Float,
        yOffsetPx: Int
    ) {
        val appContext = context.applicationContext
        runOnMain {
            isEnabled = enabled
            isLocked = locked
            currentFontSizeSp = fontSizeSp
            currentYOffsetPx = yOffsetPx

            if (!enabled) {
                removeOverlayInternal()
                return@runOnMain
            }

            if (!canDrawOverlays(appContext)) {
                return@runOnMain
            }

            if (containerView == null) {
                createAndAttachOverlay(appContext)
            } else {
                updateOverlayLayout(appContext)
            }

            karaokeView?.apply {
                this.fontSizeSp = currentFontSizeSp
                this.text = cachedText
                this.translation = cachedTranslation
                this.words = cachedWords
                this.positionMs = cachedPositionMs
            }
        }
    }

    fun updateLyric(
        lineText: String,
        translation: String?,
        words: List<WordSeg>,
        positionMs: Long
    ) {
        runOnMain {
            cachedText = lineText
            cachedTranslation = translation
            cachedWords = words
            cachedPositionMs = positionMs

            karaokeView?.apply {
                this.text = lineText
                this.translation = translation
                this.words = words
                this.positionMs = positionMs
            }
        }
    }

    fun hide() {
        runOnMain {
            isEnabled = false
            removeOverlayInternal()
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun createAndAttachOverlay(context: Context) {
        val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        windowManager = wm

        val metrics = getScreenMetrics(context, wm)
        val horizontalMargin = dpToPx(context, 16f)
        val overlayWidth = (metrics.widthPixels - horizontalMargin * 2).coerceAtLeast(dpToPx(context, 220f))

        val container = FrameLayout(context).apply {
            background = createFrostedBackground(context, isLocked)
            elevation = dpToPx(context, 8f).toFloat()
        }

        val textView = KaraokeTextView(context).apply {
            fontSizeSp = currentFontSizeSp
        }

        container.addView(
            textView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT
            )
        )

        val windowType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val baseFlags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
        val finalFlags = if (isLocked) {
            baseFlags or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
        } else {
            baseFlags
        }

        val safeY = clampYOffset(context, currentYOffsetPx, metrics.heightPixels)

        val params = WindowManager.LayoutParams(
            overlayWidth,
            WindowManager.LayoutParams.WRAP_CONTENT,
            windowType,
            finalFlags,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            x = 0
            y = safeY
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }

        var initialY = 0
        var initialTouchY = 0f
        var isDragging = false
        val touchSlop = dpToPx(context, 4f)

        container.setOnTouchListener { _, event ->
            if (isLocked) return@setOnTouchListener false
            val lp = layoutParams ?: return@setOnTouchListener false
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    initialY = lp.y
                    initialTouchY = event.rawY
                    isDragging = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dy = event.rawY - initialTouchY
                    if (!isDragging && abs(dy) > touchSlop) {
                        isDragging = true
                    }
                    if (isDragging) {
                        val screenHeight = getScreenMetrics(context, wm).heightPixels
                        val nextY = clampYOffset(context, (initialY + dy).roundToInt(), screenHeight)
                        lp.y = nextY
                        currentYOffsetPx = nextY
                        wm.updateViewLayout(container, lp)
                    }
                    true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    isDragging = false
                    true
                }
                else -> false
            }
        }

        try {
            wm.addView(container, params)
            containerView = container
            karaokeView = textView
            layoutParams = params
        } catch (_: Exception) {
            containerView = null
            karaokeView = null
            layoutParams = null
        }
    }

    private fun updateOverlayLayout(context: Context) {
        val wm = windowManager ?: return
        val container = containerView ?: return
        val params = layoutParams ?: return

        val baseFlags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
        params.flags = if (isLocked) {
            baseFlags or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
        } else {
            baseFlags
        }

        val screenHeight = getScreenMetrics(context, wm).heightPixels
        params.y = clampYOffset(context, currentYOffsetPx, screenHeight)
        container.background = createFrostedBackground(context, isLocked)

        try {
            wm.updateViewLayout(container, params)
        } catch (_: Exception) {
            // Ignore if view is no longer attached
        }
    }

    private fun removeOverlayInternal() {
        val wm = windowManager
        val container = containerView
        if (wm != null && container != null) {
            try {
                wm.removeViewImmediate(container)
            } catch (_: Exception) {
                try {
                    wm.removeView(container)
                } catch (_: Exception) {
                    // Ignore
                }
            }
        }
        containerView = null
        karaokeView = null
        layoutParams = null
    }

    private fun createFrostedBackground(context: Context, locked: Boolean): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dpToPx(context, 18f).toFloat()
            setColor(
                if (locked) Color.argb(145, 15, 23, 42)
                else Color.argb(190, 15, 23, 42)
            )
            setStroke(
                dpToPx(context, 1f),
                if (locked) Color.argb(45, 255, 255, 255)
                else Color.argb(120, 56, 189, 248)
            )
        }
    }

    private fun clampYOffset(context: Context, yOffset: Int, screenHeight: Int): Int {
        val statusBarHeight = getStatusBarHeight(context)
        val minTop = statusBarHeight + dpToPx(context, 8f)
        val maxTop = (screenHeight - dpToPx(context, 96f)).coerceAtLeast(minTop)
        return yOffset.coerceIn(minTop, maxTop)
    }

    private fun getStatusBarHeight(context: Context): Int {
        val resId = context.resources.getIdentifier("status_bar_height", "dimen", "android")
        return if (resId > 0) {
            context.resources.getDimensionPixelSize(resId)
        } else {
            dpToPx(context, 24f)
        }
    }

    private fun getScreenMetrics(context: Context, wm: WindowManager): DisplayMetrics {
        val metrics = DisplayMetrics()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds = wm.currentWindowMetrics.bounds
            metrics.widthPixels = bounds.width()
            metrics.heightPixels = bounds.height()
            metrics.density = context.resources.displayMetrics.density
        } else {
            @Suppress("DEPRECATION")
            wm.defaultDisplay.getMetrics(metrics)
        }
        return metrics
    }

    private fun dpToPx(context: Context, dp: Float): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            dp,
            context.resources.displayMetrics
        ).roundToInt()
    }

    private fun runOnMain(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            block()
        } else {
            mainHandler.post(block)
        }
    }
}
