import 'package:flutter/material.dart';
import 'package:soda_pulse/core/app_store.dart';
import 'package:soda_pulse/ui/pages/island_settings_page.dart';
import 'package:soda_pulse/ui/widgets/karaoke_lyric_view.dart';
import 'package:soda_pulse/ui/widgets/star_skin_bg.dart';

class FullLyricsPage extends StatefulWidget {
  const FullLyricsPage({
    super.key,
    required this.store,
  });

  final AppStore store;

  @override
  State<FullLyricsPage> createState() => _FullLyricsPageState();
}

class _FullLyricsPageState extends State<FullLyricsPage> {
  Future<void> _importExternalLyric() async {
    await widget.store.importExternalLyricForCurrentTrack();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已尝试为当前歌曲导入外部歌词'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    setState(() {});
  }

  void _openIslandSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => IslandSettingsPage(bridge: widget.store.bridge),
      ),
    );
  }

  void _adjustOffset(int deltaMs) {
    final nextOffset = widget.store.bridge.lyricOffsetMs + deltaMs;
    widget.store.bridge.setLyricOffset(nextOffset);
    setState(() {});
  }

  void _resetOffset() {
    widget.store.bridge.setLyricOffset(0);
    setState(() {});
  }

  void _toggleFloatingLyric() {
    final enabled = widget.store.bridge.floatingLyricEnabled;
    widget.store.bridge.setFloatingLyricEnabled(!enabled);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final store = widget.store;
        final track = store.currentTrack;
        final accent = Theme.of(context).colorScheme.primary;
        final offsetMs = store.bridge.lyricOffsetMs;
        final floatingEnabled = store.bridge.floatingLyricEnabled;

        return Scaffold(
          backgroundColor: Colors.black,
          body: StarSkinBackground(
            accentColor: accent,
            skin: store.skin,
            child: SafeArea(
              child: Column(
                children: [
                  _buildTopBar(
                    title: track?.title ?? '未知歌曲',
                    artist: track?.artist ?? '未知歌手',
                    accent: accent,
                  ),
                  Expanded(
                    child: KaraokeLyricView(
                      lyrics: store.currentLyrics,
                      positionProvider: () => store.positionMs,
                      offsetMs: offsetMs,
                      accentColor: accent,
                      onSeekToMs: store.seekTo,
                    ),
                  ),
                  _buildBottomBar(
                    accent: accent,
                    offsetMs: offsetMs,
                    isPlaying: store.isPlaying,
                    floatingEnabled: floatingEnabled,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopBar({
    required String title,
    required String artist,
    required Color accent,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Colors.white,
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
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.68),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _TopActionPill(
            label: '导入歌词',
            icon: Icons.subtitles_outlined,
            accent: accent,
            onTap: _importExternalLyric,
          ),
          const SizedBox(width: 8),
          _TopActionPill(
            label: '灵动岛',
            icon: Icons.dynamic_feed_rounded,
            accent: accent,
            onTap: _openIslandSettings,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar({
    required Color accent,
    required int offsetMs,
    required bool isPlaying,
    required bool floatingEnabled,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.0),
            Colors.black.withValues(alpha: 0.45),
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _OffsetPill(
                label: '-50ms',
                selected: false,
                accent: accent,
                onTap: () => _adjustOffset(-50),
              ),
              const SizedBox(width: 10),
              _OffsetPill(
                label: offsetMs == 0 ? '0ms' : '0ms (${offsetMs > 0 ? '+' : ''}${offsetMs}ms)',
                selected: offsetMs == 0,
                accent: accent,
                onTap: _resetOffset,
              ),
              const SizedBox(width: 10),
              _OffsetPill(
                label: '+50ms',
                selected: false,
                accent: accent,
                onTap: () => _adjustOffset(50),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(width: 96),
              GestureDetector(
                onTap: widget.store.togglePlayPause,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(alpha: 0.92),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
              SizedBox(
                width: 96,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: _toggleFloatingLyric,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: floatingEnabled
                            ? accent.withValues(alpha: 0.28)
                            : Colors.white.withValues(alpha: 0.1),
                        border: Border.all(
                          color: floatingEnabled
                              ? accent.withValues(alpha: 0.75)
                              : Colors.white.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Text(
                        '桌面歌词',
                        style: TextStyle(
                          color: floatingEnabled
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.78),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TopActionPill extends StatelessWidget {
  const _TopActionPill({
    required this.label,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: Colors.white.withValues(alpha: 0.1),
          border: Border.all(
            color: accent.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OffsetPill extends StatelessWidget {
  const _OffsetPill({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: selected
              ? accent.withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.08),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.7)
                : Colors.white.withValues(alpha: 0.16),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? Colors.white
                : Colors.white.withValues(alpha: 0.85),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
