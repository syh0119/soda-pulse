class Track {
  final String id;
  final String title;
  final String artist;
  final String album;
  final int durationMs;
  final String uri;
  final String? filePath;
  final String? albumArtUri;
  final bool isDemo;
  final String? pluginId;
  final String? rawPluginData;
  final String? sourcePlatform;
  final Map<String, String>? headers;

  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.durationMs,
    required this.uri,
    this.filePath,
    this.albumArtUri,
    this.isDemo = false,
    this.pluginId,
    this.rawPluginData,
    this.sourcePlatform,
    this.headers,
  });

  bool get isOnlinePluginTrack => pluginId != null && pluginId!.isNotEmpty;

  factory Track.fromMap(Map<dynamic, dynamic> map) {
    final dynamic rawDuration = map['durationMs'];
    final int parsedDuration;
    if (rawDuration is int) {
      parsedDuration = rawDuration;
    } else if (rawDuration is num) {
      parsedDuration = rawDuration.toInt();
    } else if (rawDuration is String) {
      parsedDuration = int.tryParse(rawDuration) ?? 0;
    } else {
      parsedDuration = 0;
    }

    final dynamic rawIsDemo = map['isDemo'];
    final bool parsedIsDemo;
    if (rawIsDemo is bool) {
      parsedIsDemo = rawIsDemo;
    } else if (rawIsDemo is num) {
      parsedIsDemo = rawIsDemo != 0;
    } else if (rawIsDemo is String) {
      parsedIsDemo = rawIsDemo.toLowerCase() == 'true' || rawIsDemo == '1';
    } else {
      parsedIsDemo = false;
    }

    Map<String, String>? parsedHeaders;
    final dynamic rawHeaders = map['headers'];
    if (rawHeaders is Map) {
      parsedHeaders = <String, String>{};
      rawHeaders.forEach((k, v) {
        if (k != null && v != null) {
          parsedHeaders![k.toString()] = v.toString();
        }
      });
      if (parsedHeaders.isEmpty) parsedHeaders = null;
    }

    return Track(
      id: (map['id'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      artist: (map['artist'] ?? '').toString(),
      album: (map['album'] ?? '').toString(),
      durationMs: parsedDuration < 0 ? 0 : parsedDuration,
      uri: (map['uri'] ?? '').toString(),
      filePath: map['filePath']?.toString(),
      albumArtUri: map['albumArtUri']?.toString(),
      isDemo: parsedIsDemo,
      pluginId: map['pluginId']?.toString(),
      rawPluginData: (map['rawPluginData'] ?? map['rawItemJson'])?.toString(),
      sourcePlatform: map['sourcePlatform']?.toString(),
      headers: parsedHeaders,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'durationMs': durationMs,
      'uri': uri,
      'filePath': filePath,
      'albumArtUri': albumArtUri,
      'isDemo': isDemo,
      if (pluginId != null) 'pluginId': pluginId,
      if (rawPluginData != null) 'rawPluginData': rawPluginData,
      if (sourcePlatform != null) 'sourcePlatform': sourcePlatform,
      if (headers != null && headers!.isNotEmpty) 'headers': headers,
    };
  }

  Track copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    int? durationMs,
    String? uri,
    String? filePath,
    String? albumArtUri,
    bool? isDemo,
    String? pluginId,
    String? rawPluginData,
    String? sourcePlatform,
    Map<String, String>? headers,
  }) {
    return Track(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      durationMs: durationMs ?? this.durationMs,
      uri: uri ?? this.uri,
      filePath: filePath ?? this.filePath,
      albumArtUri: albumArtUri ?? this.albumArtUri,
      isDemo: isDemo ?? this.isDemo,
      pluginId: pluginId ?? this.pluginId,
      rawPluginData: rawPluginData ?? this.rawPluginData,
      sourcePlatform: sourcePlatform ?? this.sourcePlatform,
      headers: headers ?? this.headers,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Track &&
        other.id == id &&
        other.title == title &&
        other.artist == artist &&
        other.album == album &&
        other.durationMs == durationMs &&
        other.uri == uri &&
        other.filePath == filePath &&
        other.albumArtUri == albumArtUri &&
        other.isDemo == isDemo &&
        other.pluginId == pluginId;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      title,
      artist,
      album,
      durationMs,
      uri,
      filePath,
      albumArtUri,
      isDemo,
      pluginId,
    );
  }
}
