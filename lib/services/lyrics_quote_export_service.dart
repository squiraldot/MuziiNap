import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class LyricsQuoteExportService {
  const LyricsQuoteExportService();

  Future<bool> sharePng(GlobalKey boundaryKey, {String filename = 'muziinap-lyric.png'}) async {
    try {
      await WidgetsBinding.instance.endOfFrame;
      final context = boundaryKey.currentContext;
      final renderObject = context?.findRenderObject();
      if (renderObject is! RenderRepaintBoundary || !renderObject.hasSize) {
        return false;
      }

      final ui.Image image = await renderObject.toImage(pixelRatio: 3);
      try {
        final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) return false;
        final Uint8List bytes = data.buffer.asUint8List();
        final directory = await getTemporaryDirectory();
        final safeName = filename.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
        final file = File('${directory.path}/$safeName');
        await file.writeAsBytes(bytes, flush: true);
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'image/png')],
          text: 'Shared from MuziiNap',
        );
        return true;
      } finally {
        image.dispose();
      }
    } catch (_) {
      // Share sheets can be dismissed and platform share handlers can fail.
      // Keep failures local to this action rather than crashing playback.
      return false;
    }
  }
}
