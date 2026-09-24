package org.nativescript.fontmanager

import android.content.Context
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertTrue
import java.io.File
import java.io.IOException
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

val context: Context get() = InstrumentationRegistry.getInstrumentation().targetContext

fun fontBytes(resId: Int = R.font.stix_two_text_regular): ByteArray =
  context.resources.openRawResource(resId).use { it.readBytes() }

fun fontFile(name: String): File = File(context.cacheDir, name).apply { writeBytes(fontBytes()) }

fun FontFace.loadAndWait(): String? {
  val done = CountDownLatch(1)
  var error: String? = null
  load(context) { error = it; done.countDown() }
  assertTrue("load of $fontFamily never called back", done.await(10, TimeUnit.SECONDS))
  return error
}

/** Answers each request with whatever [handler] writes for its path. */
class TestServer(private val handler: (path: String, socket: Socket) -> Unit) : AutoCloseable {
  private val server = ServerSocket(0)
  val base = "http://127.0.0.1:${server.localPort}"

  init {
    thread(isDaemon = true) {
      while (!server.isClosed) {
        val socket = try { server.accept() } catch (_: IOException) { break }
        thread(isDaemon = true) {
          socket.use {
            val requestLine = it.getInputStream().bufferedReader().readLine() ?: return@use
            handler(requestLine.split(" ")[1], it)
          }
        }
      }
    }
  }

  override fun close() = server.close()

  companion object {
    fun respond(socket: Socket, body: ByteArray) {
      val out = socket.getOutputStream()
      out.write("HTTP/1.1 200 OK\r\nContent-Length: ${body.size}\r\nConnection: close\r\n\r\n".toByteArray())
      out.write(body)
      out.flush()
    }
  }
}
