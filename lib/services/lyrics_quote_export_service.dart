import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class LyricsQuoteExportService {
  const LyricsQuoteExportService();

  Future<bool> sharePng(
    GlobalKey boundaryKey, {
    String filename = 'muziinap-lyric.png',
  }) async {
    try {
      await WidgetsBinding.instance.endOfFrame;
      final context = boundaryKey.currentContext;
      final renderObject = context?.findRenderObject();
      if (renderObject is! RenderRepaintBoundary || !renderObject.hasSize) {
        return false;
      }

      final ui.Image image = await renderObject.toImage(pixelRatio: 3);
      Uint8List bytes;
      try {
        final ByteData? data =
            await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) return false;
        bytes = data.buffer.asUint8List();
      } finally {
        image.dispose();
      }

      // Explicitly enforce transparent rounded corners in the exported file.
      // This protects the PNG even if the captured widget's edge pixels are
      // unexpectedly opaque. Radius matches LyricsQuoteCard's 24 logical px
      // radius at the 3x export scale (7.5% of its 320px logical width).
      bytes = _applyRoundedCornerAlphaMask(bytes);

      final directory = await getTemporaryDirectory();
      final safeName =
          filename.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final file = File('${directory.path}/$safeName');
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: 'Shared from MuziiNap',
      );
      return true;
    } catch (_) {
      // Share sheets can be dismissed and platform share handlers can fail.
      // Keep failures local to this action rather than crashing playback.
      return false;
    }
  }

  Uint8List _applyRoundedCornerAlphaMask(Uint8List pngBytes) {
    final decoded = img.decodePng(pngBytes);
    if (decoded == null || decoded.width == 0 || decoded.height == 0) {
      throw const FormatException('Could not decode quote card PNG.');
    }

    final width = decoded.width;
    final height = decoded.height;
    final radius = width * 0.075;
    final radiusSquared = radius * radius;

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final inLeft = x + 0.5 < radius;
        final inRight = x + 0.5 >= width - radius;
        final inTop = y + 0.5 < radius;
        final inBottom = y + 0.5 >= height - radius;

        // Only pixels in the four corner squares need the circular mask.
        if (!(inLeft || inRight) || !(inTop || inBottom)) continue;

        final centerX = inLeft ? radius : width - radius;
        final centerY = inTop ? radius : height - radius;
        final dx = (x + 0.5) - centerX;
        final dy = (y + 0.5) - centerY;
        final distanceSquared = dx * dx + dy * dy;
        if (distanceSquared <= radiusSquared) continue;

        final distance = math.sqrt(distanceSquared);
        // Keep a one-pixel antialiased transition instead of jagged edges.
        final coverage = (radius + 0.5 - distance).clamp(0.0, 1.0);
        final pixel = decoded.getPixel(x, y);
        final alpha = (pixel.a.toDouble() * coverage).round();
        decoded.setPixelRgba(
          x,
          y,
          pixel.r.toInt(),
          pixel.g.toInt(),
          pixel.b.toInt(),
          alpha,
        );
      }
    }

    return Uint8List.fromList(img.encodePng(decoded));
  }
}
