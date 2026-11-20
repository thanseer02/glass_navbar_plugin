package com.tnitish.native_glass_navbar

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorFilter
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.drawable.Drawable
import androidx.core.content.ContextCompat
import androidx.core.graphics.drawable.DrawableCompat

object SymbolIconResolver {

    /**
     * Resolves an iOS SF Symbol or asset icon name into an Android Vector/Drawable.
     * Generates clean vector iconography for icons that reliably render across all Android versions.
     */
    fun resolveDrawable(context: Context, symbolName: String, tintColor: Int): Drawable {
        // 1. Check application package resources for custom asset drawables first
        val resId = context.resources.getIdentifier(symbolName, "drawable", context.packageName)
        if (resId != 0) {
            try {
                val d = ContextCompat.getDrawable(context, resId)
                if (d != null) {
                    val wrapped = DrawableCompat.wrap(d.mutate())
                    DrawableCompat.setTint(wrapped, tintColor)
                    return wrapped
                }
            } catch (_: Exception) {}
        }

        // 2. Generate vector icon with exact SF Symbol semantics
        return ProceduralVectorDrawable(symbolName, tintColor)
    }
}

class ProceduralVectorDrawable(
    private val symbolName: String,
    private var tintColor: Int
) : Drawable() {

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = tintColor
        style = Paint.Style.STROKE
        strokeWidth = 5f
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }

    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = tintColor
        style = Paint.Style.FILL
    }

    private val path = Path()

    override fun draw(canvas: Canvas) {
        val b = bounds
        val w = b.width().toFloat()
        val h = b.height().toFloat()
        val cx = b.left + w / 2f
        val cy = b.top + h / 2f
        val size = minOf(w, h) * 0.65f
        val half = size / 2f

        path.reset()
        val name = symbolName.lowercase()

        when {
            // Home / House
            name.contains("house") || name.contains("home") -> {
                val isFilled = name.contains("fill")
                path.moveTo(cx, cy - half)
                path.lineTo(cx + half, cy)
                path.lineTo(cx + half * 0.75f, cy)
                path.lineTo(cx + half * 0.75f, cy + half)
                path.lineTo(cx - half * 0.75f, cy + half)
                path.lineTo(cx - half * 0.75f, cy)
                path.lineTo(cx - half, cy)
                path.close()
                if (isFilled) {
                    canvas.drawPath(path, fillPaint)
                } else {
                    canvas.drawPath(path, paint)
                }
            }

            // Search / Magnifying glass
            name.contains("magnifyingglass") || name.contains("search") -> {
                val r = half * 0.65f
                val circleCx = cx - half * 0.2f
                val circleCy = cy - half * 0.2f
                canvas.drawCircle(circleCx, circleCy, r, paint)
                val handleStartX = circleCx + r * 0.707f
                val handleStartY = circleCy + r * 0.707f
                canvas.drawLine(handleStartX, handleStartY, cx + half * 0.85f, cy + half * 0.85f, paint)
            }

            // Heart
            name.contains("heart") -> {
                val isFilled = name.contains("fill")
                path.moveTo(cx, cy + half * 0.8f)
                path.cubicTo(
                    cx - half * 1.1f, cy,
                    cx - half * 0.9f, cy - half * 0.9f,
                    cx, cy - half * 0.25f
                )
                path.cubicTo(
                    cx + half * 0.9f, cy - half * 0.9f,
                    cx + half * 1.1f, cy,
                    cx, cy + half * 0.8f
                )
                if (isFilled) {
                    canvas.drawPath(path, fillPaint)
                } else {
                    canvas.drawPath(path, paint)
                }
            }

            // Settings / Gear
            name.contains("gear") || name.contains("setting") -> {
                val isFilled = name.contains("fill")
                canvas.drawCircle(cx, cy, half * 0.45f, paint)
                val numTeeth = 6
                for (i in 0 until numTeeth) {
                    val angle = Math.toRadians((i * 360f / numTeeth).toDouble())
                    val x1 = cx + (half * 0.65f) * Math.cos(angle).toFloat()
                    val y1 = cy + (half * 0.65f) * Math.sin(angle).toFloat()
                    val x2 = cx + (half * 0.95f) * Math.cos(angle).toFloat()
                    val y2 = cy + (half * 0.95f) * Math.sin(angle).toFloat()
                    canvas.drawLine(x1, y1, x2, y2, paint)
                }
                if (isFilled) {
                    canvas.drawCircle(cx, cy, half * 0.25f, fillPaint)
                }
            }

            // Plus / Add
            name.contains("plus") || name.contains("add") -> {
                val stroke = paint.strokeWidth
                val plusPaint = Paint(paint).apply { strokeWidth = 6f }
                canvas.drawLine(cx - half * 0.7f, cy, cx + half * 0.7f, cy, plusPaint)
                canvas.drawLine(cx, cy - half * 0.7f, cx, cy + half * 0.7f, plusPaint)
            }

            // Default circle
            else -> {
                canvas.drawCircle(cx, cy, half * 0.5f, fillPaint)
            }
        }
    }

    override fun setAlpha(alpha: Int) {
        paint.alpha = alpha
        fillPaint.alpha = alpha
        invalidateSelf()
    }

    override fun setColorFilter(colorFilter: ColorFilter?) {
        paint.colorFilter = colorFilter
        fillPaint.colorFilter = colorFilter
        invalidateSelf()
    }

    override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
}
