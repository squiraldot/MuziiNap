import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';

class LyricsQuoteCard extends StatelessWidget {
  const LyricsQuoteCard({
    super.key,
    required this.lyric,
    required this.songTitle,
    required this.artist,
    required this.fontFamily,
    required this.fontSize,
    required this.bold,
    required this.themeIndex,
    required this.textAlignment,
    this.artworkUri,
  });

  final String lyric;
  final String songTitle;
  final String artist;
  final String fontFamily;
  final double fontSize;
  final bool bold;
  final int themeIndex;
  final TextAlign textAlignment;
  final Uri? artworkUri;

  static const List<List<Color>> palettes = [
    [Color(0xFF171923), Color(0xFF3A2465)],
    [Color(0xFF102A2A), Color(0xFF287271)],
    [Color(0xFF402020), Color(0xFFB45F38)],
    [Color(0xFF202938), Color(0xFF536A8E)],
  ];

  TextStyle _lyricStyle() {
    final weight = bold ? FontWeight.bold : FontWeight.w500;
    if (fontFamily == 'Poppins') {
      return GoogleFonts.poppins(fontSize: fontSize, fontWeight: weight, height: 1.35);
    }
    return TextStyle(
      fontFamily: fontFamily == 'System' ? null : fontFamily,
      fontSize: fontSize,
      fontWeight: weight,
      height: 1.35,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = palettes[themeIndex.clamp(0, palettes.length - 1)];
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: palette,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (artworkUri != null)
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.13,
                    child: Image.network(
                      artworkUri.toString(),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.graphic_eq_rounded, color: Colors.white70, size: 22),
                        SizedBox(width: 8),
                        Text('MUZIINAP', style: TextStyle(color: Colors.white70, letterSpacing: 2, fontWeight: FontWeight.w700, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Expanded(
                      child: Align(
                        alignment: Alignment.center,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 250),
                            child: Text(
                              '“${lyric.trim()}”',
                              textAlign: textAlignment,
                              style: _lyricStyle().copyWith(color: Colors.white, shadows: const [
                                Shadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 2)),
                              ]),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Container(height: 2, width: 44, color: Colors.white70),
                    const SizedBox(height: 14),
                    Text(songTitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
