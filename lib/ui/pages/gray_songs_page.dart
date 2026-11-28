import 'package:flutter/material.dart';

import '../../core/app_store.dart';
import '../../models/track.dart';
import '../../services/online_music_catalog.dart';
import '../theme/soda_theme.dart';

class GraySongsPage extends StatefulWidget {
  const GraySongsPage({super.key, required this.store});

  final AppStore store;

  @override
  State<GraySongsPage> createState() => _GraySongsPageState();
}

class _GraySongsPageState extends State<GraySongsPage> {
  bool _scanning = false;
  bool _autoFixing = false;
  int _scanChecked = 0;
  int _scanTotal = 0;
  final Set<String> _verifiedOkIds = <String>{};
  final Set<String> _replacingIds = <String>{};

  List<Track> _collectOnlineTracks() {
    final map = <String, Track>{};
    for (final t in widget.store.favorites) {
      if (t.isOnlinePluginTrack) {
        map[t.id] = t;
      }
    }
    for (final pl in widget.store.localPlaylists) {
      for (final id in pl.trackIds) {
        final t = widget.store.trackById(id);
        if (t != null && t.isOnlinePluginTrack) {
          map[t.id] = t;
        }
      }
    }
    return map.values.toList();
  }

  Future<void> _scanAll() async {
    if (_scanning) return;
    final tracks = _collectOnlineTracks();
    if (tracks.isEmpty) return;

    setState(() {
      _scanning = true;
      _scanChecked = 0;
      _scanTotal = tracks.length;
      _verifiedOkIds.clear();
    });

    try {
      for (final t in tracks) {
        if (!mounted) return;
        final ok = await widget.store.verifyTrackPlayable(t);
        if (ok) {
          _verifiedOkIds.add(t.id);
        }
        if (mounted) {
          setState(() => _scanChecked += 1);
        }
      }
      if (!mounted) return;
      final brokenCount = widget.store.failedTrackIds.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            brokenCount == 0
                ? '扫描完成：全部 ${tracks.length} 首在线歌曲均可用'
                : '扫描完成：发现 $brokenCount 首异常/灰歌，可点击一键换源',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _scanning = false);
      }
    }
  }

  Future<void> _autoFixFailed(List<Track> tracks) async {
    final failed = tracks
        .where((t) => widget.store.failedTrackIds.contains(t.id))
        .toList();
    if (failed.isEmpty || _autoFixing) return;

    setState(() => _autoFixing = true);
    var fixed = 0;
    try {
      final pluginId = widget.store.activePluginId;
      for (final oldTrack in failed) {
        if (!mounted) return;
        final results = await OnlineMusicCatalog.searchWyTracks(
          '${oldTrack.title} ${oldTrack.artist}',
          pluginId: pluginId,
          limit: 8,
        );
        for (final candidate in results) {
          if (candidate.id == oldTrack.id) continue;
          final ok = await widget.store.verifyTrackPlayable(candidate);
          if (ok) {
            await widget.store.replaceTrackEverywhere(oldTrack, candidate);
            _verifiedOkIds.add(candidate.id);
            fixed += 1;
            break;
          }
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('自动换源完成：成功修复 $fixed / ${failed.length} 首')),
      );
    } finally {
      if (mounted) {
        setState(() => _autoFixing = false);
      }
    }
  }

  Future<void> _openReplaceSheet(Track oldTrack) async {
    setState(() => _replacingIds.add(oldTrack.id));
    List<Track> candidates = const [];
    try {
      candidates = await OnlineMusicCatalog.searchWyTracks(
        '${oldTrack.title} ${oldTrack.artist}',
        pluginId: widget.store.activePluginId,
        limit: 15,
      );
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _replacingIds.remove(oldTrack.id));
      }
    }
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.72,
        ),
        decoration: const BoxDecoration(
          color: SodaColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '为「${oldTrack.title}」选择替代音源',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: SodaColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: SodaColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: SodaColors.border),
              Expanded(
                child: candidates.isEmpty
                    ? const Center(
                        child: Text(
                          '未搜索到可用替代结果',
                          style: TextStyle(color: SodaColors.textSecondary),
                        ),
                      )
                    : ListView.builder(
                        itemCount: candidates.length,
                        itemBuilder: (context, idx) {
                          final candidate = candidates[idx];
                          return ListTile(
                            leading: CoverArtWidget(
                              track: candidate,
                              accentColor: SodaColors.cyan,
                              size: 44,
                              borderRadius: 8,
                            ),
                            title: Text(
                              candidate.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: SodaColors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              '${candidate.artist} · ${candidate.album}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: SodaColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                            trailing: const Text(
                              '替换',
                              style: TextStyle(
                                color: SodaColors.cyan,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            onTap: () async {
                              await widget.store
                                  .replaceTrackEverywhere(oldTrack, candidate);
                              _verifiedOkIds.add(candidate.id);
                              if (ctx.mounted) Navigator.of(ctx).pop();
                              if (mounted) {
                                ScaffoldMessenger.of(this.context).showSnackBar(
                                  SnackBar(
                                    content: Text('已替换为「${candidate.title}」'),
                                  ),
                                );
                              }
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final tracks = _collectOnlineTracks();
        final failedIds = widget.store.failedTrackIds;
        final failedCount =
            tracks.where((t) => failedIds.contains(t.id)).length;

        return Scaffold(
          backgroundColor: SodaColors.background,
          appBar: AppBar(
            backgroundColor: SodaColors.background,
            elevation: 0,
            title: const Text(
              '灰歌扫描与一键换源',
              style: TextStyle(
                color: SodaColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          body: Column(
            children: [
              Container(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: SodaColors.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: SodaColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '收藏与自建歌单共 ${tracks.length} 首在线歌曲 · 异常 $failedCount 首',
                      style: const TextStyle(
                        color: SodaColors.textPrimary,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_scanning && _scanTotal > 0) ...[
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        value: _scanChecked / _scanTotal,
                        backgroundColor: SodaColors.background,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          SodaColors.cyan,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '正在检测可用性: $_scanChecked / $_scanTotal',
                        style: const TextStyle(
                          color: SodaColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed:
                                tracks.isEmpty || _scanning ? null : _scanAll,
                            style: FilledButton.styleFrom(
                              backgroundColor: SodaColors.cyan,
                              foregroundColor: SodaColors.background,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(Icons.radar_rounded, size: 18),
                            label: Text(_scanning ? '扫描中...' : '一键检测可用性'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: failedCount == 0 || _autoFixing
                                ? null
                                : () => _autoFixFailed(tracks),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: SodaColors.lime,
                              side: BorderSide(
                                color: SodaColors.lime.withValues(alpha: 0.45),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(Icons.auto_fix_high_rounded,
                                size: 18),
                            label: Text(_autoFixing ? '换源中...' : '一键自动换源'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: tracks.isEmpty
                    ? const Center(
                        child: Text(
                          '收藏或自建歌单中暂无在线歌曲',
                          style: TextStyle(color: SodaColors.textSecondary),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                        itemCount: tracks.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final track = tracks[index];
                          final isFailed = failedIds.contains(track.id);
                          final isOk = _verifiedOkIds.contains(track.id);
                          final isReplacing = _replacingIds.contains(track.id);

                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: SodaColors.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isFailed
                                    ? const Color(0xFFFF5C7A)
                                        .withValues(alpha: 0.45)
                                    : SodaColors.border,
                              ),
                            ),
                            child: Row(
                              children: [
                                CoverArtWidget(
                                  track: track,
                                  accentColor: SodaColors.cyan,
                                  size: 44,
                                  borderRadius: 8,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        track.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: isFailed
                                              ? const Color(0xFFFF8DA1)
                                              : SodaColors.textPrimary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${track.artist} · ${isFailed ? "解析异常/灰歌" : isOk ? "已验证可用" : "待检测"}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: isFailed
                                              ? const Color(0xFFFF5C7A)
                                              : isOk
                                                  ? SodaColors.lime
                                                  : SodaColors.textSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                TextButton(
                                  onPressed: isReplacing
                                      ? null
                                      : () => _openReplaceSheet(track),
                                  child: Text(
                                    isReplacing ? '搜索中' : '换源',
                                    style: const TextStyle(
                                      color: SodaColors.cyan,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
