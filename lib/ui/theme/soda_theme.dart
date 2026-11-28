import 'dart:io';

import 'package:flutter/material.dart';
import 'package:soda_pulse/models/track.dart';

class SodaColors {
  const SodaColors._();

  static const Color background = Color(0xFF0A0D0E);
  static const Color surface = Color(0xFF13171A);
  static const Color surfaceElevated = Color(0xFF181D20);
  static const Color cyan = Color(0xFF2FE08B);
  static const Color lime = Color(0xFF9DF871);
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color border = Color(0x14FFFFFF);
}

class SodaTheme {
  static const Color bgNight = Color(0xFF0A0D0E);
  static const Color bgDeep = bgNight;
  static const Color bgCard = Color(0xFF13171A);
  static const Color bgElevated = Color(0xFF181D20);
  static const Color seedCyan = Color(0xFF2FE08B);
  static const Color accent = seedCyan;
  static const Color seedMint = Color(0xFF2FE08B);

  static ThemeData buildDarkTheme() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedCyan,
      secondary: seedMint,
      brightness: Brightness.dark,
      surface: bgCard,
    );

    const baseTextTheme = TextTheme(
      headlineMedium: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: Colors.white,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        color: Colors.white,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        color: Colors.white,
      ),
      bodyLarge: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: Color(0xFFE2E8F0),
      ),
      bodyMedium: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: Color(0xFF94A3B8),
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.3,
        color: Color(0xFF64748B),
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: bgNight,
      cardColor: bgCard,
      textTheme: baseTextTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      iconTheme: const IconThemeData(
        color: Colors.white,
      ),
      dividerColor: Colors.white.withValues(alpha: 0.08),
    );
  }

  static BoxDecoration glassCard({
    Color? tint,
    double radius = 20,
    double borderAlpha = 0.12,
  }) {
    final baseColor = tint ?? bgElevated;
    return BoxDecoration(
      color: baseColor.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: Colors.white.withValues(alpha: borderAlpha),
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.28),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  static String formatDuration(int ms) {
    final safeMs = ms < 0 ? 0 : ms;
    final totalSeconds = safeMs ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final minStr = minutes.toString().padLeft(2, '0');
    final secStr = seconds.toString().padLeft(2, '0');
    return '$minStr:$secStr';
  }
}

class CoverArtWidget extends StatelessWidget {
  const CoverArtWidget({
    super.key,
    this.track,
    this.localPath,
    required this.accentColor,
    required this.size,
    this.borderRadius = 16,
    this.showVinylRing = false,
  });

  final Track? track;
  final String? localPath;
  final Color accentColor;
  final double size;
  final double borderRadius;
  final bool showVinylRing;

  static const String defaultUserAgent =
      'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  static Map<String, String> networkHeadersFor(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('music.126.net') || lower.contains('music.163.com')) {
      return const {'Referer': 'https://music.163.com/'};
    }
    return const <String, String>{};
  }

  static String resolveNetworkUrl(String url, {required double size}) {
    var resolved = url.trim();
    final lower = resolved.toLowerCase();
    if (lower.contains('music.126.net')) {
      if (lower.startsWith('http://')) {
        resolved = 'https://${resolved.substring(7)}';
      }
      if (!resolved.toLowerCase().contains('param=')) {
        final param = size <= 140 ? 'param=200y200' : 'param=600y600';
        resolved = resolved.contains('?')
            ? '$resolved&$param'
            : '$resolved?$param';
      }
    }
    return resolved;
  }

  @override
  Widget build(BuildContext context) {
    final fallback = _buildPlaceholder();
    final path = localPath;
    final uri = track?.albumArtUri?.trim();
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    final decodePx = (size * dpr).round().clamp(64, 1024);

    Widget? imageWidget;
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      imageWidget = Image.file(
        File(path),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: decodePx,
        cacheHeight: decodePx,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    } else if (uri != null &&
        (uri.startsWith('http://') || uri.startsWith('https://'))) {
      final resolved = resolveNetworkUrl(uri, size: size);
      final headers = networkHeadersFor(resolved);
      imageWidget = Image.network(
        resolved,
        headers: headers.isEmpty ? null : headers,
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: decodePx,
        cacheHeight: decodePx,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius),
            child: Stack(
              fit: StackFit.expand,
              children: [
                fallback,
                if (imageWidget != null) imageWidget,
              ],
            ),
          ),
          if (showVinylRing)
            IgnorePointer(
              child: Container(
                width: size * 0.88,
                height: size * 0.88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: Container(
                    width: size * 0.22,
                    height: size * 0.22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: SodaTheme.bgNight.withValues(alpha: 0.72),
                      border: Border.all(
                        color: accentColor.withValues(alpha: 0.55),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accentColor.withValues(alpha: 0.35),
            SodaTheme.bgElevated,
            SodaTheme.bgCard,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          showVinylRing ? Icons.album_rounded : Icons.music_note_rounded,
          size: size * 0.4,
          color: Colors.white.withValues(alpha: 0.65),
        ),
      ),
    );
  }
}
