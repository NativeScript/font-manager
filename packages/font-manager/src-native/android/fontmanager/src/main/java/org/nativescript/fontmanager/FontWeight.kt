package org.nativescript.fontmanager

enum class FontWeight(val weight: Int) {
  Thin(100),
  ExtraLight(200),
  Light(300),
  Normal(400),
  Medium(500),
  SemiBold(600),
  Bold(700),
  ExtraBold(800),
  Black(900);

  val raw: Int
    get() {
      return weight
    }


  companion object {
    @JvmStatic
    fun from(value: Int): FontWeight {
      if (value < 100) {
        return Thin
      }
      return when (value) {
        in 100..199 -> Thin
        in 200..299 -> ExtraLight
        in 300..399 -> Light
        in 400..499 -> Normal
        in 500..599 -> Medium
        in 600..699 -> SemiBold
        in 700..799 -> Bold
        in 800..899 -> ExtraBold
        else -> Black
      }
    }
  }
}
