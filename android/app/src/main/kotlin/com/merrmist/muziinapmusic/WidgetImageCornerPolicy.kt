package com.merrmist.muziinapmusic

import kotlin.math.min

/**
 * Keeps background corner curvature proportional to widget image dimensions,
 * so the visible radius stays consistent when Android scales the bitmap.
 */
internal object WidgetImageCornerPolicy {
    private const val BACKGROUND_CORNER_RATIO = 0.095f

    fun backgroundRadius(width: Int, height: Int): Float {
        if (width <= 0 || height <= 0) return 0f
        return min(width, height) * BACKGROUND_CORNER_RATIO
    }
}
