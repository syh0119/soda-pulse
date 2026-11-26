import 'dart:async';
import 'dart:convert';
import 'dart:io';

enum PluginType { lx, musicFree }

class MusicSourcePlugin {
  const MusicSourcePlugin({
    required this.id,
    required this.name,
    required this.version,
    required this.author,
    required this.description,
    required this.type,
    required this.platforms,
    this.enabled = true,
    this.sourceUrl,
    required this.script,
    required this.importedAtMs,
  });

  final String id;
  final String name;
  final String version;
  final String author;
  final String description;
  final PluginType type;
  final List<String> platforms;
  final bool enabled;
  final String? sourceUrl;
  final String script;
  final int importedAtMs;

  MusicSourcePlugin copyWith({
    String? id,
    String? name,
    String? version,
    String? author,
    String? description,
    PluginType? type,
    List<String>? platforms,
    bool? enabled,
    String? sourceUrl,
    bool clearSourceUrl = false,
    String? script,
    int? importedAtMs,
  }) {
    return MusicSourcePlugin(
      id: id ?? this.id,
      name: name ?? this.name,
      version: version ?? this.version,
      author: author ?? this.author,
      description: description ?? this.description,
      type: type ?? this.type,
      platforms: platforms ?? List<String>.unmodifiable(this.platforms),
      enabled: enabled ?? this.enabled,
      sourceUrl: clearSourceUrl ? null : (sourceUrl ?? this.sourceUrl),
      script: script ?? this.script,
      importedAtMs: importedAtMs ?? this.importedAtMs,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'version': version,
      'author': author,
      'description': description,
      'type': type.name,
      'platforms': platforms,
      'enabled': enabled,
      'sourceUrl': sourceUrl,
      'script': script,
      'importedAtMs': importedAtMs,
    };
  }

