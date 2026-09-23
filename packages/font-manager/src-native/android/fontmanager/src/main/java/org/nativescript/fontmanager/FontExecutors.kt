package org.nativescript.fontmanager

import java.util.ArrayDeque
import java.util.concurrent.Executor
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

internal object FontExecutors {
  private fun pool(threads: Int, name: String): Executor = ThreadPoolExecutor(
    threads, threads, 30L, TimeUnit.SECONDS, LinkedBlockingQueue()
  ) { r -> Thread(r, name).apply { isDaemon = true } }
    .apply { allowCoreThreadTimeOut(true) }

  /**
   * One pool for all non-blocking font work. Core threads are allowed to time out,
   * so an app holding many [FontFace]s costs no threads at rest — previously each
   * face owned a single-thread executor that lived for the process lifetime.
   */
  val shared: Executor = pool(2, "ns-font-manager")

  /**
   * Separate pool for work that blocks on the network — a download parks its thread
   * for the whole transfer. On [shared] two slow remote fonts occupied both of its
   * threads and stalled every unrelated face, including local file loads; it is
   * wider than [shared] for the same reason, since its threads are mostly waiting.
   */
  val io: Executor = pool(4, "ns-font-manager-io")

  fun serial(delegate: Executor = shared): Executor = SerialExecutor(delegate)
}

/**
 * Runs its tasks one at a time, in submission order, on [delegate].
 *
 * This preserves the ordering guarantee each face used to get from owning a
 * dedicated single-thread executor, without owning a thread.
 */
internal class SerialExecutor(private val delegate: Executor) : Executor {
  private val tasks = ArrayDeque<Runnable>()
  private var active: Runnable? = null

  override fun execute(command: Runnable) {
    synchronized(tasks) {
      tasks.add(Runnable {
        try {
          command.run()
        } finally {
          scheduleNext()
        }
      })
      if (active == null) scheduleNext()
    }
  }

  private fun scheduleNext() {
    synchronized(tasks) {
      active = tasks.poll()
      active?.let { delegate.execute(it) }
    }
  }
}
