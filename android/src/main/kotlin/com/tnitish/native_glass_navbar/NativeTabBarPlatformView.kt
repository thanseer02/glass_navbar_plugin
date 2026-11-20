package com.tnitish.native_glass_navbar

import android.animation.ValueAnimator
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.RenderEffect
import android.graphics.RuntimeShader
import android.graphics.Shader
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.graphics.drawable.ShapeDrawable
import android.graphics.drawable.shapes.OvalShape
import android.graphics.drawable.shapes.RoundRectShape
import android.os.Build
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.PixelCopy
import android.view.View
import android.view.ViewGroup
import android.view.Window
import android.view.animation.AccelerateDecelerateInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.annotation.RequiresApi
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView

data class AndroidTabConfig(
    val label: String,
    val symbol: String,
    val selectedSymbol: String,
    val badgeValue: String?
) {
    companion object {
        fun fromMap(map: Map<*, *>): AndroidTabConfig {
            val label = map["label"] as? String ?: ""
            val symbol = map["symbol"] as? String ?: ""
            val selectedSymbol = map["selectedSymbol"] as? String ?: symbol
            val badgeValue = map["badgeValue"] as? String
            return AndroidTabConfig(label, symbol, selectedSymbol, badgeValue)
        }
    }
}

data class AndroidTabBarConfig(
    val tabs: List<AndroidTabConfig> = emptyList(),
    val actionButtonSymbol: String = "",
    val tintColorARGB: Long = 0xFF007AFF,
    val selectedIndex: Int = 0,
    val isDark: Bool = false
) {
    val hasActionButton: Boolean get() = actionButtonSymbol.isNotEmpty()

    companion object {
        fun fromMap(map: Map<*, *>?): AndroidTabBarConfig {
            if (map == null) return AndroidTabBarConfig()
            val rawTabs = map["tabs"] as? List<*>
            val tabs = rawTabs?.filterIsInstance<Map<*, *>>()?.map { AndroidTabConfig.fromMap(it) } ?: emptyList()
            val action = map["actionButtonSymbol"] as? String ?: ""
            val colorVal = (map["tintColor"] as? Number)?.toLong() ?: 0xFF007AFF
            val index = (map["selectedIndex"] as? Number)?.toInt() ?: 0
            val isDark = map["isDark"] as? Boolean ?: false
            return AndroidTabBarConfig(tabs, action, colorVal, index, isDark)
        }
    }
}

typealias Bool = Boolean

