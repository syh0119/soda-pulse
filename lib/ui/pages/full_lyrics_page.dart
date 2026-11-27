import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:soda_pulse/core/app_store.dart';
import 'package:soda_pulse/ui/pages/island_settings_page.dart';
import 'package:soda_pulse/ui/widgets/karaoke_lyric_view.dart';
import 'package:soda_pulse/ui/widgets/star_skin_bg.dart';

class FullLyricsPage extends StatefulWidget {
  const FullLyricsPage({super.key, required this.store});

  final AppStore store;

  @override
  State<FullLyricsPage> createState() => _FullLyricsPageState();
}

class _FullLyricsPageState extends State<FullLyricsPage> {
  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final topPadding = MediaQuery.paddingOf(context).top;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final track = store.currentTrack;
        final accent = store.accentColor;
        final style = store.fullLyricStyle;
        final isAppleBlur = style == FullLyricStyle.appleBlur;
        final isMinimal = store.minimalLyricMode;
        final offsetMs = store.bridge.lyricOffsetMs;
        final floatingEnabled = store.bridge.floatingLyricEnabled;
        final isFav = track != null && store.isFavorite(track.id);
        final coverPath = track != null ? store.coverPathFor(track) : null;

        final primaryTextColor =
            isAppleBlur ? Colors.white : const Color(0xFF0F172A);
        final secondaryTextColor = isAppleBlur
            ? Colors.white.withValues(alpha: 0.72)
            : const Color(0xFF475569);
        final pillBgColor = isAppleBlur
            ? Colors.white.withValues(alpha: 0.14)
            : const Color(0xFF0F172A).withValues(alpha: 0.08);
        final pillBorderColor = isAppleBlur
            ? Colors.white.withValues(alpha: 0.22)
            : const Color(0xFF0F172A).withValues(alpha: 0.12);