  factory MusicSourcePlugin.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] as String? ?? '';
    final type = PluginType.values.firstWhere(
      (e) => e.name == typeName,
      orElse: () => PluginType.lx,
    );
    final rawPlatforms = json['platforms'] as List<dynamic>? ?? const <dynamic>[];
    return MusicSourcePlugin(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      version: json['version'] as String? ?? '1.0.0',
      author: json['author'] as String? ?? '未知作者',
      description: json['description'] as String? ?? '',
      type: type,
      platforms: rawPlatforms.map((e) => e.toString()).toList(growable: false),
      enabled: json['enabled'] as bool? ?? true,
      sourceUrl: json['sourceUrl'] as String?,
      script: json['script'] as String? ?? '',
      importedAtMs: (json['importedAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

class PluginParser {
  static const List<String> _lxKnownPlatforms = <String>[
    'kw',
    'kg',
    'tx',
    'wy',
    'mg',
    'local',
  ];

  static MusicSourcePlugin parseScript(
    String rawScript, {
    String? sourceUrl,
    String? fileName,
  }) {
    final script = rawScript.trim();
    if (script.isEmpty) {
      throw const FormatException('这个文件看起来不是音源脚本');
    }

    final isMusicFree = _looksLikeMusicFree(script);
    final isLx = _looksLikeLx(script);

    if (!isMusicFree && !isLx) {
      throw const FormatException('这个文件看起来不是音源脚本');
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final cleanFileName = _stripJsExtension(fileName);

    if (isMusicFree && !isLx) {
      return _parseMusicFree(
        rawScript,
        sourceUrl: sourceUrl,
        fallbackName: cleanFileName,
        importedAtMs: nowMs,
      );
    }

    if (isLx && !isMusicFree) {
      return _parseLx(
        rawScript,
        sourceUrl: sourceUrl,
        fallbackName: cleanFileName,
        importedAtMs: nowMs,
      );
    }

    if (RegExp(r'\bgetMediaSource\b').hasMatch(script)) {
      return _parseMusicFree(
        rawScript,
        sourceUrl: sourceUrl,
        fallbackName: cleanFileName,
        importedAtMs: nowMs,
      );
    }

    return _parseLx(
      rawScript,
      sourceUrl: sourceUrl,
      fallbackName: cleanFileName,
      importedAtMs: nowMs,
    );
  }

  static bool _looksLikeLx(String script) {
    final hasHeaderTag =
        RegExp(r'^\s*\*?\s*@(?:name|version|author|description)\b', multiLine: true)
            .hasMatch(script);
    final hasLxApi = RegExp(r'\b(?:EVENT_NAMES|globalThis\.lx|window\.lx)\b')
        .hasMatch(script);
    final hasSourcesBlock = RegExp(r'\bsources\s*:').hasMatch(script) &&
        RegExp(r'''['"]?(?:kw|kg|tx|wy|mg|local)['"]?\s*:''').hasMatch(script);

    if (hasLxApi || hasSourcesBlock) {
      return true;
    }
    if (hasHeaderTag &&
        RegExp(r'^\s*\*?\s*@(?:version|author|description)\b', multiLine: true)
            .hasMatch(script)) {
      return true;
    }
    return false;
  }

  static bool _looksLikeMusicFree(String script) {
    if (!RegExp(r'\bmodule\.exports\b').hasMatch(script)) {
      return false;
    }
    return RegExp(r'\bgetMediaSource\b').hasMatch(script) ||
        RegExp(r'\bplatform\s*:').hasMatch(script) ||
        RegExp(r'\bsrcUrl\s*:').hasMatch(script);
  }

  static MusicSourcePlugin _parseLx(
    String rawScript, {
    String? sourceUrl,
    String? fallbackName,
    required int importedAtMs,
  }) {
    final name = _extractLxTag(rawScript, 'name') ??
        (fallbackName != null && fallbackName.isNotEmpty
            ? fallbackName
            : '未命名 LX 音源');
    final version = _extractLxTag(rawScript, 'version') ?? '1.0.0';
    final author = _extractLxTag(rawScript, 'author') ?? '未知作者';
    final description = _extractLxTag(rawScript, 'description') ?? '';
    final platforms = _extractLxPlatforms(rawScript);
    final id = _buildDeterministicId(PluginType.lx, name, version);

    return MusicSourcePlugin(
      id: id,
      name: name,
      version: version,
      author: author,
      description: description,
      type: PluginType.lx,
      platforms: platforms,
      enabled: true,
      sourceUrl: sourceUrl,
      script: rawScript,
      importedAtMs: importedAtMs,
    );
  }

  static MusicSourcePlugin _parseMusicFree(
    String rawScript, {
    String? sourceUrl,
    String? fallbackName,
    required int importedAtMs,
  }) {
    final platform = _extractJsStringProp(rawScript, 'platform');
    final version = _extractJsStringProp(rawScript, 'version') ??
        _extractLxTag(rawScript, 'version') ??
        '1.0.0';
    final author = _extractJsStringProp(rawScript, 'author') ??
        _extractLxTag(rawScript, 'author') ??
        '未知作者';
    final srcUrl = _extractJsStringProp(rawScript, 'srcUrl');
    final description = _extractJsStringProp(rawScript, 'description') ??
        _extractLxTag(rawScript, 'description') ??
        '';
    final name = (platform != null && platform.isNotEmpty)
        ? platform
        : (_extractLxTag(rawScript, 'name') ??
            (fallbackName != null && fallbackName.isNotEmpty
                ? fallbackName
                : '未命名 MusicFree 插件'));
    final platforms = (platform != null && platform.isNotEmpty)
        ? <String>[platform]
        : const <String>[];
    final resolvedSourceUrl = (sourceUrl != null && sourceUrl.trim().isNotEmpty)
        ? sourceUrl.trim()
        : srcUrl;
    final id = _buildDeterministicId(PluginType.musicFree, name, version);

    return MusicSourcePlugin(
      id: id,
      name: name,
      version: version,
      author: author,
      description: description,
      type: PluginType.musicFree,
      platforms: platforms,
      enabled: true,
      sourceUrl: resolvedSourceUrl,
      script: rawScript,
      importedAtMs: importedAtMs,
    );
  }

  static String? _extractLxTag(String script, String tag) {
    final match = RegExp(
      '^\\s*\\*?\\s*@$tag\\s+(.+?)\\s*\$',
      multiLine: true,
    ).firstMatch(script);
    final value = match?.group(1)?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  static List<String> _extractLxPlatforms(String script) {
    final found = <String>{};
    final keyPattern = RegExp(
      r'''(?:sources\s*:\s*\{[^}]*\}|\b(kw|kg|tx|wy|mg|local)\b\s*[:=]|['"](kw|kg|tx|wy|mg|local)['"])''',
      dotAll: true,
    );
    for (final match in keyPattern.allMatches(script)) {
      final g1 = match.group(1);
      final g2 = match.group(2);
      if (g1 != null) found.add(g1);
      if (g2 != null) found.add(g2);
    }

    final sourcesBlockMatch =
        RegExp(r'sources\s*:\s*\{([^}]*)\}', dotAll: true).firstMatch(script);
    if (sourcesBlockMatch != null) {
      final block = sourcesBlockMatch.group(1) ?? '';
      for (final platform in _lxKnownPlatforms) {
        if (RegExp('''['"]?$platform['"]?\\s*:''').hasMatch(block)) {
          found.add(platform);
        }
      }
    }

    return _lxKnownPlatforms
        .where(found.contains)
        .toList(growable: false);
  }

  static String? _extractJsStringProp(String script, String prop) {
    final match = RegExp(
      '''\\b$prop\\s*:\\s*(['"`])((?:\\\\.|(?!\\1).)*)\\1''',
      dotAll: true,
    ).firstMatch(script);
    final value = match?.group(2)?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  static String? _stripJsExtension(String? fileName) {
    if (fileName == null) return null;
    final trimmed = fileName.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.toLowerCase().endsWith('.js')) {
      return trimmed.substring(0, trimmed.length - 3).trim();
    }
    return trimmed;
  }

  static String _buildDeterministicId(
    PluginType type,
    String name,
    String version,
  ) {
    final input = '${type.name}|$name|$version';
    var hash = 0x811c9dc5;
    for (final unit in utf8.encode(input)) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return '${type.name}_${hash.toRadixString(16).padLeft(8, '0')}';
  }
}

class PluginFetcher {
  static const Duration _timeout = Duration(seconds: 12);

  static Future<String> fetchScriptFromUrl(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw const FormatException('无效的脚本链接');
    }

    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final request = await client.getUrl(uri).timeout(_timeout);
      request.followRedirects = true;
      request.maxRedirects = 5;
      request.headers.set(HttpHeaders.userAgentHeader, 'SodaPulse/1.0');

      final response = await request.close().timeout(_timeout);
      if (response.statusCode != HttpStatus.ok) {
        throw FormatException('请求失败 (HTTP ${response.statusCode})');
      }

      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_timeout);
      if (body.trim().isEmpty) {
        throw const FormatException('下载的脚本内容为空');
      }
      return body;
    } finally {
      client.close(force: true);
    }
  }
}
