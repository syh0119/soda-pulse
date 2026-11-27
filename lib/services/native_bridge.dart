import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:soda_pulse/lyrics/lyric_models.dart';
import 'package:soda_pulse/models/track.dart';

enum LyricIslandMode {
  auto,
  lyricInfo,
  superLyric,
  ticker,
  overlay;

  String get wireValue {
    switch (this) {
      case LyricIslandMode.auto:
        return 'auto';
      case LyricIslandMode.lyricInfo:
        return 'lyric_info';
      case LyricIslandMode.superLyric:
        return 'super_lyric';
      case LyricIslandMode.ticker:
        return 'ticker';
      case LyricIslandMode.overlay:
        return 'overlay';
    }
  }

  static LyricIslandMode fromWire(String? v) {
    switch (v) {
      case 'lyric_info':
        return LyricIslandMode.lyricInfo;
      case 'super_lyric':
        return LyricIslandMode.superLyric;
      case 'ticker':
        return LyricIslandMode.ticker;
      case 'overlay':
        return LyricIslandMode.overlay;
      case 'auto':
      default:
        return LyricIslandMode.auto;
    }
  }
}

class PlaybackSnapshot {
  final bool isPlaying;
  final int positionMs;
  final int durationMs;
  final double speed;
  final bool buffering;
  final String? trackId;
  final int updatedAtElapsedMs;

  const PlaybackSnapshot({
    this.isPlaying = false,
    this.positionMs = 0,
    this.durationMs = 0,
    this.speed = 1.0,
    this.buffering = false,
    this.trackId,
    this.updatedAtElapsedMs = 0,
  });

  bool get isCompleted =>
      !isPlaying && durationMs > 0 && positionMs >= durationMs - 300;

  int extrapolatedPositionMs(int currentElapsedMs) {
    if (!isPlaying || buffering || updatedAtElapsedMs <= 0) {
      return durationMs > 0
          ? positionMs.clamp(0, durationMs)
          : math.max(0, positionMs);
    }
    final int delta = currentElapsedMs - updatedAtElapsedMs;
    if (delta <= 0) {
      return durationMs > 0
          ? positionMs.clamp(0, durationMs)
          : math.max(0, positionMs);
    }
    final int extrapolated = positionMs + (delta * speed).round();
    return durationMs > 0
        ? extrapolated.clamp(0, durationMs)
        : math.max(0, extrapolated);
  }

