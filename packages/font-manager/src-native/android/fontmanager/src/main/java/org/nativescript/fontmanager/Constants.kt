package org.nativescript.fontmanager

import java.util.regex.Pattern

object Constants {
  val FONT_FAMILY_PATTERN = Regex("font-family:\\s*'([^']+)';")
  val FONT_STYLE_PATTERN =
    Regex("font-style:\\s*(normal|italic|oblique(?:\\s+([-]?\\d+(\\.\\d+)?deg))?);")
  val FONT_WEIGHT_PATTERN = Regex("font-weight:\\s*([^;]+);")
  val FONT_DISPLAY_PATTERN = Regex("font-display:\\s*([^;]+);")
  val FONT_STRETCH_PATTERN = Regex("font-stretch:\\s*([^;]+);")
  val FONT_FEATURE_SETTINGS_PATTERN = Regex("font-feature-settings:\\s*([^;]+);")
  val FONT_VARIATION_SETTINGS_PATTERN = Regex("font-variation-settings:\\s*([^;]+);")
  val UNICODE_RANGE_PATTERN = Regex("unicode-range:\\s*([^;]+);")
  val ASCENT_OVERRIDE_PATTERN = Regex("ascent-override:\\s*([^;]+);")
  val DESCENT_OVERRIDE_PATTERN = Regex("descent-override:\\s*([^;]+);")
  val LINE_GAP_OVERRIDE_PATTERN = Regex("line-gap-override:\\s*([^;]+);")
  val FONT_KERNING_PATTERN = Regex("font-kerning:\\s*([^;]+);")
  val FONT_VARIANT_LIGATURES_PATTERN = Regex("font-variant-ligatures:\\s*([^;]+);")
  val FONT_SRC_PATTERN = Regex("src:\\s*url\\(([^)]+)\\)\\s*format\\('([^']+)'\\);")

  val FONT_FACE_PATTERN: Pattern = Pattern.compile("@font-face\\s*\\{([^}]+)\\}")

}