        return Scaffold(
          backgroundColor: isAppleBlur
              ? const Color(0xFF0B0F1A)
              : Color.lerp(const Color(0xFFF3F6FB), accent, 0.14)!,
          body: Stack(
            fit: StackFit.expand,
            children: [
              _buildBackground(
                store: store,
                isAppleBlur: isAppleBlur,
                accent: accent,
                coverPath: coverPath,
              ),
              Column(
                children: [
                  Padding(
                    padding: EdgeInsets.only(
                      top: topPadding + 8,
                      left: 12,
                      right: 12,
                      bottom: 8,
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: primaryTextColor,
                            size: 28,
                          ),
                          tooltip: '返回',
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                track?.title ?? '未播放曲目',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: primaryTextColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (track != null && track.artist.isNotEmpty)
                                Text(
                                  track.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: secondaryTextColor,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (track != null)
                          IconButton(
                            onPressed: () => store.toggleFavorite(track),
                            icon: Icon(
                              isFav
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              color: isFav
                                  ? accent
                                  : primaryTextColor.withValues(alpha: 0.85),
                              size: 22,
                            ),
                            tooltip: isFav ? '取消收藏' : '收藏',
                          ),
                        const SizedBox(width: 4),
                        _StyleTogglePill(
                          isAppleBlur: isAppleBlur,
                          textColor: primaryTextColor,
                          backgroundColor: pillBgColor,
                          borderColor: pillBorderColor,
                          onTap: () {
                            store.setFullLyricStyle(
                              isAppleBlur
                                  ? FullLyricStyle.starPure
                                  : FullLyricStyle.appleBlur,
                            );
                          },
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          onPressed: () =>
                              store.setMinimalLyricMode(!isMinimal),
                          icon: Icon(
                            isMinimal
                                ? Icons.fullscreen_exit_rounded
                                : Icons.fullscreen_rounded,
                            color: primaryTextColor,
                            size: 22,
                          ),
                          tooltip: isMinimal ? '退出极简' : '极简模式',
                        ),
                        PopupMenuButton<_LyricMenuAction>(
                          icon: Icon(
                            Icons.more_vert_rounded,
                            color: primaryTextColor,
                            size: 22,
                          ),
                          onSelected: (action) {
                            switch (action) {
                              case _LyricMenuAction.importLyric:
                                store.importExternalLyricForCurrentTrack();
                              case _LyricMenuAction.islandSettings:
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        IslandSettingsPage(bridge: store.bridge),
                                  ),
                                );
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem<_LyricMenuAction>(
                              value: _LyricMenuAction.importLyric,
                              child: Text('导入外部歌词'),
                            ),
                            PopupMenuItem<_LyricMenuAction>(
                              value: _LyricMenuAction.islandSettings,
                              child: Text('灵动岛设置'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: isMinimal
                          ? () => store.setMinimalLyricMode(false)
                          : null,
                      child: KaraokeLyricView(
                        lyrics: store.currentLyrics,
                        positionProvider: () => store.positionMs,
                        offsetMs: offsetMs,
                        accentColor: accent,
                        onSeekToMs: store.seekTo,
                      ),
                    ),
                  ),
                  if (!isMinimal)
                    Padding(
                      padding: EdgeInsets.only(
                        left: 16,
                        right: 16,
                        top: 8,
                        bottom: bottomPadding + 16,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                _ControlPill(
                                  label: '-50ms',
                                  textColor: primaryTextColor,
                                  backgroundColor: pillBgColor,
                                  borderColor: pillBorderColor,
                                  onTap: () => store.bridge
                                      .setLyricOffset(offsetMs - 50),
                                ),
                                _ControlPill(
                                  label: offsetMs == 0
                                      ? '0ms'
                                      : '${offsetMs > 0 ? '+' : ''}${offsetMs}ms',
                                  textColor: offsetMs == 0
                                      ? primaryTextColor
                                      : accent,
                                  backgroundColor: pillBgColor,
                                  borderColor: offsetMs == 0
                                      ? pillBorderColor
                                      : accent.withValues(alpha: 0.5),
                                  onTap: () => store.bridge.setLyricOffset(0),
                                ),
                                _ControlPill(
                                  label: '+50ms',
                                  textColor: primaryTextColor,
                                  backgroundColor: pillBgColor,
                                  borderColor: pillBorderColor,
                                  onTap: () => store.bridge
                                      .setLyricOffset(offsetMs + 50),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Material(
                            color: accent,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: store.togglePlayPause,
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Icon(
                                  store.isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 28,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: _ControlPill(
                                label: '桌面歌词',
                                isActive: floatingEnabled,
                                accentColor: accent,
                                textColor: floatingEnabled
                                    ? Colors.white
                                    : primaryTextColor,
                                backgroundColor:
                                    floatingEnabled ? accent : pillBgColor,
                                borderColor: floatingEnabled
                                    ? accent
                                    : pillBorderColor,
                                onTap: () =>
                                    store.bridge.setFloatingLyricEnabled(
                                  !floatingEnabled,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBackground({
    required AppStore store,
    required bool isAppleBlur,
    required Color accent,
    required String? coverPath,
  }) {
    if (!isAppleBlur) {
      final base = Color.lerp(const Color(0xFFF3F6FB), accent, 0.14)!;
      return DecoratedBox(
        decoration: BoxDecoration(
          color: base,
          gradient: RadialGradient(
            center: const Alignment(0.0, -0.35),
            radius: 1.15,
            colors: [
              accent.withValues(alpha: 0.22),
              base,
            ],
          ),
        ),
      );
    }

    final hasCover =
        coverPath != null && coverPath.isNotEmpty && File(coverPath).existsSync();

    if (hasCover) {
      return Stack(
        fit: StackFit.expand,
        children: [
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 46, sigmaY: 46),
            child: Image.file(
              File(coverPath),
              fit: BoxFit.cover,
              errorBuilder: (ctx, err, st) => const SizedBox.shrink(),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.45),
                  accent.withValues(alpha: 0.24),
                  Colors.black.withValues(alpha: 0.68),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        StarSkinBackground(accentColor: accent, skin: store.skin),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.0, -0.25),
              radius: 1.1,
              colors: [
                accent.withValues(alpha: 0.34),
                Colors.black.withValues(alpha: 0.56),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

enum _LyricMenuAction {
  importLyric,
  islandSettings,
}

class _StyleTogglePill extends StatelessWidget {
  const _StyleTogglePill({
    required this.isAppleBlur,
    required this.textColor,
    required this.backgroundColor,
    required this.borderColor,
    required this.onTap,
  });

  final bool isAppleBlur;
  final Color textColor;
  final Color backgroundColor;
  final Color borderColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: borderColor),
        ),
        child: Text(
          isAppleBlur ? 'Apple模糊' : '星澜纯净',
          style: TextStyle(
            color: textColor,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _ControlPill extends StatelessWidget {
  const _ControlPill({
    required this.label,
    required this.textColor,
    required this.backgroundColor,
    required this.borderColor,
    required this.onTap,
    this.isActive = false,
    this.accentColor,
  });

  final String label;
  final Color textColor;
  final Color backgroundColor;
  final Color borderColor;
  final VoidCallback onTap;
  final bool isActive;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: isActive ? (accentColor ?? backgroundColor) : backgroundColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: borderColor),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: textColor,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
