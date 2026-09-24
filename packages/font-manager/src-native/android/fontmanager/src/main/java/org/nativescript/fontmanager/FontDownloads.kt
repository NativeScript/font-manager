package org.nativescript.fontmanager

import java.io.File
import java.io.IOException
import java.io.InputStream
import java.net.URL
import java.net.URLConnection
import java.security.MessageDigest

internal object FontDownloads {
  private const val TIMEOUT_MS = 15_000

  fun fetch(url: String, dir: File, timeoutMs: Int = TIMEOUT_MS): File {
    val extension = url.substringBefore('?').substringBefore('#').substringAfterLast('/').substringAfterLast('.', "")
    val name = sha1(url) + if (extension.isEmpty()) "" else ".$extension"
    val target = File(dir, name)
    if (target.exists()) return target
    dir.mkdirs()
    val temp = File.createTempFile(name, ".part", dir)
    try {
      val connection = open(url, timeoutMs)
      val written = connection.getInputStream().use { input -> temp.outputStream().use { input.copyTo(it) } }
      val expected = connection.contentLengthLong
      if (expected >= 0 && written != expected) {
        throw IOException("Download of $url ended after $written of $expected bytes")
      }
      if (!temp.renameTo(target) && !target.exists()) {
        throw IOException("Could not move the download of $url into the font cache")
      }
    } finally {
      temp.delete()
    }
    return target
  }

  fun readText(url: String, timeoutMs: Int = TIMEOUT_MS): String =
    open(url, timeoutMs).getInputStream().use { String(it.readBytes()) }

  private fun open(url: String, timeoutMs: Int): URLConnection =
    URL(url).openConnection().apply {
      connectTimeout = timeoutMs
      readTimeout = timeoutMs
    }

  private fun sha1(value: String): String =
    MessageDigest.getInstance("SHA-1").digest(value.toByteArray()).joinToString("") { "%02x".format(it) }
}
