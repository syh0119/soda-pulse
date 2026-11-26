import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:soda_pulse/services/native_bridge.dart';
import 'package:soda_pulse/models/track.dart';
import 'package:soda_pulse/ui/pages/player_page.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({
    super.key,
    required this.bridge,
    required this.queue,
    required this.currentTrack,
    required this.onSelectTrack,
    required this.onPlayDemo,
    required this.onRescan,
    required this.scanning,
  });

  final NativePlayerBridge bridge;
  final List<Track> queue;
  final Track? currentTrack;
  final ValueChanged<int> onSelectTrack;
  final VoidCallback onPlayDemo;
  final Future<void> Function() onRescan;
  final bool scanning;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<_IndexedTrack> get _filteredTracks {
    final q = _query.trim().toLowerCase();
    final result = <_IndexedTrack>[];
    for (var i = 0; i < widget.queue.length; i++) {
      final track = widget.queue[i];
      if (q.isEmpty ||
          track.title.toLowerCase().contains(q) ||
          track.artist.toLowerCase().contains(q)) {
        result.add(_IndexedTrack(index: i, track: track));
      }
    }
    return result;
  }

  String _formatDuration(int durationMs) {
    if (durationMs <= 0) return '00:00';
    final totalSeconds = durationMs ~/ 1000;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _openPlayerPage() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerPage(
          bridge: widget.bridge,
          track: widget.currentTrack,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final filtered = _filteredTracks;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildTopBar(colorScheme),
                _buildDemoBanner(colorScheme),
                Expanded(
                  child: _buildTrackList(filtered, colorScheme),
                ),
              ],
            ),
            if (widget.currentTrack != null)
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: _buildMiniPlayer(widget.currentTrack!, colorScheme),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: '搜索歌名或歌手...',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                isDense: true,
                filled: true,
                fillColor: const Color(0xFF162033),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          IconButton.filledTonal(
            onPressed: widget.scanning ? null : () => widget.onRescan(),
            tooltip: '重新扫描本地音乐',
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF162033),
              foregroundColor: colorScheme.primary,
              minimumSize: const Size(44, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: widget.scanning
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildDemoBanner(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onPlayDemo,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                colors: [Color(0xFF0EA5E9), Color(0xFF2563EB)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x4038BDF8),
                  blurRadius: 16,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0x33FFFFFF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '一键演示 (ColorOS 17 逐字/灵动岛实测)',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        '内置逐字歌词时间轴，立即验证灵动岛与悬浮窗同步',
                        style: TextStyle(
                          color: Color(0xFFE0F2FE),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.play_circle_filled_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrackList(
    List<_IndexedTrack> filtered,
    ColorScheme colorScheme,
  ) {
    if (widget.scanning && widget.queue.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text(
              '正在扫描本地音频...',
              style: TextStyle(color: Color(0xFF94A3B8)),
            ),
          ],
        ),
      );
    }

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.library_music_outlined,
              size: 48,
              color: Color(0xFF475569),
            ),
            const SizedBox(height: 12),
            Text(
              _query.isEmpty ? '暂无本地音频，点击右上角刷新扫描' : '未找到匹配的曲目',
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
            ),
          ],
        ),
      );
    }

    final bottomPadding = widget.currentTrack != null ? 92.0 : 16.0;

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(16, 4, 16, bottomPadding),
      itemCount: filtered.length,
      separatorBuilder: (context, index) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final item = filtered[index];
        final track = item.track;
        final isCurrent = widget.currentTrack?.id == track.id;

        return Material(
          color: isCurrent ? const Color(0xFF17253D) : const Color(0xFF111827),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              widget.onSelectTrack(item.index);
              _openPlayerPage();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isCurrent
                      ? colorScheme.primary
                      : const Color(0xFF1E293B),
                  width: isCurrent ? 1.2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? const Color(0x2E38BDF8)
                          : const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isCurrent
                          ? Icons.equalizer_rounded
                          : Icons.music_note_rounded,
                      color: isCurrent
                          ? colorScheme.primary
                          : const Color(0xFF94A3B8),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight:
                                isCurrent ? FontWeight.w700 : FontWeight.w500,
                            color: isCurrent
                                ? colorScheme.primary
                                : Colors.white,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          track.artist.isEmpty ? '未知歌手' : track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatDuration(track.durationMs),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: isCurrent
                          ? colorScheme.primary
                          : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMiniPlayer(Track track, ColorScheme colorScheme) {
    return StreamBuilder<PlaybackState>(
      stream: widget.bridge.stateStream,
      initialData: widget.bridge.currentState,
      builder: (context, snapshot) {
        final state = snapshot.data ?? const PlaybackSnapshot();
        final isPlaying = state.isPlaying;

        return Material(
          color: const Color(0xF0162033),
          elevation: 8,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: _openPlayerPage,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0x4D38BDF8)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0x2E38BDF8),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.graphic_eq_rounded,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          track.artist.isEmpty ? '未知歌手' : track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => widget.bridge.togglePlayPause(),
                    icon: Icon(
                      isPlaying
                          ? Icons.pause_circle_filled_rounded
                          : Icons.play_circle_filled_rounded,
                      size: 36,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _IndexedTrack {
  const _IndexedTrack({required this.index, required this.track});

  final int index;
  final Track track;
}
