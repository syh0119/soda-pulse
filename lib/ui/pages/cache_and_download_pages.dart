import 'package:flutter/material.dart';

import '../../core/app_store.dart';
import '../../models/track.dart';
import '../../services/media_storage_service.dart';
import '../theme/soda_theme.dart';

String _formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  if (unitIndex == 0) return '$bytes B';
  return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[unitIndex]}';
}

String _qualityBadge(String quality) {
  switch (quality.toLowerCase()) {
    case 'flac24bit':
      return 'HR';
    case 'flac':
      return 'SQ';
    case '320k':
      return 'HQ';
    case '128k':
    default:
      return 'PQ';
  }
}

Color _qualityColor(String quality) {
  switch (quality.toLowerCase()) {
    case 'flac24bit':
      return SodaColors.lime;
    case 'flac':
      return SodaColors.cyan;
    case '320k':
      return const Color(0xFF7B61FF);
    case '128k':
    default:
      return SodaColors.textSecondary;
  }
}

String _qualityLabel(String quality) {
  switch (quality.toLowerCase()) {
    case 'flac24bit':
      return 'Hi-Res 无损';
    case 'flac':
      return 'SQ 无损';
    case '320k':
      return 'HQ 高品';
    case '128k':
    default:
      return 'PQ 标准';
  }
}

class CacheManagePage extends StatefulWidget {
  const CacheManagePage({super.key, required this.store});

  final AppStore store;

  @override
  State<CacheManagePage> createState() => _CacheManagePageState();
}

class _CacheManagePageState extends State<CacheManagePage> {
  static const List<int> _cacheLimitOptionsMb = [200, 500, 1024, 2048, 4096];

