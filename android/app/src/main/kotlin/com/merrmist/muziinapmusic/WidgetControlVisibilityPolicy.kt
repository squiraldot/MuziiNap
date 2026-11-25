package com.merrmist.muziinapmusic

internal enum class WidgetRenderMode {
    ACTIVE,
    LIMIT_REACHED,
    UNAVAILABLE
}

internal data class WidgetControlVisibility(val visible: Boolean)

internal object WidgetControlVisibilityPolicy {
    fun forMode(mode: WidgetRenderMode): WidgetControlVisibility =
        WidgetControlVisibility(visible = mode == WidgetRenderMode.ACTIVE)
}
