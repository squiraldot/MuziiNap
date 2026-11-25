import 'package:flutter_test/flutter_test.dart';
import 'package:muziinap/services/theme_widget_catalog.dart';

void main() {
  group('bundledThemeWidgetCatalog', () {
    test('contains only explicitly registered theme packs', () {
      expect(bundledThemeWidgetCatalog.map((pack) => pack.themeId),
          contains('dragon-ball-z'));
      expect(bundledThemeWidgetCatalog, hasLength(1));
    });

    test('keeps design identity independent from widget size', () {
      final design = bundledThemeWidgetCatalog.single.designs.single;
      expect(design.designId, 'widget-1');
      expect(design.supportedSizes, <String>['4x2']);
    });

    test('does not invent a remote preview URL when none is registered', () {
      expect(bundledThemeWidgetCatalog.single.designs.single.remotePreviewUrl, isNull);
    });

    test('uses the bundled 4x2 artwork for a local Gallery preview', () {
      final design = bundledThemeWidgetCatalog.single.designs.single;
      expect(design.previewBackgroundAsset, endsWith('/Background.png'));
      expect(design.previewBorderAsset, endsWith('/Border.png'));
      expect(design.previewCharacterAsset, endsWith('/Character.png'));
    });
  });
}
