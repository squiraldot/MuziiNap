package com.merrmist.muziinapmusic

/** Resolves artwork strictly within the selected widget-size directory. */
internal object ThemeWidgetAssetPath {
    private const val THEME_DIRECTORY = "assets/widget_assets/Dragon_Ball_Z"

    fun resolve(widgetFolder: String, fileName: String): String {
        require(widgetFolder == "4x2" || widgetFolder == "4x3") {
            "Unsupported music widget size: $widgetFolder"
        }
        require(fileName == "Background.png" || fileName == "Border.png" || fileName == "Character.png") {
            "Unsupported music widget image: $fileName"
        }
        return "$THEME_DIRECTORY/$widgetFolder/Widget1/$fileName"
    }
}
