package com.merrmist.muziinapmusic

import org.junit.Assert.assertEquals
import org.junit.Test

class WidgetImageCornerPolicyTest {
    @Test
    fun backgroundRadiusScalesWithTheShorterImageEdge() {
        assertEquals(12.16f, WidgetImageCornerPolicy.backgroundRadius(256, 128), 0.001f)
        assertEquals(24.32f, WidgetImageCornerPolicy.backgroundRadius(512, 256), 0.001f)
    }

    @Test
    fun backgroundRadiusIsZeroForInvalidDimensions() {
        assertEquals(0f, WidgetImageCornerPolicy.backgroundRadius(0, 128), 0f)
        assertEquals(0f, WidgetImageCornerPolicy.backgroundRadius(256, -1), 0f)
    }
}
