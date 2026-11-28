import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

enum DownloadStatus {
  queued,
  downloading,
  completed,
  failed,
  canceled,
}

const Object _unset = Object();

class DownloadTask {
  const DownloadTask({
    required this.id,
    required this.trackId,
    required this.title,
    required this.artist,
    this.album = '',
    required this.quality,
    required this.url,
    required this.targetPath,
    this.lrcPath,
    this.coverUrl,
    required this.status,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.error,
    required this.createdAt,
    this.headers = const <String, String>{},
  });

  final String id;
  final String trackId;
  final String title;
  final String artist;
  final String album;
  final String quality;
  final String url;
  final String targetPath;
  final String? lrcPath;
  final String? coverUrl;
  final DownloadStatus status;
  final int receivedBytes;
  final int totalBytes;
  final String? error;
  final DateTime createdAt;
  final Map<String, String> headers;

  double get progress {
    if (totalBytes <= 0) {
      return status == DownloadStatus.completed ? 1.0 : 0.0;
    }
    return (receivedBytes / totalBytes).clamp(0.0, 1.0);
  }

  DownloadTask copyWith({
    String? id,
    String? trackId,
    String? title,
    String? artist,
    String? album,
    String? quality,
    String? url,
    String? targetPath,
    Object? lrcPath = _unset,
    Object? coverUrl = _unset,
    DownloadStatus? status,
    int? receivedBytes,
    int? totalBytes,
    Object? error = _unset,
    DateTime? createdAt,
    Map<String, String>? headers,
  }) {
    return DownloadTask(
      id: id ?? this.id,
      trackId: trackId ?? this.trackId,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      quality: quality ?? this.quality,
      url: url ?? this.url,
      targetPath: targetPath ?? this.targetPath,
      lrcPath: identical(lrcPath, _unset) ? this.lrcPath : lrcPath as String?,
      coverUrl:
          identical(coverUrl, _unset) ? this.coverUrl : coverUrl as String?,
      status: status ?? this.status,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      error: identical(error, _unset) ? this.error : error as String?,
      createdAt: createdAt ?? this.createdAt,
      headers: headers ?? this.headers,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'trackId': trackId,
      'title': title,
      'artist': artist,
      'album': album,
      'quality': quality,
      'url': url,
      'targetPath': targetPath,
      'lrcPath': lrcPath,
      'coverUrl': coverUrl,
      'status': status.name,
      'receivedBytes': receivedBytes,
      'totalBytes': totalBytes,
      'error': error,
      'createdAt': createdAt.toIso8601String(),
      'headers': headers,
    };
  }

