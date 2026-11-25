/// Bundled, locally discoverable widget themes. Remote catalog discovery is intentionally absent.
class ThemeWidgetDesignDefinition {
  const ThemeWidgetDesignDefinition({
    required this.designId,
    required this.name,
    required this.supportedSizes,
    this.remotePreviewUrl,
  });

  final String designId;
  final String name;
  final List<String> supportedSizes;
  final String? remotePreviewUrl;
}

class ThemeWidgetPackDefinition {
  const ThemeWidgetPackDefinition({
    required this.themeId,
    required this.name,
    required this.designs,
  });

  final String themeId;
  final String name;
  final List<ThemeWidgetDesignDefinition> designs;
}

const List<ThemeWidgetPackDefinition> bundledThemeWidgetCatalog =
    <ThemeWidgetPackDefinition>[
  ThemeWidgetPackDefinition(
    themeId: 'dragon-ball-z',
    name: 'Dragon Ball Z',
    designs: <ThemeWidgetDesignDefinition>[
      ThemeWidgetDesignDefinition(
        designId: 'widget-1',
        name: 'Widget 1',
        supportedSizes: <String>['4x2'],
      ),
    ],
  ),
];
