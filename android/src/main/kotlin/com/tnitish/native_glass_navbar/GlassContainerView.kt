package com.tnitish.native_glass_navbar

import android.content.Context
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.util.AttributeSet
import android.util.TypedValue
import android.widget.FrameLayout

class GlassContainerView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : FrameLayout(context, attrs, defStyleAttr) {

    private var isDark: Boolean = false
    private val cornerRadiusPx = dpToPx(28f)
    private val borderWidthPx = dpToPx(1f).toInt()

    private val bgDrawable = GradientDrawable().apply {
        shape = GradientDrawable.RECTANGLE
        cornerRadius = cornerRadiusPx
    }

    init {
        elevation = dpToPx(8f)
        background = bgDrawable
        updateTheme(isDark)
    }

    fun updateTheme(isDark: Boolean) {
        this.isDark = isDark
        val strokeColor = if (isDark) Color.argb(160, 255, 255, 255) else Color.argb(230, 255, 255, 255)
        val bgColor = if (isDark) Color.parseColor("#E6222226") else Color.parseColor("#F2FFFFFF")
        
        bgDrawable.setColor(bgColor)
        bgDrawable.setStroke(borderWidthPx, strokeColor)
        invalidate()
    }

    fun triggerTouchRipple(x: Float, y: Float) {
        // Haptic or touch pulse
    }

    fun release() {
        // cleanup resources
    }

    private fun dpToPx(dp: Float): Float {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            dp,
            context.resources.displayMetrics
        )
    }
}
