package org.nativescript.fontmanager

import org.junit.Assert.assertEquals
import org.junit.Test

class FontParserSizeTest {
  private fun size(shorthand: String): Int? = FontParser.parse(shorthand)?.sizePx

  @Test
  fun `fractional pixel sizes parse`() {
    assertEquals(12, size("12.4px Foo"))
    assertEquals(listOf("Foo"), FontParser.parse("12.4px/1.2 Foo")!!.families)
  }

  @Test
  fun `relative and point units convert to pixels`() {
    assertEquals(16, size("12pt Foo"))
    assertEquals(24, size("1.5em Foo"))
    assertEquals(20, size("1.25rem Foo"))
    assertEquals(16, size("bold 100% Foo"))
  }

  @Test
  fun `absolute size keywords parse`() {
    assertEquals(16, size("medium Foo"))
    assertEquals(24, size("italic x-large Foo, serif"))
    assertEquals(listOf("Foo", "serif"), FontParser.parse("italic x-large Foo, serif")!!.families)
  }
}