  CacheStats? _stats;
  bool _loading = true;
  bool _clearingListen = false;
  bool _clearingCover = false;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    if (mounted) {
      setState(() => _loading = true);
    }
    try {
      final stats = await widget.store.computeCacheStats();
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  String _formatMbOption(int mb) {
    if (mb >= 1024) {
      final gb = mb ~/ 1024;
      return '$gb GB';
    }
    return '$mb MB';
  }

  Future<bool> _confirmClear({
    required String title,
    required String content,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SodaColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: SodaColors.border),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: SodaColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          content,
          style: const TextStyle(
            color: SodaColors.textSecondary,
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              '取消',
              style: TextStyle(color: SodaColors.textSecondary),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: SodaColors.cyan,
              foregroundColor: SodaColors.background,
            ),
            child: const Text(
              '确认清理',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _handleClearListenCache() async {
    if (_clearingListen) return;
    final confirmed = await _confirmClear(
      title: '清理边听边存缓存',
      content: '将删除已缓存的在线试听音频文件，不影响已下载的本地歌曲。',
    );
    if (!confirmed || !mounted) return;

    setState(() => _clearingListen = true);
    try {
      await widget.store.clearListenCache();
      await _loadStats();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已清理边听边存缓存')),
      );
    } finally {
      if (mounted) {
        setState(() => _clearingListen = false);
      }
    }
  }

  Future<void> _handleClearCoverCache() async {
    if (_clearingCover) return;
    final confirmed = await _confirmClear(
      title: '清理封面缓存',
      content: '将清空磁盘封面缓存与内存图片缓存，后续浏览时将按需重新加载。',
    );
    if (!confirmed || !mounted) return;

    setState(() => _clearingCover = true);
    try {
      await widget.store.clearCoverCache();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      await _loadStats();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已清理封面与图片缓存')),
      );
    } finally {
      if (mounted) {
        setState(() => _clearingCover = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final imageCache = PaintingBinding.instance.imageCache;
        final memBytes = imageCache.currentSizeBytes;
        final memCount = imageCache.currentSize;
        final stats = _stats;
        final totalDiskBytes = (stats?.listenCacheBytes ?? 0) +
            (stats?.coverCacheBytes ?? 0) +
            (stats?.downloadBytes ?? 0);

        return Scaffold(
          backgroundColor: SodaColors.background,
          appBar: AppBar(
            backgroundColor: SodaColors.background,
            elevation: 0,
            title: const Text(
              '缓存与存储管理',
              style: TextStyle(
                color: SodaColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            actions: [
              IconButton(
                tooltip: '刷新统计',
                onPressed: _loading ? null : _loadStats,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          body: RefreshIndicator(
            color: SodaColors.cyan,
            backgroundColor: SodaColors.surface,
            onRefresh: _loadStats,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _buildOverviewCard(
                  totalDiskBytes: totalDiskBytes,
                  stats: stats,
                  memBytes: memBytes,
                  memCount: memCount,
                ),
                const SizedBox(height: 16),
                _buildListenCacheSettingsCard(),
                const SizedBox(height: 16),
                _buildCleanupActionsCard(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOverviewCard({
    required int totalDiskBytes,
    required CacheStats? stats,
    required int memBytes,
    required int memCount,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            SodaColors.cyan.withValues(alpha: 0.14),
            SodaColors.lime.withValues(alpha: 0.08),
            SodaColors.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: SodaColors.cyan.withValues(alpha: 0.28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: SodaColors.cyan.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.storage_rounded,
                  color: SodaColors.cyan,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '存储空间总览',
                      style: TextStyle(
                        color: SodaColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _loading
                          ? '正在统计媒体存储...'
                          : '本地占用 ${_formatBytes(totalDiskBytes)}',
                      style: const TextStyle(
                        color: SodaColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (_loading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: SodaColors.cyan,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          _StorageStatRow(
            icon: Icons.headphones_rounded,
            accent: SodaColors.cyan,
            label: '边听边存音频缓存',
            value: _formatBytes(stats?.listenCacheBytes ?? 0),
            subtitle: '${stats?.listenCacheCount ?? 0} 个音频切片/文件',
          ),
          const Divider(height: 20, color: SodaColors.border),
          _StorageStatRow(
            icon: Icons.image_rounded,
            accent: SodaColors.lime,
            label: '封面图片缓存',
            value: _formatBytes(stats?.coverCacheBytes ?? 0),
            subtitle:
                '磁盘 ${_formatBytes(stats?.coverCacheBytes ?? 0)} · 内存 ${_formatBytes(memBytes)} ($memCount 张)',
          ),
          const Divider(height: 20, color: SodaColors.border),
          _StorageStatRow(
            icon: Icons.download_done_rounded,
            accent: const Color(0xFF7B61FF),
            label: '已下载离线歌曲',
            value: _formatBytes(stats?.downloadBytes ?? 0),
            subtitle: '${stats?.downloadCount ?? 0} 首离线曲目',
          ),
        ],
      ),
    );
  }

  Widget _buildListenCacheSettingsCard() {
    final enabled = widget.store.listenCacheEnabled;
    final currentMaxMb = widget.store.listenCacheMaxMb;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: SodaColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SodaColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      '边听边存',
                      style: TextStyle(
                        color: SodaColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '在线播放时自动缓存音频，再次播放节省流量',
                      style: TextStyle(
                        color: SodaColors.textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: enabled,
                activeThumbColor: SodaColors.background,
                activeTrackColor: SodaColors.cyan,
                onChanged: (value) {
                  widget.store.setListenCacheEnabled(value);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '音频缓存上限',
                style: TextStyle(
                  color: SodaColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: SodaColors.cyan.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: SodaColors.cyan.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  _formatMbOption(currentMaxMb),
                  style: const TextStyle(
                    color: SodaColors.cyan,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _cacheLimitOptionsMb.map((mb) {
              final selected = currentMaxMb == mb;
              return ChoiceChip(
                label: Text(_formatMbOption(mb)),
                selected: selected,
                onSelected: enabled
                    ? (_) {
                        widget.store.setListenCacheMaxMb(mb);
                      }
                    : null,
                selectedColor: SodaColors.cyan.withValues(alpha: 0.22),
                backgroundColor: SodaColors.background,
                disabledColor: SodaColors.background.withValues(alpha: 0.5),
                side: BorderSide(
                  color: selected ? SodaColors.cyan : SodaColors.border,
                ),
                labelStyle: TextStyle(
                  color: selected
                      ? SodaColors.cyan
                      : enabled
                          ? SodaColors.textSecondary
                          : SodaColors.textSecondary.withValues(alpha: 0.45),
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 12.5,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCleanupActionsCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: SodaColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SodaColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '清理缓存',
            style: TextStyle(
              color: SodaColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '清理缓存不会删除你的歌单、收藏或已下载的离线音乐。',
            style: TextStyle(
              color: SodaColors.textSecondary,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _clearingListen ? null : _handleClearListenCache,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: SodaColors.cyan,
                    side: BorderSide(
                      color: SodaColors.cyan.withValues(alpha: 0.45),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: _clearingListen
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: SodaColors.cyan,
                          ),
                        )
                      : const Icon(Icons.cleaning_services_rounded, size: 18),
                  label: const Text(
                    '清理听歌缓存',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _clearingCover ? null : _handleClearCoverCache,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: SodaColors.lime,
                    side: BorderSide(
                      color: SodaColors.lime.withValues(alpha: 0.45),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: _clearingCover
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: SodaColors.lime,
                          ),
                        )
                      : const Icon(Icons.broken_image_outlined, size: 18),
                  label: const Text(
                    '清理封面缓存',
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
}

class _StorageStatRow extends StatelessWidget {
  const _StorageStatRow({
    required this.icon,
    required this.accent,
    required this.label,
    required this.value,
    required this.subtitle,
  });

  final IconData icon;
  final Color accent;
  final String label;
  final String value;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: accent, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: SodaColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: SodaColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: accent,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

enum _DownloadFilter { all, active, completed }

class DownloadManagePage extends StatefulWidget {
  const DownloadManagePage({super.key, required this.store});

  final AppStore store;

  @override
  State<DownloadManagePage> createState() => _DownloadManagePageState();
}

class _DownloadManagePageState extends State<DownloadManagePage> {
  _DownloadFilter _filter = _DownloadFilter.all;

  List<DownloadTask> _filteredTasks(List<DownloadTask> tasks) {
    switch (_filter) {
      case _DownloadFilter.all:
        return tasks;
      case _DownloadFilter.active:
        return tasks
            .where((t) => t.status != DownloadStatus.completed)
            .toList();
      case _DownloadFilter.completed:
        return tasks
            .where((t) => t.status == DownloadStatus.completed)
            .toList();
    }
  }

  Future<void> _confirmClearCompleted(int completedCount) async {
    if (completedCount == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SodaColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: SodaColors.border),
        ),
        title: const Text(
          '清空已完成记录',
          style: TextStyle(
            color: SodaColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          '确定要清除 $completedCount 条已完成的下载记录吗？',
          style: const TextStyle(color: SodaColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              '取消',
              style: TextStyle(color: SodaColors.textSecondary),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: SodaColors.cyan,
              foregroundColor: SodaColors.background,
            ),
            child: const Text(
              '清空',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await widget.store.clearCompletedDownloads();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final allTasks = widget.store.downloadTasks;
        final filtered = _filteredTasks(allTasks);
        final activeCount = allTasks
            .where((t) => t.status != DownloadStatus.completed)
            .length;
        final completedCount = allTasks.length - activeCount;

        return Scaffold(
          backgroundColor: SodaColors.background,
          appBar: AppBar(
            backgroundColor: SodaColors.background,
            elevation: 0,
            title: const Text(
              '下载管理',
              style: TextStyle(
                color: SodaColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: completedCount > 0
                    ? () => _confirmClearCompleted(completedCount)
                    : null,
                icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                label: const Text('清空已完成'),
                style: TextButton.styleFrom(
                  foregroundColor: SodaColors.cyan,
                  disabledForegroundColor:
                      SodaColors.textSecondary.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                child: _buildFilterBar(
                  allCount: allTasks.length,
                  activeCount: activeCount,
                  completedCount: completedCount,
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? _buildEmptyState()
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final task = filtered[index];
                          return _DownloadTaskTile(
                            task: task,
                            onTap: task.status == DownloadStatus.completed
                                ? () => widget.store.playDownloadedTask(task)
                                : null,
                            onRetry: () => widget.store.retryDownload(task.id),
                            onCancel: () =>
                                widget.store.cancelDownload(task.id),
                            onDelete: () =>
                                widget.store.deleteDownload(task.id),
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

  Widget _buildFilterBar({
    required int allCount,
    required int activeCount,
    required int completedCount,
  }) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: SodaColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SodaColors.border),
      ),
      child: Row(
        children: [
          _FilterSegment(
            label: '全部 ($allCount)',
            selected: _filter == _DownloadFilter.all,
            onTap: () => setState(() => _filter = _DownloadFilter.all),
          ),
          _FilterSegment(
            label: '进行中 ($activeCount)',
            selected: _filter == _DownloadFilter.active,
            onTap: () => setState(() => _filter = _DownloadFilter.active),
          ),
          _FilterSegment(
            label: '已完成 ($completedCount)',
            selected: _filter == _DownloadFilter.completed,
            onTap: () => setState(() => _filter = _DownloadFilter.completed),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    String message;
    switch (_filter) {
      case _DownloadFilter.all:
        message = '暂无下载任务';
        break;
      case _DownloadFilter.active:
        message = '没有进行中的下载';
        break;
      case _DownloadFilter.completed:
        message = '还没有已完成的离线歌曲';
        break;
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: SodaColors.cyan.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.download_for_offline_outlined,
              color: SodaColors.cyan,
              size: 30,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: const TextStyle(
              color: SodaColors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterSegment extends StatelessWidget {
  const _FilterSegment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? SodaColors.cyan.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: selected
                ? Border.all(color: SodaColors.cyan.withValues(alpha: 0.45))
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? SodaColors.cyan : SodaColors.textSecondary,
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _DownloadTaskTile extends StatelessWidget {
  const _DownloadTaskTile({
    required this.task,
    required this.onTap,
    required this.onRetry,
    required this.onCancel,
    required this.onDelete,
  });

  final DownloadTask task;
  final VoidCallback? onTap;
  final VoidCallback onRetry;
  final VoidCallback onCancel;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final badge = _qualityBadge(task.quality);
    final badgeColor = _qualityColor(task.quality);
    final isDownloading = task.status == DownloadStatus.downloading;
    final isQueued = task.status == DownloadStatus.queued;
    final isCompleted = task.status == DownloadStatus.completed;
    final isFailed = task.status == DownloadStatus.failed;
    final isCanceled = task.status == DownloadStatus.canceled;

    final progress = task.progress.clamp(0.0, 1.0);
    final percentText = '${(progress * 100).toStringAsFixed(0)}%';

    return Material(
      color: SodaColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isCompleted
                  ? SodaColors.cyan.withValues(alpha: 0.22)
                  : SodaColors.border,
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  CoverArtWidget(
                    track: Track(
                      id: task.trackId,
                      title: task.title,
                      artist: task.artist,
                      album: task.album,
                      durationMs: 0,
                      uri: '',
                      albumArtUri: task.coverUrl,
                    ),
                    accentColor: SodaColors.cyan,
                    size: 48,
                    borderRadius: 10,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                task.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: SodaColors.textPrimary,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            _QualityBadgeChip(
                              badge: badge,
                              color: badgeColor,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                task.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: SodaColors.textSecondary,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildStatusText(
                              isDownloading: isDownloading,
                              isQueued: isQueued,
                              isCompleted: isCompleted,
                              isFailed: isFailed,
                              isCanceled: isCanceled,
                              percentText: percentText,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  _buildActionButtons(
                    isDownloading: isDownloading,
                    isQueued: isQueued,
                    isCompleted: isCompleted,
                    isFailed: isFailed,
                    isCanceled: isCanceled,
                  ),
                ],
              ),
              if (isDownloading || isQueued) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: isQueued && progress == 0 ? null : progress,
                    minHeight: 4,
                    backgroundColor: SodaColors.background,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      SodaColors.cyan,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      task.totalBytes > 0
                          ? '${_formatBytes(task.receivedBytes)} / ${_formatBytes(task.totalBytes)}'
                          : _formatBytes(task.receivedBytes),
                      style: const TextStyle(
                        color: SodaColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      percentText,
                      style: const TextStyle(
                        color: SodaColors.cyan,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusText({
    required bool isDownloading,
    required bool isQueued,
    required bool isCompleted,
    required bool isFailed,
    required bool isCanceled,
    required String percentText,
  }) {
    if (isCompleted) {
      return Text(
        task.totalBytes > 0 ? '离线可播 · ${_formatBytes(task.totalBytes)}' : '已完成',
        style: const TextStyle(
          color: SodaColors.lime,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    if (isDownloading) {
      return Text(
        '下载中 $percentText',
        style: const TextStyle(
          color: SodaColors.cyan,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    if (isQueued) {
      return const Text(
        '等待中',
        style: TextStyle(
          color: SodaColors.textSecondary,
          fontSize: 11.5,
        ),
      );
    }
    if (isFailed) {
      return const Text(
        '下载失败',
        style: TextStyle(
          color: Color(0xFFFF5C7A),
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    if (isCanceled) {
      return const Text(
        '已取消',
        style: TextStyle(
          color: SodaColors.textSecondary,
          fontSize: 11.5,
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildActionButtons({
    required bool isDownloading,
    required bool isQueued,
    required bool isCompleted,
    required bool isFailed,
    required bool isCanceled,
  }) {
    if (isDownloading || isQueued) {
      return IconButton(
        tooltip: '取消下载',
        onPressed: onCancel,
        icon: const Icon(
          Icons.close_rounded,
          color: SodaColors.textSecondary,
          size: 20,
        ),
      );
    }
    if (isFailed || isCanceled) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '重试',
            onPressed: onRetry,
            icon: const Icon(
              Icons.refresh_rounded,
              color: SodaColors.cyan,
              size: 20,
            ),
          ),
          IconButton(
            tooltip: '删除记录',
            onPressed: onDelete,
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: SodaColors.textSecondary,
              size: 20,
            ),
          ),
        ],
      );
    }
    if (isCompleted) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '离线播放',
            onPressed: onTap,
            icon: const Icon(
              Icons.play_circle_fill_rounded,
              color: SodaColors.lime,
              size: 24,
            ),
          ),
          IconButton(
            tooltip: '删除离线文件',
            onPressed: onDelete,
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: SodaColors.textSecondary,
              size: 20,
            ),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }
}

class _QualityBadgeChip extends StatelessWidget {
  const _QualityBadgeChip({
    required this.badge,
    required this.color,
  });

  final String badge;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        badge,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

Future<void> showBatchDownloadSheet(
  BuildContext context,
  AppStore store,
  List<Track> tracks, {
  String title = '批量下载',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _BatchDownloadSheet(
      store: store,
      tracks: tracks,
      title: title,
    ),
  );
}

class _BatchDownloadSheet extends StatefulWidget {
  const _BatchDownloadSheet({
    required this.store,
    required this.tracks,
    required this.title,
  });

  final AppStore store;
  final List<Track> tracks;
  final String title;

  @override
  State<_BatchDownloadSheet> createState() => _BatchDownloadSheetState();
}

class _BatchDownloadSheetState extends State<_BatchDownloadSheet> {
  static const List<String> _qualities = ['128k', '320k', 'flac', 'flac24bit'];

  late String _selectedQuality;
  late Set<String> _selectedIds;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _selectedQuality = AudioQualityOptions.byId(widget.store.audioQuality).id;
    _selectedIds = widget.tracks.map((t) => t.id).toSet();
  }

  void _selectAll() {
    setState(() {
      _selectedIds = widget.tracks.map((t) => t.id).toSet();
    });
  }

  void _invertSelection() {
    setState(() {
      final next = <String>{};
      for (final track in widget.tracks) {
        if (!_selectedIds.contains(track.id)) {
          next.add(track.id);
        }
      }
      _selectedIds = next;
    });
  }

  Future<void> _startBatchDownload() async {
    final selectedTracks =
        widget.tracks.where((t) => _selectedIds.contains(t.id)).toList();
    if (selectedTracks.isEmpty || _submitting) return;

    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.store.batchDownloadTracks(selectedTracks, _selectedQuality);
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '已加入 ${selectedTracks.length} 首曲目至下载队列 (${_qualityBadge(_selectedQuality)})',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      messenger.showSnackBar(
        SnackBar(content: Text('批量下载启动失败: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.82;
    final selectedCount = _selectedIds.length;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: SodaColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: SodaColors.border),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: SodaColors.textSecondary.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 14, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            color: SodaColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '已选 $selectedCount / ${widget.tracks.length} 首',
                          style: const TextStyle(
                            color: SodaColors.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _selectAll,
                    child: const Text(
                      '全选',
                      style: TextStyle(
                        color: SodaColors.cyan,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _invertSelection,
                    child: const Text(
                      '反选',
                      style: TextStyle(
                        color: SodaColors.lime,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '下载音质',
                    style: TextStyle(
                      color: SodaColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _qualities.map((q) {
                      final selected = _selectedQuality == q;
                      final color = _qualityColor(q);
                      return ChoiceChip(
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _qualityBadge(q),
                              style: TextStyle(
                                color: selected ? color : SodaColors.textSecondary,
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(_qualityLabel(q)),
                          ],
                        ),
                        selected: selected,
                        onSelected: (_) =>
                            setState(() => _selectedQuality = q),
                        selectedColor: color.withValues(alpha: 0.18),
                        backgroundColor: SodaColors.background,
                        side: BorderSide(
                          color: selected ? color : SodaColors.border,
                        ),
                        labelStyle: TextStyle(
                          color: selected
                              ? SodaColors.textPrimary
                              : SodaColors.textSecondary,
                          fontSize: 12.5,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w500,
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: SodaColors.border),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: widget.tracks.length,
                itemBuilder: (context, index) {
                  final track = widget.tracks[index];
                  final checked = _selectedIds.contains(track.id);
                  return CheckboxListTile(
                    value: checked,
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _selectedIds.add(track.id);
                        } else {
                          _selectedIds.remove(track.id);
                        }
                      });
                    },
                    activeColor: SodaColors.cyan,
                    checkColor: SodaColors.background,
                    controlAffinity: ListTileControlAffinity.leading,
                    secondary: CoverArtWidget(
                      track: track,
                      accentColor: SodaColors.cyan,
                      size: 40,
                      borderRadius: 8,
                    ),
                    title: Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: SodaColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: SodaColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed:
                      selectedCount > 0 && !_submitting ? _startBatchDownload : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: SodaColors.cyan,
                    foregroundColor: SodaColors.background,
                    disabledBackgroundColor:
                        SodaColors.border.withValues(alpha: 0.6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: SodaColors.background,
                          ),
                        )
                      : const Icon(Icons.download_rounded),
                  label: Text(
                    selectedCount > 0
                        ? '开始下载 ($selectedCount 首 · ${_qualityBadge(_selectedQuality)})'
                        : '请选择要下载的曲目',
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
