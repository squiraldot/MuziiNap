package com.merrmist.muziinapmusic

/** Resolves only validated theme/design/size asset paths from the bundled registry. */
internal object ThemeWidgetAssetPath {
    private val safeId = Regex("^[a-z0-9]+(?:-[a-z0-9]+)*$")

    fun resolve(themeId: String, designId: String, widgetFolder: String, fileName: String): String {
        require(safeId.matches(themeId)) { "Invalid theme identifier" }
        require(safeId.matches(designId)) { "Invalid design identifier" }
        require(widgetFolder == "4x2" || widgetFolder == "4x3") {
            "Unsupported music widget size: $widgetFolder"
        }
        require(fileName == "Background.png" || fileName == "Border.png" ||
            fileName == "Character.png" || fileName == "Effects.png") {
            "Unsupported music widget image: $fileName"
        }
        val themeDirectory = themeId.split("-").joinToString("_") { part ->
            part.replaceFirstChar { it.uppercase() }
        }
        val designDirectory = designId.split("-").joinToString("") { part ->
            part.replaceFirstChar { it.uppercase() }
        }
        return "assets/widget_assets/$themeDirectory/$widgetFolder/$designDirectory/$fileName"
    }

    /** Compatibility overload for Phase 02's original Dragon Ball Z asset tests. */
    fun resolve(widgetFolder: String, fileName: String): String =
        resolve("dragon-ball-z", "widget-1", widgetFolder, fileName)
}
