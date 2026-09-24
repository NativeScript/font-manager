package org.nativescript.fontmanager

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
class FontFaceSetTest {
  private val set = FontFaceSet()

  @Test
  fun statusIsLoadingUntilEveryLoadHasFinished() {
    val font = fontBytes()
    TestServer { _, socket ->
      Thread.sleep(500)
      TestServer.respond(socket, font)
    }.use { server ->
      set.add(FontFace("Slow", "${server.base}/slow.ttf"))
      val done = CountDownLatch(1)
      var error: String? = "not called"
      set.load(context, "16px Slow") { _, e -> error = e; done.countDown() }
      set.load(context, "16px NotRegistered")
      assertEquals(FontFaceSet.Status.Loading, set.status)

      assertTrue(done.await(10, TimeUnit.SECONDS))
      assertNull(error)
      assertEquals(FontFaceSet.Status.Loaded, set.status)
    }
  }

  @Test
  fun checkIsTrueOnlyWhenUsingTheFontWouldNotStartALoad() {
    set.add(FontFace("Pending", fontFile("check-pending.ttf").absolutePath))
    val loaded = FontFace("serif")
    assertNull(loaded.loadAndWait())
    set.add(loaded)

    assertFalse(set.check("16px Pending", null))
    assertTrue(set.check("16px serif", null))
    assertTrue(set.check("16px NoSuchFamily", null))
  }
}