  factory PlaybackSnapshot.fromMap(Map<dynamic, dynamic> map) {
    return PlaybackSnapshot(
      isPlaying: (map['isPlaying'] as bool?) ?? false,
      positionMs: (map['positionMs'] as num?)?.toInt() ?? 0,
      durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
      speed: (map['speed'] as num?)?.toDouble() ?? 1.0,
      buffering: (map['buffering'] as bool?) ?? false,
      trackId: map['trackId']?.toString(),
      updatedAtElapsedMs: (map['updatedAtElapsedMs'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }

  PlaybackSnapshot copyWith({
    bool? isPlaying,
    int? positionMs,
    int? durationMs,
    double? speed,
    bool? buffering,
    String? trackId,
    int? updatedAtElapsedMs,
  }) {
    return PlaybackSnapshot(
      isPlaying: isPlaying ?? this.isPlaying,
      positionMs: positionMs ?? this.positionMs,
      durationMs: durationMs ?? this.durationMs,
      speed: speed ?? this.speed,
      buffering: buffering ?? this.buffering,
      trackId: trackId ?? this.trackId,
      updatedAtElapsedMs: updatedAtElapsedMs ?? this.updatedAtElapsedMs,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'isPlaying': isPlaying,
      'positionMs': positionMs,
      'durationMs': durationMs,
      'speed': speed,
      'buffering': buffering,
      'trackId': trackId,
      'updatedAtElapsedMs': updatedAtElapsedMs,
    };
  }
}

typedef PlaybackState = PlaybackSnapshot;

class EnvironmentStatus {
  final String superLyricStatus;
  final String superLyricVersion;
  final LyricIslandMode activeMode;
  final LyricIslandMode selectedMode;
  final bool canDrawOverlay;
  final bool hasAudioPerm;
  final bool hasNotifPerm;
  final int androidSdk;
  final String brand;
  final String model;
  final String lastPublishResult;

  const EnvironmentStatus({
    this.superLyricStatus = 'unknown',
    this.superLyricVersion = '',
    this.activeMode = LyricIslandMode.auto,
    this.selectedMode = LyricIslandMode.auto,
    this.canDrawOverlay = false,
    this.hasAudioPerm = false,
    this.hasNotifPerm = false,
    this.androidSdk = 0,
    this.brand = '',
    this.model = '',
    this.lastPublishResult = '',
  });

  factory EnvironmentStatus.fromMap(Map<dynamic, dynamic> map) {
    return EnvironmentStatus(
      superLyricStatus: (map['superLyricStatus'] ?? 'unknown').toString(),
      superLyricVersion: (map['superLyricVersion'] ?? '').toString(),
      activeMode: LyricIslandMode.fromWire(map['activeMode']?.toString()),
      selectedMode: LyricIslandMode.fromWire(map['selectedMode']?.toString()),
      canDrawOverlay: (map['canDrawOverlay'] as bool?) ?? false,
      hasAudioPerm: (map['hasAudioPerm'] as bool?) ?? false,
      hasNotifPerm: (map['hasNotifPerm'] as bool?) ?? false,
      androidSdk: (map['androidSdk'] as num?)?.toInt() ?? 0,
      brand: (map['brand'] ?? '').toString(),
      model: (map['model'] ?? '').toString(),
      lastPublishResult: (map['lastPublishResult'] ?? '').toString(),
    );
  }

  EnvironmentStatus copyWith({
    String? superLyricStatus,
    String? superLyricVersion,
    LyricIslandMode? activeMode,
    LyricIslandMode? selectedMode,
    bool? canDrawOverlay,
    bool? hasAudioPerm,
    bool? hasNotifPerm,
    int? androidSdk,
    String? brand,
    String? model,
    String? lastPublishResult,
  }) {
    return EnvironmentStatus(
      superLyricStatus: superLyricStatus ?? this.superLyricStatus,
      superLyricVersion: superLyricVersion ?? this.superLyricVersion,
      activeMode: activeMode ?? this.activeMode,
      selectedMode: selectedMode ?? this.selectedMode,
      canDrawOverlay: canDrawOverlay ?? this.canDrawOverlay,
      hasAudioPerm: hasAudioPerm ?? this.hasAudioPerm,
      hasNotifPerm: hasNotifPerm ?? this.hasNotifPerm,
      androidSdk: androidSdk ?? this.androidSdk,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      lastPublishResult: lastPublishResult ?? this.lastPublishResult,
    );
  }
}

typedef RemoteActionCallback = void Function(
  String action,
  Map<String, dynamic> payload,
);

class NativePlayerBridge extends ChangeNotifier {
  static const MethodChannel _methodChannel =
      MethodChannel('com.sodapulse.music/player');
  static const EventChannel _eventChannel =
      EventChannel('com.sodapulse.music/events');

  static final NativePlayerBridge instance = NativePlayerBridge._internal();

  factory NativePlayerBridge() => instance;

  NativePlayerBridge._internal() {
    _startListening();
  }

  final StreamController<PlaybackSnapshot> _stateController =
      StreamController<PlaybackSnapshot>.broadcast();

  StreamSubscription<dynamic>? _eventSubscription;
  PlaybackSnapshot _snapshot = const PlaybackSnapshot();
  EnvironmentStatus _environmentStatus = const EnvironmentStatus();
  Track? _currentTrack;
  ParsedLyric? _currentLyrics;

  int _lastSnapshotEpochMs = 0;
  int _lyricOffsetMs = 0;
  bool _floatingLyricEnabled = false;
  bool _overlayLocked = false;
  double _overlayFontSizeSp = 15.0;
  int _overlayYOffsetPx = 120;
  LyricIslandMode _islandMode = LyricIslandMode.auto;

  RemoteActionCallback? onRemoteAction;

  PlaybackSnapshot get snapshot => _snapshot;
  PlaybackSnapshot get currentState => _snapshot;
  Stream<PlaybackSnapshot> get stateStream => _stateController.stream;
  EnvironmentStatus get environmentStatus => _environmentStatus;
  Track? get currentTrack => _currentTrack;
  ParsedLyric? get currentLyrics => _currentLyrics;

  bool get isPlaying => _snapshot.isPlaying;
  int get durationMs => _snapshot.durationMs;
  int get positionMs => currentPositionMs();
  int get lyricOffsetMs => _lyricOffsetMs;
  bool get floatingLyricEnabled => _floatingLyricEnabled;
  LyricIslandMode get islandMode => _islandMode;

  int currentPositionMs() {
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (_snapshot.updatedAtElapsedMs > 1000000000000) {
      return _snapshot.extrapolatedPositionMs(now);
    }
    if (!_snapshot.isPlaying ||
        _snapshot.buffering ||
        _lastSnapshotEpochMs <= 0) {
      return _snapshot.durationMs > 0
          ? _snapshot.positionMs.clamp(0, _snapshot.durationMs)
          : math.max(0, _snapshot.positionMs);
    }
    final int delta = now - _lastSnapshotEpochMs;
    if (delta <= 0) {
      return _snapshot.durationMs > 0
          ? _snapshot.positionMs.clamp(0, _snapshot.durationMs)
          : math.max(0, _snapshot.positionMs);
    }
    final int extrapolated =
        _snapshot.positionMs + (delta * _snapshot.speed).round();
    return _snapshot.durationMs > 0
        ? extrapolated.clamp(0, _snapshot.durationMs)
        : math.max(0, extrapolated);
  }

  void _startListening() {
    _eventSubscription?.cancel();
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      _handleNativeEvent,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('NativePlayerBridge EventChannel error: $error');
      },
    );
  }

  void _handleNativeEvent(dynamic rawEvent) {
    if (rawEvent is! Map) {
      return;
    }
    final Map<dynamic, dynamic> event = rawEvent;
    final String? type = (event['type'] ?? event['event'])?.toString();
    final Map<dynamic, dynamic> payload =
        event['data'] is Map ? event['data'] as Map<dynamic, dynamic> : event;

    switch (type) {
      case 'playback':
        _snapshot = PlaybackSnapshot.fromMap(payload);
        _lastSnapshotEpochMs = DateTime.now().millisecondsSinceEpoch;
        if (!_stateController.isClosed) {
          _stateController.add(_snapshot);
        }
        notifyListeners();
        break;
      case 'action':
        final String action = (event['action'] ??
                payload['action'] ??
                event['name'] ??
                '')
            .toString();
        if (action.isNotEmpty) {
          onRemoteAction?.call(action, Map<String, dynamic>.from(payload));
        }
        break;
      case 'lyric_status':
        _environmentStatus = EnvironmentStatus.fromMap(payload);
        _islandMode = _environmentStatus.selectedMode;
        notifyListeners();
        break;
      default:
        break;
    }
  }

  Future<List<Track>> scanLocalAudio() async {
    final dynamic result =
        await _methodChannel.invokeMethod<dynamic>('scanLocalAudio');
    if (result is! List) {
      return <Track>[];
    }
    return result
        .whereType<Map<dynamic, dynamic>>()
        .map((Map<dynamic, dynamic> item) =>
            Track.fromMap(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<Map<String, dynamic>> readTrackLyrics({String? filePath, String? uri}) async {
    final dynamic result = await _methodChannel.invokeMethod<dynamic>(
      'readTrackLyrics',
      <String, dynamic>{
        'filePath': filePath,
        'uri': uri,
      },
    );
    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }
    if (result is String) {
      return <String, dynamic>{'raw': result};
    }
    return const <String, dynamic>{};
  }

  Future<Track> prepareDemoAudio() async {
    final dynamic result =
        await _methodChannel.invokeMethod<dynamic>('prepareDemoAudio');
    if (result is Map) {
      return Track.fromMap(Map<String, dynamic>.from(result));
    }
    throw PlatformException(
      code: 'DEMO_AUDIO_NULL',
      message: 'Native prepareDemoAudio returned null',
    );
  }

  Future<void> loadAndPlay(
    Track track, {
    ParsedLyric? parsedLyrics,
    Map<String, dynamic>? lyricPayload,
    Map<String, String>? headers,
  }) async {
    _currentTrack = track;
    _currentLyrics = parsedLyrics;
    notifyListeners();

    final Map<String, dynamic>? payload =
        lyricPayload ??
        parsedLyrics?.toNativePayload(
          songId: track.id,
          songName: track.title,
          artist: track.artist,
          album: track.album,
          durationMs: track.durationMs,
        );

    final effectiveHeaders = headers ?? track.headers;
    await _methodChannel.invokeMethod<void>(
      'loadAndPlay',
      <String, dynamic>{
        'track': track.toMap(),
        if (payload != null) 'lyricPayload': payload,
        if (effectiveHeaders != null && effectiveHeaders.isNotEmpty)
          'headers': effectiveHeaders,
      },
    );
  }

  Future<void> play() async {
    await _methodChannel.invokeMethod<void>('play');
  }

  Future<void> pause() async {
    await _methodChannel.invokeMethod<void>('pause');
  }

  Future<void> togglePlay() async {
    await _methodChannel.invokeMethod<void>('togglePlay');
  }

  Future<void> togglePlayPause() => togglePlay();

  Future<void> seekTo(int positionMs) async {
    await _methodChannel.invokeMethod<void>(
      'seekTo',
      <String, dynamic>{'positionMs': positionMs},
    );
  }

  Future<void> setQueue(List<Track> items, int index) async {
    await _methodChannel.invokeMethod<void>(
      'setQueue',
      <String, dynamic>{
        'items': items.map((Track t) => t.toMap()).toList(),
        'index': index,
      },
    );
  }

  Future<void> next() async {
    await _methodChannel.invokeMethod<void>('next');
  }

  Future<void> previous() async {
    await _methodChannel.invokeMethod<void>('previous');
  }

  Future<void> skipToNext() => next();

  Future<void> skipToPrevious() => previous();

  Future<void> setLyricMode(LyricIslandMode mode) async {
    _islandMode = mode;
    notifyListeners();
    await _methodChannel.invokeMethod<void>(
      'setLyricMode',
      <String, dynamic>{'mode': mode.wireValue},
    );
  }

  Future<void> setLyricOffset(int offsetMs) async {
    _lyricOffsetMs = offsetMs;
    notifyListeners();
    await _methodChannel.invokeMethod<void>(
      'setLyricOffset',
      <String, dynamic>{'offsetMs': offsetMs},
    );
  }

  Future<void> setOverlayConfig({
    required bool enabled,
    required bool locked,
    required double fontSizeSp,
    required int yOffsetPx,
  }) async {
    _floatingLyricEnabled = enabled;
    _overlayLocked = locked;
    _overlayFontSizeSp = fontSizeSp;
    _overlayYOffsetPx = yOffsetPx;
    notifyListeners();

    await _methodChannel.invokeMethod<void>(
      'setOverlayConfig',
      <String, dynamic>{
        'enabled': enabled,
        'locked': locked,
        'fontSizeSp': fontSizeSp,
        'yOffsetPx': yOffsetPx,
      },
    );
  }

  Future<void> setFloatingLyricEnabled(bool enabled) async {
    await setOverlayConfig(
      enabled: enabled,
      locked: _overlayLocked,
      fontSizeSp: _overlayFontSizeSp,
      yOffsetPx: _overlayYOffsetPx,
    );
  }

  Future<bool> canDrawOverlays() async {
    final bool? result =
        await _methodChannel.invokeMethod<bool>('canDrawOverlays');
    return result ?? false;
  }

  Future<void> requestOverlayPermission() async {
    await _methodChannel.invokeMethod<void>('requestOverlayPermission');
  }

  Future<bool> requestPermissions() async {
    final dynamic result =
        await _methodChannel.invokeMethod<dynamic>('requestPermissions');
    if (result is bool) {
      return result;
    }
    if (result is Map) {
      return (result['granted'] as bool?) ?? false;
    }
    return false;
  }

  Future<EnvironmentStatus> getEnvironmentStatus() async {
    final dynamic result =
        await _methodChannel.invokeMethod<dynamic>('getEnvironmentStatus');
    if (result is Map) {
      _environmentStatus = EnvironmentStatus.fromMap(result);
      _islandMode = _environmentStatus.selectedMode;
      notifyListeners();
    }
    return _environmentStatus;
  }

  Future<Map<String, dynamic>> getPreferences() async {
    final dynamic result =
        await _methodChannel.invokeMethod<dynamic>('getPreferences');
    if (result is! Map) {
      return <String, dynamic>{};
    }
    final Map<String, dynamic> prefs = Map<String, dynamic>.from(result);
    if (prefs['lyricOffsetMs'] is num) {
      _lyricOffsetMs = (prefs['lyricOffsetMs'] as num).toInt();
    }
    if (prefs['floatingLyricEnabled'] is bool) {
      _floatingLyricEnabled = prefs['floatingLyricEnabled'] as bool;
    }
    if (prefs['overlayLocked'] is bool) {
      _overlayLocked = prefs['overlayLocked'] as bool;
    }
    if (prefs['overlayFontSizeSp'] is num) {
      _overlayFontSizeSp = (prefs['overlayFontSizeSp'] as num).toDouble();
    }
    if (prefs['overlayYOffsetPx'] is num) {
      _overlayYOffsetPx = (prefs['overlayYOffsetPx'] as num).toInt();
    }
    if (prefs['islandMode'] != null) {
      _islandMode = LyricIslandMode.fromWire(prefs['islandMode'].toString());
    }
    notifyListeners();
    return prefs;
  }

  Future<void> savePreferences(Map<String, dynamic> prefs) async {
    await _methodChannel.invokeMethod<void>('savePreferences', prefs);
  }

  Future<void> setEqParams(List<double> gains, double preGain) async {
    await _methodChannel.invokeMethod<void>(
      'setEqParams',
      <String, dynamic>{
        'gains': gains,
        'preGain': preGain,
      },
    );
  }

  Future<void> setPlaybackSpeed(double speed) async {
    await _methodChannel.invokeMethod<void>(
      'setPlaybackSpeed',
      <String, dynamic>{'speed': speed},
    );
  }

  Future<void> setFavorite(bool favorite) async {
    await _methodChannel.invokeMethod<void>(
      'setFavorite',
      <String, dynamic>{'favorite': favorite},
    );
  }

  Future<Map<String, dynamic>> getCoverArtInfo(String? uri) async {
    if (uri == null || uri.isEmpty) {
      return const <String, dynamic>{};
    }
    final dynamic result = await _methodChannel.invokeMethod<dynamic>(
      'getCoverArtInfo',
      <String, dynamic>{'uri': uri},
    );
    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }
    return const <String, dynamic>{};
  }

  Future<void> shareText(String text, {String? subject}) async {
    await _methodChannel.invokeMethod<void>(
      'shareText',
      <String, dynamic>{
        'text': text,
        if (subject != null) 'subject': subject,
      },
    );
  }

  Future<Map<String, String>?> pickTextFile() async {
    final dynamic result =
        await _methodChannel.invokeMethod<dynamic>('pickTextFile');
    if (result is Map) {
      return <String, String>{
        'name': (result['name'] ?? 'file.txt').toString(),
        'content': (result['content'] ?? '').toString(),
      };
    }
    return null;
  }

  Future<String?> exportTextFile(String fileName, String content) async {
    final dynamic result = await _methodChannel.invokeMethod<dynamic>(
      'exportTextFile',
      <String, dynamic>{
        'fileName': fileName,
        'content': content,
      },
    );
    if (result is Map) {
      return result['path']?.toString();
    }
    return null;
  }

  Future<Map<String, dynamic>> pluginLoad(
    String id,
    String script,
    String type,
  ) async {
    final dynamic result = await _methodChannel.invokeMethod<dynamic>(
      'pluginLoad',
      <String, dynamic>{'id': id, 'script': script, 'type': type},
    );
    if (result is Map) return Map<String, dynamic>.from(result);
    return const <String, dynamic>{'ok': false};
  }

  Future<bool> pluginUnload(String id) async {
    final bool? result = await _methodChannel.invokeMethod<bool>(
      'pluginUnload',
      <String, dynamic>{'id': id},
    );
    return result ?? false;
  }

  Future<Map<String, dynamic>> pluginTest(String id) async {
    final dynamic result = await _methodChannel.invokeMethod<dynamic>(
      'pluginTest',
      <String, dynamic>{'id': id},
    );
    if (result is Map) return Map<String, dynamic>.from(result);
    return const <String, dynamic>{'ok': false};
  }

  Future<List<Track>> pluginSearch(
    String pluginId,
    String query, {
    int page = 1,
  }) async {
    final dynamic result = await _methodChannel.invokeMethod<dynamic>(
      'pluginSearch',
      <String, dynamic>{'pluginId': pluginId, 'query': query, 'page': page},
    );
    if (result is! List) return const <Track>[];
    return result
        .whereType<Map<dynamic, dynamic>>()
        .map((m) => Track.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<Map<String, dynamic>> pluginResolveUrl(
    String pluginId,
    String rawItemJson, {
    String quality = 'standard',
    String source = '',
  }) async {
    final dynamic result = await _methodChannel.invokeMethod<dynamic>(
      'pluginResolveUrl',
      <String, dynamic>{
        'pluginId': pluginId,
        'rawItemJson': rawItemJson,
        'quality': quality,
        'source': source,
      },
    );
    if (result is Map) return Map<String, dynamic>.from(result);
    return const <String, dynamic>{'ok': false};
  }

  Future<Map<String, dynamic>> pluginResolveLyric(
    String pluginId,
    String rawItemJson,
  ) async {
    final dynamic result = await _methodChannel.invokeMethod<dynamic>(
      'pluginResolveLyric',
      <String, dynamic>{'pluginId': pluginId, 'rawItemJson': rawItemJson},
    );
    if (result is Map) return Map<String, dynamic>.from(result);
    return const <String, dynamic>{'ok': false};
  }

  Future<List<Track>> pluginImportSheet(
    String pluginId,
    String urlOrId,
  ) async {
    final dynamic result = await _methodChannel.invokeMethod<dynamic>(
      'pluginImportSheet',
      <String, dynamic>{'pluginId': pluginId, 'urlOrId': urlOrId},
    );
    if (result is! List) return const <Track>[];
    return result
        .whereType<Map<dynamic, dynamic>>()
        .map((m) => Track.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _stateController.close();
    super.dispose();
  }
}
