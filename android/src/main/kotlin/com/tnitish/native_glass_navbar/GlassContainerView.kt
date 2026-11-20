package com.tnitish.native_glass_navbar

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.RenderEffect
import android.graphics.RuntimeShader
import android.graphics.Shader
import android.os.Build
import android.util.AttributeSet
import android.util.TypedValue
import android.view.View
import android.widget.FrameLayout

class GlassContainerView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : FrameLayout(context, attrs, defStyleAttr) {

    private var isDark: Boolean = false
    private val cornerRadiusPx = dpToPx(28f)
    private val borderWidthPx = dpToPx(1f)

    private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = borderWidthPx
    }

    private val tintPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }

    private val clipPath = Path()
    private val rectF = RectF()
    private val borderRectF = RectF()

    private var runtimeShader: RuntimeShader? = null
    private var touchX = -1f
    private var touchY = -1f
    private var touchIntensity = 0f
    private var touchAnimator: ValueAnimator? = null

    companion object {
        private const val AGSL_GLASS_SHADER = """
            uniform shader compositedContent;
            uniform float2 resolution;
            uniform float isDark;
            uniform float2 touchPos;
            uniform float touchIntensity;
            
            half4 main(float2 fragCoord) {
                half4 content = compositedContent.eval(fragCoord);
                
                // Base liquid glass transparency tint
                half4 baseColor = (isDark > 0.5) 
                    ? half4(0.12, 0.12, 0.14, 0.68)
                    : half4(0.96, 0.96, 0.98, 0.72);
                
                // Curvature refraction simulation near borders
                float edgeDist = min(min(fragCoord.x, resolution.x - fragCoord.x),
                                     min(fragCoord.y, resolution.y - fragCoord.y));
                float edgeFactor = clamp(edgeDist / 24.0, 0.0, 1.0);
                float curvature = 1.0 - pow(edgeFactor, 2.0);
                
                // Specular highlight at top edge (iOS liquid glass shine)
                float topHighlight = smoothstep(12.0, 0.0, fragCoord.y) * 0.28;
                if (isDark > 0.5) {
                    topHighlight *= 0.5;
                }
                
                // Subtle interactive touch refraction wave
                float touchDist = distance(fragCoord, touchPos);
                float touchWave = sin(touchDist * 0.08) * exp(-touchDist * 0.015) * touchIntensity * 0.15;
                
                half3 color = mix(content.rgb, baseColor.rgb, 0.7) + half3(topHighlight + curvature * 0.08 + touchWave);
                float alpha = clamp(baseColor.a + curvature * 0.12, 0.0, 1.0);
                
                return half4(color * alpha, alpha);
            }
        """
    }

    init {
        setWillNotDraw(false)
        setupElevationAndGlass()
    }

    private fun setupElevationAndGlass() {
        val elevationPx = dpToPx(8f)
        elevation = elevationPx

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                val blurEffect = RenderEffect.createBlurEffect(
                    dpToPx(24f),
                    dpToPx(24f),
                    Shader.TileMode.CLAMP
                )
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    val shader = RuntimeShader(AGSL_GLASS_SHADER)
                    runtimeShader = shader
                    val shaderEffect = RenderEffect.createRuntimeShaderEffect(shader, "compositedContent")
                    val combinedEffect = RenderEffect.createChainEffect(shaderEffect, blurEffect)
                    setRenderEffect(combinedEffect)
                } else {
                    setRenderEffect(blurEffect)
                }
            } catch (t: Throwable) {
                // Graceful fallback to custom canvas drawing
            }
        }
    }

    fun updateTheme(isDark: Boolean) {
        this.isDark = isDark
        runtimeShader?.setFloatUniform("isDark", if (isDark) 1f else 0f)
        invalidate()
    }

    fun triggerTouchRipple(x: Float, y: Float) {
        touchX = x
        touchY = y
        runtimeShader?.setFloatUniform("touchPos", touchX, touchY)

        touchAnimator?.cancel()
        touchAnimator = ValueAnimator.ofFloat(1f, 0f).apply {
            duration = 450
            addUpdateListener { anim ->
                touchIntensity = anim.animatedValue as Float
                runtimeShader?.setFloatUniform("touchIntensity", touchIntensity)
                invalidate()
            }
            start()
        }
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        val width = w.toFloat()
        val height = h.toFloat()
        rectF.set(0f, 0f, width, height)
        clipPath.reset()
        clipPath.addRoundRect(rectF, cornerRadiusPx, cornerRadiusPx, Path.Direction.CW)

        val halfBorder = borderWidthPx / 2f
        borderRectF.set(halfBorder, halfBorder, width - halfBorder, height - halfBorder)

        runtimeShader?.setFloatUniform("resolution", width, height)

        val topBorderColor = if (isDark) Color.argb(140, 255, 255, 255) else Color.argb(220, 255, 255, 255)
        val bottomBorderColor = if (isDark) Color.argb(40, 255, 255, 255) else Color.argb(80, 255, 255, 255)
        borderPaint.shader = LinearGradient(
            0f, 0f, 0f, height,
            topBorderColor, bottomBorderColor,
            Shader.TileMode.CLAMP
        )
    }

    override fun dispatchDraw(canvas: Canvas) {
        canvas.save()
        canvas.clipPath(clipPath)

        // Backdrop tint layer
        val bgAlpha = if (isDark) 170 else 200
        val baseRgb = if (isDark) 28 else 248
        tintPaint.color = Color.argb(bgAlpha, baseRgb, baseRgb, baseRgb)
        canvas.drawRoundRect(rectF, cornerRadiusPx, cornerRadiusPx, tintPaint)

        // Top specular highlight gradient
        val highlightPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            shader = LinearGradient(
                0f, 0f, 0f, dpToPx(16f),
                if (isDark) Color.argb(50, 255, 255, 255) else Color.argb(120, 255, 255, 255),
                Color.TRANSPARENT,
                Shader.TileMode.CLAMP
            )
        }
        canvas.drawRoundRect(rectF, cornerRadiusPx, cornerRadiusPx, highlightPaint)

        super.dispatchDraw(canvas)

        // 1dp perimeter stroke border
        canvas.drawRoundRect(borderRectF, cornerRadiusPx, cornerRadiusPx, borderPaint)

        canvas.restore()
    }

    fun release() {
        touchAnimator?.cancel()
        touchAnimator = null
        runtimeShader = null
    }

    private fun dpToPx(dp: Float): Float {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            dp,
            context.resources.displayMetrics
        )
    }
}
