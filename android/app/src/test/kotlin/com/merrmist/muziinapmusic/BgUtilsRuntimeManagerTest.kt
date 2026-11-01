package com.merrmist.muziinapmusic

import java.net.URL
import org.junit.Assert.assertEquals
import org.junit.Test

class BgUtilsRuntimeManagerTest {
    @Test
    fun healthCheckUsesCleartextPermittedLocalhostHost() {
        val url = URL(BgUtilsRuntimeManager.HEALTH_CHECK_URL)

        assertEquals("http", url.protocol)
        assertEquals("localhost", url.host)
        assertEquals("/ping", url.path)
    }
}