class NativeTabBarPlatformView(
    private val context: Context,
    private val viewId: Long,
    args: Any?,
    messenger: BinaryMessenger
) : PlatformView, MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "NativeTabBar_$viewId")
    private val rootLayout: FrameLayout = FrameLayout(context)
    private var config: AndroidTabBarConfig = AndroidTabBarConfig.fromMap(args as? Map<*, *>)

    private val glassContainer: GlassContainerView
    private val tabsContainer: LinearLayout
    private var actionButtonView: FrameLayout? = null

    init {
        channel.setMethodCallHandler(this)

        rootLayout.layoutParams = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        )
        rootLayout.clipChildren = false
        rootLayout.clipToPadding = false

        glassContainer = GlassContainerView(context)
        val containerParams = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            dpToPx(56f)
        ).apply {
            gravity = Gravity.BOTTOM
            val marginH = dpToPx(16f)
            val marginB = dpToPx(12f)
            setMargins(marginH, 0, marginH, marginB)
        }
        glassContainer.layoutParams = containerParams
        glassContainer.updateTheme(config.isDark)

        tabsContainer = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            clipChildren = false
            clipToPadding = false
        }

        glassContainer.addView(tabsContainer)
        rootLayout.addView(glassContainer)

        buildTabsUI()
    }

    override fun getView(): View = rootLayout

    override fun dispose() {
        channel.setMethodCallHandler(null)
        glassContainer.release()
        rootLayout.removeAllViews()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "update") {
            val map = call.arguments as? Map<*, *>
            val newConfig = AndroidTabBarConfig.fromMap(map)
            val oldConfig = this.config
            this.config = newConfig

            glassContainer.updateTheme(newConfig.isDark)

            if (newConfig.tabs.size != oldConfig.tabs.size || newConfig.hasActionButton != oldConfig.hasActionButton) {
                buildTabsUI()
            } else {
                updateTabsInPlace()
            }
            result.success(null)
        } else {
            result.notImplemented()
        }
    }

    private fun buildTabsUI() {
        tabsContainer.removeAllViews()
        val count = config.tabs.size

        for (i in 0 until count) {
            val tabConfig = config.tabs[i]
            val tabView = createTabView(i, tabConfig)
            val params = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f)
            tabView.layoutParams = params
            tabsContainer.addView(tabView)
        }

        if (config.hasActionButton) {
            val actionView = createActionButtonView(config.actionButtonSymbol)
            val actionParams = LinearLayout.LayoutParams(dpToPx(48f), dpToPx(48f)).apply {
                gravity = Gravity.CENTER_VERTICAL
                setMargins(dpToPx(4f), 0, dpToPx(8f), 0)
            }
            actionView.layoutParams = actionParams
            actionButtonView = actionView
            tabsContainer.addView(actionView)
        } else {
            actionButtonView = null
        }

        updateSelectionAndColors()
    }

    private fun createTabView(index: Int, tabConfig: AndroidTabConfig): View {
        val tabLayout = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            isClickable = true
            isFocusable = true
        }

        val iconContainer = FrameLayout(context).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
            clipChildren = false
            clipToPadding = false
        }

        val imageView = ImageView(context).apply {
            tag = "icon"
            layoutParams = FrameLayout.LayoutParams(dpToPx(24f), dpToPx(24f))
            scaleType = ImageView.ScaleType.FIT_CENTER
        }
        iconContainer.addView(imageView)

        val badgeTextView = TextView(context).apply {
            tag = "badge"
            textSize = 10f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            includeFontPadding = false
            setPadding(dpToPx(4f), dpToPx(1f), dpToPx(4f), dpToPx(1f))
            val badgeBg = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(8f).toFloat()
                setColor(Color.RED)
            }
            background = badgeBg
            val badgeParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                gravity = Gravity.TOP or Gravity.END
                setMargins(0, -dpToPx(4f), -dpToPx(6f), 0)
            }
            layoutParams = badgeParams
            visibility = if (tabConfig.badgeValue.isNullOrEmpty()) View.GONE else View.VISIBLE
            text = tabConfig.badgeValue ?: ""
        }
        iconContainer.addView(badgeTextView)

        val labelView = TextView(context).apply {
            tag = "label"
            textSize = 11f
            gravity = Gravity.CENTER
            setPadding(0, dpToPx(2f), 0, 0)
            text = tabConfig.label
            maxLines = 1
        }

        tabLayout.addView(iconContainer)
        tabLayout.addView(labelView)

        applyTouchFeedback(tabLayout) {
            config = config.copy(selectedIndex = index)
            updateSelectionAndColors()
            channel.invokeMethod("valueChanged", mapOf("index" to index))
        }

        return tabLayout
    }

    private fun createActionButtonView(symbolName: String): FrameLayout {
        val frame = FrameLayout(context).apply {
            isClickable = true
            isFocusable = true
        }

        val btnBg = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            val tint = config.tintColorARGB.toInt()
            colors = intArrayOf(
                tint,
                blendColors(tint, Color.BLACK, 0.15f)
            )
            gradientType = GradientDrawable.LINEAR_GRADIENT
        }
        frame.background = btnBg
        frame.elevation = dpToPx(4f).toFloat()

        val icon = ImageView(context).apply {
            tag = "actionIcon"
            val p = dpToPx(24f)
            layoutParams = FrameLayout.LayoutParams(p, p).apply {
                gravity = Gravity.CENTER
            }
            setImageDrawable(SymbolIconResolver.resolveDrawable(context, symbolName, Color.WHITE))
        }
        frame.addView(icon)

        applyTouchFeedback(frame, scaleDown = 0.88f) {
            channel.invokeMethod("actionButtonPressed", null)
        }

        return frame
    }

    private fun applyTouchFeedback(view: View, scaleDown: Float = 0.92f, onClick: () -> Unit) {
        val originalScale = 1f
        var isDown = false

        view.setOnTouchListener { v, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    isDown = true
                    v.animate()
                        .scaleX(scaleDown)
                        .scaleY(scaleDown)
                        .setDuration(120)
                        .setInterpolator(AccelerateDecelerateInterpolator())
                        .start()
                    glassContainer.triggerTouchRipple(
                        event.rawX - glassContainer.x,
                        event.rawY - glassContainer.y
                    )
                }
                MotionEvent.ACTION_UP -> {
                    if (isDown) {
                        isDown = false
                        v.animate()
                            .scaleX(originalScale)
                            .scaleY(originalScale)
                            .setDuration(160)
                            .setInterpolator(AccelerateDecelerateInterpolator())
                            .start()
                        onClick()
                    }
                }
                MotionEvent.ACTION_CANCEL -> {
                    if (isDown) {
                        isDown = false
                        v.animate()
                            .scaleX(originalScale)
                            .scaleY(originalScale)
                            .setDuration(160)
                            .start()
                    }
                }
            }
            true
        }
    }

    private fun updateTabsInPlace() {
        val childCount = tabsContainer.childCount
        val standardCount = config.tabs.size

        for (i in 0 until minOf(childCount, standardCount)) {
            val tabView = tabsContainer.getChildAt(i) as? LinearLayout ?: continue
            val tabConfig = config.tabs[i]

            val iconContainer = tabView.getChildAt(0) as? FrameLayout
            val badgeView = iconContainer?.findViewWithTag<TextView>("badge")
            if (badgeView != null) {
                badgeView.visibility = if (tabConfig.badgeValue.isNullOrEmpty()) View.GONE else View.VISIBLE
                badgeView.text = tabConfig.badgeValue ?: ""
            }

            val labelView = tabView.findViewWithTag<TextView>("label")
            if (labelView != null && labelView.text != tabConfig.label) {
                labelView.text = tabConfig.label
            }
        }

        if (config.hasActionButton && actionButtonView != null) {
            val iconView = actionButtonView?.findViewWithTag<ImageView>("actionIcon")
            iconView?.setImageDrawable(
                SymbolIconResolver.resolveDrawable(context, config.actionButtonSymbol, Color.WHITE)
            )
        }

        updateSelectionAndColors()
    }

    private fun updateSelectionAndColors() {
        val standardCount = config.tabs.size
        val selectedIdx = config.selectedIndex
        val tintColor = config.tintColorARGB.toInt()
        val unselectedColor = if (config.isDark) Color.parseColor("#8E8E93") else Color.parseColor("#6C6C70")

        for (i in 0 until minOf(tabsContainer.childCount, standardCount)) {
            val tabView = tabsContainer.getChildAt(i) as? LinearLayout ?: continue
            val tabConfig = config.tabs[i]
            val isSelected = (i == selectedIdx)

            val color = if (isSelected) tintColor else unselectedColor
            val symbolName = if (isSelected) tabConfig.selectedSymbol else tabConfig.symbol

            val imageView = tabView.findViewWithTag<ImageView>("icon")
            imageView?.setImageDrawable(SymbolIconResolver.resolveDrawable(context, symbolName, color))

            val labelView = tabView.findViewWithTag<TextView>("label")
            labelView?.setTextColor(color)
        }
    }

    private fun dpToPx(dp: Float): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            dp,
            context.resources.displayMetrics
        ).toInt()
    }

    private fun blendColors(color1: Int, color2: Int, ratio: Float): Int {
        val inverseRatio = 1f - ratio
        val a = Color.alpha(color1) * inverseRatio + Color.alpha(color2) * ratio
        val r = Color.red(color1) * inverseRatio + Color.red(color2) * ratio
        val g = Color.green(color1) * inverseRatio + Color.green(color2) * ratio
        val b = Color.blue(color1) * inverseRatio + Color.blue(color2) * ratio
        return Color.argb(a.toInt(), r.toInt(), g.toInt(), b.toInt())
    }
}
