package org.nativescript.fontmanager

import java.util.regex.Matcher

class FontDescriptors(var family: String) {
  var weight: FontWeight
  var ascentOverride: String
  var descentOverride: String
  var display: FontDisplay
  var style: FontStyle
  var variant: String
  var stretch: String
  var unicodeRange: String
  var featureSettings: String
  var lineGapOverride: String
  var variationSettings: String
  var kerning: String
  var variantLigatures: String

  init {
    weight = FontWeight.Normal
    this.ascentOverride = "normal"
    this.descentOverride = "normal"
    this.display = FontDisplay.Auto
    this.style = FontStyle.Normal
    this.variant = "normal"
    this.stretch = "normal"
    this.unicodeRange = "U+0-10FFFF"
    this.featureSettings = "normal"
    this.variationSettings = "normal"
    this.lineGapOverride = "normal"
    this.kerning = "auto"
    this.variantLigatures = "normal"
  }

  internal fun update(value: String) {

    val matcher: Matcher = Constants.FONT_FACE_PATTERN.matcher(value)
    while (matcher.find()) {
      val match = matcher.group(1) ?: continue

      Constants.FONT_WEIGHT_PATTERN.find(match)?.groupValues?.get(1)?.let { setFontWeight(it) }
      Constants.FONT_STYLE_PATTERN.find(match)?.groupValues?.get(1)?.let { setFontStyle(it) }
      Constants.FONT_DISPLAY_PATTERN.find(match)?.groupValues?.get(1)?.let { setFontDisplay(it) }
      Constants.FONT_STRETCH_PATTERN.find(match)?.groupValues?.get(1)?.let { stretch = it }
      Constants.FONT_FEATURE_SETTINGS_PATTERN.find(match)?.groupValues?.get(1)?.let { featureSettings = it }
      Constants.FONT_VARIATION_SETTINGS_PATTERN.find(match)?.groupValues?.get(1)
        ?.let { variationSettings = it }
      Constants.UNICODE_RANGE_PATTERN.find(match)?.groupValues?.get(1)?.let { unicodeRange = it }
      Constants.ASCENT_OVERRIDE_PATTERN.find(match)?.groupValues?.get(1)?.let { ascentOverride = it }
      Constants.DESCENT_OVERRIDE_PATTERN.find(match)?.groupValues?.get(1)?.let { descentOverride = it }
      Constants.LINE_GAP_OVERRIDE_PATTERN.find(match)?.groupValues?.get(1)?.let { lineGapOverride = it }
      Constants.FONT_KERNING_PATTERN.find(match)?.groupValues?.get(1)?.let { kerning = it }
      Constants.FONT_VARIANT_LIGATURES_PATTERN.find(match)?.groupValues?.get(1)?.let { variantLigatures = it }
    }

  }

  fun setFontWeight(value: String) {
    when (value) {
      "normal" -> {
        weight = FontWeight.Normal
      }

      "bold" -> {
        weight = FontWeight.Bold
      }

      else -> {
        try {
          weight = FontWeight.from(value.toInt())
        } catch (_: Exception) {
        }
      }
    }
  }

  fun setFontStyle(value: String) {
    when (value) {
      "normal" -> style = FontStyle.Normal
      "italic" -> style = FontStyle.Italic
      else -> {
        Constants.FONT_STYLE_PATTERN.find("font-style: $value")?.let {
          var angle = 0

          try {
            angle = it.groupValues[2].toInt()
          } catch (_: Exception) {
          }

          style = FontStyle.Oblique(angle)
        }
      }
    }
  }

  /** Hash of the CSS matching fields. Non-rendering fields (display, unicodeRange, overrides) excluded. */
  fun renderHash(): Long {
    var h = family.hashCode().toLong()
    h = h * 31 + weight.weight.toLong()
    h = h * 31 + style.hashCode().toLong()
    h = h * 31 + stretch.hashCode().toLong()
    h = h * 31 + variationSettings.hashCode().toLong()
    h = h * 31 + featureSettings.hashCode().toLong()
    return h
  }

  fun setFontDisplay(value: String) {
    when (value) {
      "auto" -> {
        display = FontDisplay.Auto
      }

      "block" -> {
        display = FontDisplay.Block
      }

      "fallback" -> {
        display = FontDisplay.Fallback
      }

      "optional" -> {
        display = FontDisplay.Optional
      }

      "swap" -> {
        display = FontDisplay.Swap
      }
    }
  }

}
