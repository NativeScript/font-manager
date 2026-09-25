package org.nativescript.fontmanager

import android.graphics.Typeface
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class GenericFamilyTest {
  @Test
  fun genericFamiliesResolveToTheMatchingSystemFamily() {
    for ((css, system) in listOf("cursive" to "cursive", "ui-serif" to "serif", "ui-monospace" to "monospace", "fantasy" to "casual")) {
      val face = FontFace(css)
      assertNull(face.loadAndWait())
      assertSame(css, Typeface.create(system, Typeface.NORMAL), face.font)
    }
  }

  @Test
  fun anItalicSerifFaceIsItalic() {
    val face = FontFace("serif").setFontStyle("italic")
    assertNull(face.loadAndWait())
    assertTrue(face.font!!.isItalic)
  }
}
