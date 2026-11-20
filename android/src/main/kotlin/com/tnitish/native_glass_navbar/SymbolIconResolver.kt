package com.tnitish.native_glass_navbar

import android.content.Context
import android.graphics.Color
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.LayerDrawable
import androidx.core.content.ContextCompat
import androidx.core.graphics.drawable.DrawableCompat

object SymbolIconResolver {

    /**
     * Resolves an iOS SF Symbol or asset icon name into an Android Vector/Drawable.
     * Matches standard SF symbols used in Flutter apps to Android built-in vector icons.
     */
    fun resolveDrawable(context: Context, symbolName: String, tintColor: Int): Drawable {
        val resourceId = getSystemEquivalentResourceId(symbolName)

        val drawable: Drawable = if (resourceId != 0) {
            try {
                ContextCompat.getDrawable(context, resourceId) ?: createFallbackVector(symbolName)
            } catch (e: Exception) {
                createFallbackVector(symbolName)
            }
        } else {
            // Check application package resources for custom asset drawables
            val resId = context.resources.getIdentifier(symbolName, "drawable", context.packageName)
            if (resId != 0) {
                try {
                    ContextCompat.getDrawable(context, resId) ?: createFallbackVector(symbolName)
                } catch (e: Exception) {
                    createFallbackVector(symbolName)
                }
            } else {
                createFallbackVector(symbolName)
            }
        }

        val wrapped = DrawableCompat.wrap(drawable.mutate())
        DrawableCompat.setTint(wrapped, tintColor)
        return wrapped
    }

    private fun getSystemEquivalentResourceId(symbolName: String): Int {
        val name = symbolName.lowercase()
        return when {
            name.contains("house") || name.contains("home") -> android.R.drawable.ic_menu_today
            name.contains("magnifyingglass") || name.contains("search") -> android.R.drawable.ic_menu_search
            name.contains("gear") || name.contains("setting") -> android.R.drawable.ic_menu_preferences
            name.contains("heart") -> android.R.drawable.star_big_on
            name.contains("star") -> android.R.drawable.btn_star_big_on
            name.contains("person") || name.contains("profile") || name.contains("user") -> android.R.drawable.ic_menu_myplaces
            name.contains("bell") || name.contains("notification") -> android.R.drawable.ic_popup_reminder
            name.contains("plus") || name.contains("add") -> android.R.drawable.ic_input_add
            name.contains("edit") || name.contains("pencil") -> android.R.drawable.ic_menu_edit
            name.contains("trash") || name.contains("delete") -> android.R.drawable.ic_menu_delete
            name.contains("mail") || name.contains("message") -> android.R.drawable.ic_dialog_email
            name.contains("share") -> android.R.drawable.ic_menu_share
            name.contains("info") -> android.R.drawable.ic_dialog_info
            name.contains("camera") -> android.R.drawable.ic_menu_camera
            name.contains("photo") || name.contains("image") -> android.R.drawable.ic_menu_gallery
            else -> 0
        }
    }

    private fun createFallbackVector(name: String): Drawable {
        // Fallback procedural geometric icon
        val shape = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setSize(48, 48)
            setColor(Color.WHITE)
        }
        return shape
    }
}