  factory DownloadTask.fromMap(Map<String, dynamic> map) {
    final rawStatus = map['status'] as String?;
    final parsedStatus = DownloadStatus.values.firstWhere(
      (s) => s.name == rawStatus,
      orElse: () => DownloadStatus.failed,
    );

    final rawHeaders = map['headers'];
    final headers = <String, String>{};
    if (rawHeaders is Map) {
      for (final entry in rawHeaders.entries) {
        if (entry.key != null && entry.value != null) {
          headers[entry.key.toString()] = entry.value.toString();
        }
      }
    }

    final rawCreatedAt = map['createdAt'] as String?;
    final createdAt = (rawCreatedAt != null
            ? DateTime.tryParse(rawCreatedAt)
            : null) ??
        DateTime.fromMillisecondsSinceEpoch(0);

    return DownloadTask(
      id: (map['id'] ?? '').toString(),
      trackId: (map['trackId'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      artist: (map['artist'] ?? '').toString(),
      album: (map['album'] ?? '').toString(),
      quality: (map['quality'] ?? '').toString(),
      url: (map['url'] ?? '').toString(),
      targetPath: (map['targetPath'] ?? '').toString(),
      lrcPath: map['lrcPath'] as String?,
      coverUrl: map['coverUrl'] as String?,
      status: parsedStatus,
      receivedBytes: (map['receivedBytes'] as num?)?.toInt() ?? 0,
      totalBytes: (map['totalBytes'] as num?)?.toInt() ?? 0,
      error: map['error'] as String?,
      createdAt: createdAt,
      headers: Map<String, String>.unmodifiable(headers),
    );
  }
}

class CacheStats {
  const CacheStats({
    required this.listenCacheBytes,
    required this.listenCacheCount,
    required this.coverCacheBytes,
    required this.downloadBytes,
    required this.downloadCount,
    required this.listenCacheDir,
    required this.downloadDir,
  });

  final int listenCacheBytes;
  final int listenCacheCount;
  final int coverCacheBytes;
  final int downloadBytes;
  final int downloadCount;
  final String listenCacheDir;
  final String downloadDir;
}

class _ListenCacheEntry {
  _ListenCacheEntry({
    required this.key,
    required this.trackId,
    required this.quality,
    required this.fileName,
    required this.bytes,
    required this.lastAccessedMs,
    required this.createdAtMs,
  });

  final String key;
  final String trackId;
  final String quality;
  final String fileName;
  int bytes;
  int lastAccessedMs;
  final int createdAtMs;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'key': key,
        'trackId': trackId,
        'quality': quality,
        'fileName': fileName,
        'bytes': bytes,
        'lastAccessedMs': lastAccessedMs,
        'createdAtMs': createdAtMs,
      };

  factory _ListenCacheEntry.fromMap(Map<String, dynamic> map) {
    return _ListenCacheEntry(
      key: (map['key'] ?? '').toString(),
      trackId: (map['trackId'] ?? '').toString(),
      quality: (map['quality'] ?? '').toString(),
      fileName: (map['fileName'] ?? '').toString(),
      bytes: (map['bytes'] as num?)?.toInt() ?? 0,
      lastAccessedMs: (map['lastAccessedMs'] as num?)?.toInt() ?? 0,
      createdAtMs: (map['createdAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

class _ActiveDownloadHandle {
  _ActiveDownloadHandle(this.client);

  final HttpClient client;
  bool canceled = false;
}

class MediaStorageService extends ChangeNotifier {
  MediaStorageService();

  static final MediaStorageService instance = MediaStorageService();

  static const int _maxConcurrentDownloads = 2;
  static const Duration _progressThrottle = Duration(milliseconds: 200);
  static const String _defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
  static const List<String> _supportedExts = <String>[
    '.flac',
    '.mp3',
    '.m4a',
    '.ogg',
    '.aac',
    '.wav',
  ];

  bool _initialized = false;
  late String _baseDir;
  late String _listenCacheDir;
  late String _downloadDir;
  late String _downloadsIndexPath;
  late String _listenCacheIndexPath;

  final List<DownloadTask> _tasks = <DownloadTask>[];
  final Map<String, _ListenCacheEntry> _listenCacheIndex =
      <String, _ListenCacheEntry>{};
  final Map<String, Future<String?>> _inFlightCacheJobs =
      <String, Future<String?>>{};
  final Map<String, _ActiveDownloadHandle> _activeDownloads =
      <String, _ActiveDownloadHandle>{};
  final Map<String, String> _pendingLyrics = <String, String>{};

  Future<void> _downloadsWriteChain = Future<void>.value();
  Future<void> _listenCacheWriteChain = Future<void>.value();
  Timer? _listenCacheTouchTimer;
  int _taskSeq = 0;

  bool get isInitialized => _initialized;
  String get listenCacheDir => _listenCacheDir;
  String get downloadDir => _downloadDir;

  List<DownloadTask> get tasks => List<DownloadTask>.unmodifiable(_tasks);

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const int kb = 1024;
    const int mb = kb * 1024;
    const int gb = mb * 1024;
    if (bytes < kb) return '$bytes B';
    if (bytes < mb) return '${(bytes / kb).toStringAsFixed(1)} KB';
    if (bytes < gb) return '${(bytes / mb).toStringAsFixed(1)} MB';
    return '${(bytes / gb).toStringAsFixed(2)} GB';
  }

  static String sanitizeFileName(String name) {
    var sanitized = name
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    sanitized = sanitized.replaceAll(RegExp(r'^[.\s]+|[.\s]+$'), '');
    if (sanitized.isEmpty) {
      return 'untitled';
    }
    if (sanitized.length > 120) {
      sanitized = sanitized.substring(0, 120).trimRight();
    }
    return sanitized;
  }

  static String extFromUrlOrQuality(String url, String quality) {
    final uri = Uri.tryParse(url);
    final path = (uri?.path ?? url).toLowerCase();
    for (final ext in _supportedExts) {
      if (path.endsWith(ext)) {
        return ext;
      }
    }
    for (final ext in _supportedExts) {
      if (path.contains('$ext?') || path.contains('$ext&')) {
        return ext;
      }
    }

    final q = quality.toLowerCase().trim();
    if (q.contains('flac') ||
        q.contains('lossless') ||
        q.contains('hires') ||
        q.contains('hi-res') ||
        q == 'sq' ||
        q == 'hr' ||
        q == 'jymaster' ||
        q == 'sky') {
      return '.flac';
    }
    if (q.contains('m4a') || q.contains('alac')) return '.m4a';
    if (q.contains('aac')) return '.aac';
    if (q.contains('ogg') || q.contains('vorbis')) return '.ogg';
    if (q.contains('wav')) return '.wav';
    return '.mp3';
  }

  Future<void> init({
    required String baseDir,
    String? downloadDir,
  }) async {
    _baseDir = baseDir;
    _listenCacheDir = _joinPath(baseDir, 'listen_cache');
    _downloadDir = downloadDir ?? _joinPath(baseDir, 'downloads');
    _downloadsIndexPath = _joinPath(baseDir, 'downloads_index.json');
    _listenCacheIndexPath = _joinPath(baseDir, 'listen_cache_index.json');

    await Directory(_baseDir).create(recursive: true);
    await Directory(_listenCacheDir).create(recursive: true);
    await Directory(_downloadDir).create(recursive: true);

    await _loadDownloadsIndex();
    await _loadListenCacheIndex();

    _initialized = true;
    notifyListeners();
    _pumpQueue();
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError(
        'MediaStorageService must be initialized with init() before use.',
      );
    }
  }

  String _cacheKey(String trackId, String quality) =>
      sanitizeFileName('${trackId}_$quality');

  String? getCachedAudioPath(String trackId, String quality) {
    _ensureInitialized();
    final key = _cacheKey(trackId, quality);
    final entry = _listenCacheIndex[key];
    if (entry == null) {
      return null;
    }

    final path = _joinPath(_listenCacheDir, entry.fileName);
    final file = File(path);
    if (!file.existsSync()) {
      _listenCacheIndex.remove(key);
      _scheduleListenCacheIndexSave();
      return null;
    }

    final length = file.lengthSync();
    if (length <= 0) {
      return null;
    }

    entry.bytes = length;
    entry.lastAccessedMs = DateTime.now().millisecondsSinceEpoch;
    _scheduleListenCacheIndexSave();
    return path;
  }

  Future<String?> cacheAudioInBackground(
    String trackId,
    String quality,
    String url, {
    Map<String, String>? headers,
    int maxCacheMb = 500,
  }) async {
    _ensureInitialized();
    if (url.trim().isEmpty) return null;

    final existing = getCachedAudioPath(trackId, quality);
    if (existing != null) {
      return existing;
    }

    final key = _cacheKey(trackId, quality);
    final inFlight = _inFlightCacheJobs[key];
    if (inFlight != null) {
      return inFlight;
    }

    final future = _performBackgroundCache(
      key: key,
      trackId: trackId,
      quality: quality,
      url: url,
      headers: headers,
      maxCacheMb: maxCacheMb,
    );
    _inFlightCacheJobs[key] = future;

    try {
      return await future;
    } finally {
      _inFlightCacheJobs.remove(key);
    }
  }

  Future<String?> _performBackgroundCache({
    required String key,
    required String trackId,
    required String quality,
    required String url,
    Map<String, String>? headers,
    required int maxCacheMb,
  }) async {
    final ext = extFromUrlOrQuality(url, quality);
    final fileName = '$key$ext';
    final targetPath = _joinPath(_listenCacheDir, fileName);
    final partFile = File('$targetPath.part');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    IOSink? sink;

    try {
      final uri = Uri.parse(url);
      final request = await client.getUrl(uri);
      _applyRequestHeaders(request, uri, headers);

      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        return null;
      }

      if (await partFile.exists()) {
        await partFile.delete();
      }
      await partFile.parent.create(recursive: true);

      sink = partFile.openWrite();
      await for (final chunk in response) {
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
      sink = null;

      final size = await partFile.length();
      if (size <= 0) {
        await _deleteFileQuietly(partFile);
        return null;
      }

      final targetFile = File(targetPath);
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await partFile.rename(targetPath);

      final now = DateTime.now().millisecondsSinceEpoch;
      _listenCacheIndex[key] = _ListenCacheEntry(
        key: key,
        trackId: trackId,
        quality: quality,
        fileName: fileName,
        bytes: size,
        lastAccessedMs: now,
        createdAtMs: now,
      );

      await _evictListenCacheIfNeeded(maxCacheMb);
      await _saveListenCacheIndex();
      return targetPath;
    } catch (_) {
      await _closeSinkQuietly(sink);
      await _deleteFileQuietly(partFile);
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _evictListenCacheIfNeeded(int maxCacheMb) async {
    if (maxCacheMb <= 0) {
      await clearListenCache();
      return;
    }

    final maxBytes = maxCacheMb * 1024 * 1024;
    var totalBytes = 0;
    final entries = _listenCacheIndex.values.toList();
    for (final entry in entries) {
      totalBytes += entry.bytes;
    }

    if (totalBytes <= maxBytes) {
      return;
    }

    entries.sort((a, b) => a.lastAccessedMs.compareTo(b.lastAccessedMs));
    for (final entry in entries) {
      if (totalBytes <= maxBytes) break;
      final file = File(_joinPath(_listenCacheDir, entry.fileName));
      await _deleteFileQuietly(file);
      _listenCacheIndex.remove(entry.key);
      totalBytes -= entry.bytes;
    }
  }

  Future<void> clearListenCache() async {
    _ensureInitialized();
    _listenCacheTouchTimer?.cancel();
    _listenCacheIndex.clear();

    final dir = Directory(_listenCacheDir);
    if (await dir.exists()) {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File && !entity.path.endsWith('.part')) {
          await _deleteFileQuietly(entity);
        }
      }
    }

    await _saveListenCacheIndex();
    notifyListeners();
  }

  Future<CacheStats> computeStats() async {
    _ensureInitialized();

    var listenCacheBytes = 0;
    var listenCacheCount = 0;
    final listenDir = Directory(_listenCacheDir);
    if (await listenDir.exists()) {
      await for (final entity in listenDir.list(followLinks: false)) {
        if (entity is File && !entity.path.endsWith('.part')) {
          listenCacheBytes += await entity.length();
          listenCacheCount++;
        }
      }
    }

    var coverCacheBytes = 0;
    final coverDir = Directory(_joinPath(_baseDir, 'cover_cache'));
    if (await coverDir.exists()) {
      await for (final entity in coverDir.list(followLinks: false)) {
        if (entity is File) {
          coverCacheBytes += await entity.length();
        }
      }
    }

    var downloadBytes = 0;
    var downloadCount = 0;
    final dlDir = Directory(_downloadDir);
    if (await dlDir.exists()) {
      await for (final entity in dlDir.list(followLinks: false)) {
        if (entity is File && !entity.path.endsWith('.part')) {
          downloadBytes += await entity.length();
          if (!entity.path.toLowerCase().endsWith('.lrc')) {
            downloadCount++;
          }
        }
      }
    }

    return CacheStats(
      listenCacheBytes: listenCacheBytes,
      listenCacheCount: listenCacheCount,
      coverCacheBytes: coverCacheBytes,
      downloadBytes: downloadBytes,
      downloadCount: downloadCount,
      listenCacheDir: _listenCacheDir,
      downloadDir: _downloadDir,
    );
  }

  String? getDownloadedAudioPath(String trackId) {
    _ensureInitialized();
    for (final task in _tasks) {
      if (task.trackId == trackId && task.status == DownloadStatus.completed) {
        final file = File(task.targetPath);
        if (file.existsSync() && file.lengthSync() > 0) {
          return task.targetPath;
        }
      }
    }
    return null;
  }

  Future<DownloadTask> enqueueDownload({
    required String trackId,
    required String title,
    required String artist,
    String album = '',
    required String quality,
    required String url,
    Map<String, String>? headers,
    String? lyricText,
    String? coverUrl,
  }) async {
    _ensureInitialized();

    for (final existing in _tasks) {
      if (existing.trackId == trackId && existing.quality == quality) {
        if (existing.status == DownloadStatus.queued ||
            existing.status == DownloadStatus.downloading) {
          return existing;
        }
        if (existing.status == DownloadStatus.completed) {
          final file = File(existing.targetPath);
          if (file.existsSync() && file.lengthSync() > 0) {
            return existing;
          }
        }
      }
    }

    final ext = extFromUrlOrQuality(url, quality);
    final baseName = sanitizeFileName(
      artist.trim().isEmpty
          ? '$title ($quality)'
          : '$artist - $title ($quality)',
    );

    final targetPath = _resolveUniqueTargetPath(baseName, ext);
    final hasLyric = lyricText != null && lyricText.trim().isNotEmpty;
    final lrcPath = hasLyric
        ? '${targetPath.substring(0, targetPath.length - ext.length)}.lrc'
        : null;

    final taskId =
        '${DateTime.now().microsecondsSinceEpoch}_${++_taskSeq}_${sanitizeFileName(trackId)}';

    final task = DownloadTask(
      id: taskId,
      trackId: trackId,
      title: title,
      artist: artist,
      album: album,
      quality: quality,
      url: url,
      targetPath: targetPath,
      lrcPath: lrcPath,
      coverUrl: coverUrl,
      status: DownloadStatus.queued,
      createdAt: DateTime.now(),
      headers: headers == null
          ? const <String, String>{}
          : Map<String, String>.unmodifiable(headers),
    );

    if (hasLyric) {
      _pendingLyrics[task.id] = lyricText;
    }

    _tasks.insert(0, task);
    await _saveDownloadsIndex();
    notifyListeners();
    _pumpQueue();
    return task;
  }

  String _resolveUniqueTargetPath(String baseName, String ext) {
    var candidate = _joinPath(_downloadDir, '$baseName$ext');
    var index = 1;
    while (_isPathInUse(candidate) || File(candidate).existsSync()) {
      candidate = _joinPath(_downloadDir, '$baseName ($index)$ext');
      index++;
    }
    return candidate;
  }

  bool _isPathInUse(String path) {
    for (final task in _tasks) {
      if (task.targetPath == path &&
          (task.status == DownloadStatus.queued ||
              task.status == DownloadStatus.downloading)) {
        return true;
      }
    }
    return false;
  }

  void _pumpQueue() {
    if (!_initialized) return;

    while (_activeDownloads.length < _maxConcurrentDownloads) {
      final nextIndex = _tasks.indexWhere(
        (t) => t.status == DownloadStatus.queued,
      );
      if (nextIndex == -1) {
        break;
      }

      final task = _tasks[nextIndex].copyWith(
        status: DownloadStatus.downloading,
        error: null,
      );
      _tasks[nextIndex] = task;
      notifyListeners();
      unawaited(_runDownloadTask(task));
    }
  }

  Future<void> _runDownloadTask(DownloadTask initialTask) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    final handle = _ActiveDownloadHandle(client);
    _activeDownloads[initialTask.id] = handle;

    final partFile = File('${initialTask.targetPath}.part');
    IOSink? sink;

    try {
      final uri = Uri.parse(initialTask.url);
      final request = await client.getUrl(uri);
      _applyRequestHeaders(request, uri, initialTask.headers);

      final response = await request.close();
      if (handle.canceled) {
        await response.drain<void>();
        return;
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        throw HttpException(
          'HTTP ${response.statusCode}',
          uri: uri,
        );
      }

      final totalBytes =
          response.contentLength > 0 ? response.contentLength : 0;
      _updateTask(
        initialTask.id,
        (t) => t.copyWith(
          totalBytes: totalBytes,
          receivedBytes: 0,
        ),
        notify: true,
      );

      if (await partFile.exists()) {
        await partFile.delete();
      }
      await partFile.parent.create(recursive: true);

      sink = partFile.openWrite();
      var receivedBytes = 0;
      var lastNotifyAt = DateTime.now();

      await for (final chunk in response) {
        if (handle.canceled) {
          break;
        }
        sink.add(chunk);
        receivedBytes += chunk.length;

        final now = DateTime.now();
        if (now.difference(lastNotifyAt) >= _progressThrottle) {
          lastNotifyAt = now;
          _updateTask(
            initialTask.id,
            (t) => t.copyWith(receivedBytes: receivedBytes),
            notify: true,
          );
        }
      }

      if (handle.canceled) {
        await _closeSinkQuietly(sink);
        sink = null;
        await _deleteFileQuietly(partFile);
        return;
      }

      await sink.flush();
      await sink.close();
      sink = null;

      final finalSize = await partFile.length();
      if (finalSize <= 0) {
        throw const FileSystemException('Downloaded file is empty');
      }

      final targetFile = File(initialTask.targetPath);
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await partFile.rename(initialTask.targetPath);

      final lyricText = _pendingLyrics.remove(initialTask.id);
      if (lyricText != null &&
          lyricText.trim().isNotEmpty &&
          initialTask.lrcPath != null) {
        try {
          await File(initialTask.lrcPath!).writeAsString(lyricText);
        } catch (_) {
          // Ignore lyric write failures so audio download still succeeds.
        }
      }

      _updateTask(
        initialTask.id,
        (t) => t.copyWith(
          status: DownloadStatus.completed,
          receivedBytes: finalSize,
          totalBytes: t.totalBytes > 0 ? t.totalBytes : finalSize,
          error: null,
        ),
        notify: true,
      );
      await _saveDownloadsIndex();
    } catch (e) {
      await _closeSinkQuietly(sink);
      await _deleteFileQuietly(partFile);

      if (!handle.canceled) {
        _updateTask(
          initialTask.id,
          (t) => t.copyWith(
            status: DownloadStatus.failed,
            error: e.toString(),
          ),
          notify: true,
        );
        await _saveDownloadsIndex();
      }
    } finally {
      _activeDownloads.remove(initialTask.id);
      client.close(force: true);
      _pumpQueue();
    }
  }

  Future<void> cancelDownload(String taskId) async {
    _ensureInitialized();
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx == -1) return;

    final task = _tasks[idx];
    if (task.status != DownloadStatus.queued &&
        task.status != DownloadStatus.downloading) {
      return;
    }

    final handle = _activeDownloads[taskId];
    if (handle != null) {
      handle.canceled = true;
      handle.client.close(force: true);
    }

    _pendingLyrics.remove(taskId);
    await _deleteFileQuietly(File('${task.targetPath}.part'));

    _tasks[idx] = task.copyWith(
      status: DownloadStatus.canceled,
      error: null,
    );
    await _saveDownloadsIndex();
    notifyListeners();
    _pumpQueue();
  }

  Future<void> retryDownload(String taskId) async {
    _ensureInitialized();
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx == -1) return;

    final task = _tasks[idx];
    if (task.status != DownloadStatus.failed &&
        task.status != DownloadStatus.canceled) {
      return;
    }

    _tasks[idx] = task.copyWith(
      status: DownloadStatus.queued,
      receivedBytes: 0,
      error: null,
    );
    await _saveDownloadsIndex();
    notifyListeners();
    _pumpQueue();
  }

  Future<void> deleteDownload(
    String taskId, {
    bool deleteFile = true,
  }) async {
    _ensureInitialized();
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx == -1) return;

    final task = _tasks[idx];
    final handle = _activeDownloads[taskId];
    if (handle != null) {
      handle.canceled = true;
      handle.client.close(force: true);
    }

    _pendingLyrics.remove(taskId);
    _tasks.removeAt(idx);

    if (deleteFile) {
      await _deleteFileQuietly(File(task.targetPath));
      await _deleteFileQuietly(File('${task.targetPath}.part'));
      if (task.lrcPath != null) {
        await _deleteFileQuietly(File(task.lrcPath!));
      }
    }

    await _saveDownloadsIndex();
    notifyListeners();
    _pumpQueue();
  }

