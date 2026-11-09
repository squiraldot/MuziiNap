package com.merrmist.muziinapmusic

import java.util.concurrent.atomic.AtomicBoolean

/** Single-flight guard shared by every BgUtils setup request. */
internal class BgUtilsSetupGate {
    private val active = AtomicBoolean(false)

    fun tryAcquire(): Boolean = active.compareAndSet(false, true)

    fun release() {
        active.set(false)
    }

    fun isActive(): Boolean = active.get()
}
