package org.nativescript.fontmanager

import android.graphics.Typeface

sealed class FontStyle {

  object Normal : FontStyle()

  object Italic : FontStyle()

  data class Oblique(val angle: Int = 0) : FontStyle()

  val fontStyle: Int
    get() = when (this) {
      Normal -> Typeface.NORMAL
      Italic -> Typeface.ITALIC
      is Oblique -> Typeface.NORMAL
    }

  override fun toString(): String = when (this) {
    Normal -> "normal"
    Italic -> "italic"
    is Oblique -> {
      if (angle == 0) "oblique" else "oblique $angle"
    }
  }

  companion object {
    @JvmField
    val NORMAL = Normal

    @JvmField
    val ITALIC = Italic

    @JvmStatic
    fun oblique(angle: Int = 0) = Oblique(angle)
  }
}