  Future<void> clearCompletedDownloads() async {
    _ensureInitialized();
    final before = _tasks.length;
    _tasks.removeWhere((t) => t.status == DownloadStatus.completed);
    if (_tasks.length != before) {
      await _saveDownloadsIndex();
      notifyListeners();
    }
  }

  void _updateTask(
    String taskId,
    DownloadTask Function(DownloadTask current) updater, {
    bool notify = false,
  }) {
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx == -1) return;
    _tasks[idx] = updater(_tasks[idx]);
    if (notify) {
      notifyListeners();
    }
  }

  void _applyRequestHeaders(
    HttpClientRequest request,
    Uri uri,
    Map<String, String>? customHeaders,
  ) {
    var hasUserAgent = false;
    var hasReferer = false;

    if (customHeaders != null) {
      for (final entry in customHeaders.entries) {
        final lowerKey = entry.key.toLowerCase();
        if (lowerKey == 'user-agent') hasUserAgent = true;
        if (lowerKey == 'referer') hasReferer = true;
        request.headers.set(entry.key, entry.value);
      }
    }

    if (!hasUserAgent) {
      request.headers.set(HttpHeaders.userAgentHeader, _defaultUserAgent);
    }

    final host = uri.host.toLowerCase();
    if (!hasReferer &&
        (host.contains('music.126.net') || host.contains('music.163.com'))) {
      request.headers.set(HttpHeaders.refererHeader, 'https://music.163.com/');
    }
  }

  Future<void> _loadDownloadsIndex() async {
    _tasks.clear();
    final file = File(_downloadsIndexPath);
    if (!await file.exists()) return;

    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;

      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          var task = DownloadTask.fromMap(item);
          if (task.status == DownloadStatus.downloading) {
            task = task.copyWith(
              status: DownloadStatus.failed,
              error: 'Download interrupted',
            );
          }
          _tasks.add(task);
        } else if (item is Map) {
          var task = DownloadTask.fromMap(Map<String, dynamic>.from(item));
          if (task.status == DownloadStatus.downloading) {
            task = task.copyWith(
              status: DownloadStatus.failed,
              error: 'Download interrupted',
            );
          }
          _tasks.add(task);
        }
      }
    } catch (_) {
      // Ignore corrupted index and start clean.
    }
  }

  Future<void> _loadListenCacheIndex() async {
    _listenCacheIndex.clear();
    final file = File(_listenCacheIndexPath);
    if (!await file.exists()) return;

    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;

      for (final item in decoded) {
        if (item is Map) {
          final entry = _ListenCacheEntry.fromMap(
            Map<String, dynamic>.from(item),
          );
          if (entry.key.isEmpty || entry.fileName.isEmpty) continue;
          final cachedFile = File(_joinPath(_listenCacheDir, entry.fileName));
          if (await cachedFile.exists() && await cachedFile.length() > 0) {
            _listenCacheIndex[entry.key] = entry;
          }
        }
      }
    } catch (_) {
      // Ignore corrupted index and start clean.
    }
  }

  Future<void> _saveDownloadsIndex() {
    final snapshot = _tasks.map((t) => t.toMap()).toList(growable: false);
    _downloadsWriteChain = _downloadsWriteChain.then((_) async {
      await _writeJsonAtomically(_downloadsIndexPath, snapshot);
    });
    return _downloadsWriteChain;
  }

  void _scheduleListenCacheIndexSave() {
    _listenCacheTouchTimer?.cancel();
    _listenCacheTouchTimer = Timer(const Duration(seconds: 2), () {
      unawaited(_saveListenCacheIndex());
    });
  }

  Future<void> _saveListenCacheIndex() {
    final snapshot =
        _listenCacheIndex.values.map((e) => e.toMap()).toList(growable: false);
    _listenCacheWriteChain = _listenCacheWriteChain.then((_) async {
      await _writeJsonAtomically(_listenCacheIndexPath, snapshot);
    });
    return _listenCacheWriteChain;
  }

  Future<void> _writeJsonAtomically(String path, Object data) async {
    final tmpFile = File('$path.tmp');
    try {
      await tmpFile.parent.create(recursive: true);
      await tmpFile.writeAsString(jsonEncode(data));
      final target = File(path);
      if (await target.exists()) {
        await target.delete();
      }
      await tmpFile.rename(path);
    } catch (_) {
      await _deleteFileQuietly(tmpFile);
    }
  }

  static String _joinPath(String a, String b) {
    if (a.endsWith(Platform.pathSeparator) || a.endsWith('/')) {
      return '$a$b';
    }
    return '$a${Platform.pathSeparator}$b';
  }

  static Future<void> _closeSinkQuietly(IOSink? sink) async {
    if (sink == null) return;
    try {
      await sink.close();
    } catch (_) {}
  }

  static Future<void> _deleteFileQuietly(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _listenCacheTouchTimer?.cancel();
    for (final handle in _activeDownloads.values) {
      handle.canceled = true;
      handle.client.close(force: true);
    }
    _activeDownloads.clear();
    super.dispose();
  }
}
