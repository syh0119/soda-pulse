import 'package:flutter/material.dart';
import 'package:soda_pulse/core/app_store.dart';
import 'package:soda_pulse/models/track.dart';
import 'package:soda_pulse/services/online_music_catalog.dart';
import 'package:soda_pulse/ui/theme/soda_theme.dart';

class OnlinePlaylistDetailPage extends StatefulWidget {
  const OnlinePlaylistDetailPage({
    super.key,
    required this.store,
    required this.playlistId,
    required this.title,
    required this.subtitle,
    required this.onOpenPlayer,
  });

  final AppStore store;
  final String playlistId;
  final String title;
  final String subtitle;
  final VoidCallback onOpenPlayer;

  @override
  State<OnlinePlaylistDetailPage> createState() =>
      _OnlinePlaylistDetailPageState();
}

class _OnlinePlaylistDetailPageState extends State<OnlinePlaylistDetailPage> {
  static const Color _bgObsidian = Color(0xFF0A0D0E);
  static const Color _cardSurface = Color(0xFF13181A);

  OnlinePlaylistDetail? _detail;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadChart();
  }

  Future<void> _loadChart() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final detail = await widget.store.fetchOnlineChart(widget.playlistId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '加载歌单失败：$e';
        _isLoading = false;
      });
    }
  }

  Future<void> _saveToLocalPlaylist(List<Track> tracks) async {
    if (_isSaving || tracks.isEmpty) return;
    setState(() => _isSaving = true);

    try {
      final playlistId = await widget.store.createPlaylist(widget.title);
      for (final track in tracks) {
        await widget.store.addTrackToPlaylist(playlistId, track);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已收藏到歌单「${widget.title}」（共 ${tracks.length} 首）'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('收藏失败：$e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  String _formatDuration(int ms) {
    final duration = Duration(milliseconds: ms);
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _buildHeaderCover(OnlinePlaylistDetail detail, List<Track> tracks) {
    const double size = 96;
    if (tracks.isNotEmpty) {
      return CoverArtWidget(
        track: tracks.first,
        localPath: widget.store.coverPathFor(tracks.first),
        accentColor: SodaTheme.accent,
        size: size,
      );
    }

    final coverUrl = detail.coverUrl;
    final resolvedCoverUrl = coverUrl.isNotEmpty
        ? CoverArtWidget.resolveNetworkUrl(coverUrl, size: size)
        : '';
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: size,
        height: size,
        color: const Color(0xFF1A2124),
        child: resolvedCoverUrl.isNotEmpty
            ? Image.network(
                resolvedCoverUrl,
                headers: CoverArtWidget.networkHeadersFor(resolvedCoverUrl),
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.queue_music_rounded,
                  color: Colors.white54,
                  size: 36,
                ),
              )
            : const Icon(
                Icons.queue_music_rounded,
                color: Colors.white54,
                size: 36,
              ),
      ),
    );
  }

  Widget _buildHeaderCard(OnlinePlaylistDetail detail, List<Track> tracks) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderCover(detail, tracks),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.68),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${tracks.length} 首',
                      style: const TextStyle(
                        color: SodaTheme.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: tracks.isEmpty
                      ? null
                      : () {
                          widget.store.playQueue(tracks, initialIndex: 0);
                          widget.onOpenPlayer();
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: SodaTheme.accent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text(
                    '播放全部',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: tracks.isEmpty || _isSaving
                      ? null
                      : () => _saveToLocalPlaylist(tracks),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.24)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.playlist_add_rounded),
                  label: const Text(
                    '收藏到歌单',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTrackTile(List<Track> tracks, int index) {
    final track = tracks[index];
    return InkWell(
      onTap: () {
        widget.store.playQueue(tracks, initialIndex: index);
        widget.onOpenPlayer();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '${index + 1}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CoverArtWidget(
                track: track,
                localPath: widget.store.coverPathFor(track),
                accentColor: SodaTheme.accent,
                size: 44,
                borderRadius: 8,
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
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${track.artist} · ${track.album}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              _formatDuration(track.durationMs),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 12,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: SodaTheme.accent),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loadChart,
                style: FilledButton.styleFrom(
                  backgroundColor: SodaTheme.accent,
                  foregroundColor: Colors.black,
                ),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    final detail = _detail!;
    final tracks = detail.tracks;

    return Column(
      children: [
        _buildHeaderCard(detail, tracks),
        Expanded(
          child: tracks.isEmpty
              ? Center(
                  child: Text(
                    '暂无歌曲',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 14,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: tracks.length,
                  itemBuilder: (context, index) => _buildTrackTile(tracks, index),
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgObsidian,
      appBar: AppBar(
        backgroundColor: _bgObsidian,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: const BackButton(color: Colors.white),
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _buildBody(),
    );
  }
}
