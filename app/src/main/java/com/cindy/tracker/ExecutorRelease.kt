package com.cindy.tracker

import java.util.concurrent.ExecutorService

/**
 * Stops accepting work, and runs [release] on this executor after whatever is already queued or
 * running.
 *
 * `shutdown()` alone does not wait for the task in flight, so freeing a native resource right
 * after it frees it under that task. The analysis thread is the one that runs the pose model, and
 * closing the interpreter while it is mid-frame is a SIGSEGV in `NativeInterpreterWrapper.run`
 * that takes the whole process down as the athlete leaves the camera screen. A single-thread
 * executor runs tasks in order, so [release] runs once the current frame is done.
 */
internal fun ExecutorService.releaseAfterPending(release: () -> Unit) {
    execute(release)
    shutdown()
}
