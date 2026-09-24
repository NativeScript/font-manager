package org.nativescript.fontmanager

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
class ImportFromRemoteTest {
  @After
  fun tearDown() {
    FontFaceSet.instance.clear()
  }

  @Test
  fun importsEveryFaceInParallelAndAnswersOnceAllAreLoaded() {
    val font = fontBytes()
    val faces = 4
    val delayMs = 600L
    TestServer { path, socket ->
      if (path == "/fonts.css") {
        val css = (0 until faces).joinToString("\n") { i ->
          "@font-face { font-family: 'Remote$i'; font-weight: 400; src: url(http://127.0.0.1:${socket.localPort}/f$i.ttf) format('truetype'); }"
        }
        TestServer.respond(socket, css.toByteArray())
      } else {
        Thread.sleep(delayMs)
        TestServer.respond(socket, font)
      }
    }.use { server ->
      val done = CountDownLatch(1)
      var result: List<FontFace> = emptyList()
      var error: String? = "not called"
      val started = System.nanoTime()
      FontFace.importFromRemote(context, "${server.base}/fonts.css", true) { fonts, e ->
        result = fonts
        error = e
        done.countDown()
      }
      assertTrue("import never called back", done.await(20, TimeUnit.SECONDS))
      val elapsedMs = (System.nanoTime() - started) / 1_000_000

      assertNull(error)
      assertEquals(faces, result.size)
      result.forEach {
        assertEquals(FontFaceStatus.Loaded, it.status)
        assertNotNull(it.font)
      }
      assertTrue("$faces downloads of ${delayMs}ms took ${elapsedMs}ms", elapsedMs < delayMs * 3)
    }
  }
}
