class LyricWord {
  final String text;
  final int startMs;
  final int endMs;

  const LyricWord({
    required this.text,
    required this.startMs,
    required this.endMs,
  });

  LyricWord copyWith({
    String? text,
    int? startMs,
    int? endMs,
  }) {
    return LyricWord(
      text: text ?? this.text,
      startMs: startMs ?? this.startMs,
      endMs: endMs ?? this.endMs,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'text': text,
      'startMs': startMs,
      'endMs': endMs,
    };
  }
}

class LyricLine {
  final String text;
  final int startMs;
  final int endMs;
  final List<LyricWord>? words;
  final String? translation;
  final String? phonetic;

  const LyricLine({
    required this.text,
    required this.startMs,
    required this.endMs,
    this.words,
    this.translation,
    this.phonetic,
  });

  LyricLine copyWith({
    String? text,
    int? startMs,
    int? endMs,
    List<LyricWord>? words,
    String? translation,
    String? phonetic,
  }) {
    return LyricLine(
      text: text ?? this.text,
      startMs: startMs ?? this.startMs,
      endMs: endMs ?? this.endMs,
      words: words ?? this.words,
      translation: translation ?? this.translation,
      phonetic: phonetic ?? this.phonetic,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'text': text,
      'startMs': startMs,
      'endMs': endMs,
      'translation': translation,
      'phonetic': phonetic,
      'words': words?.map((LyricWord w) => w.toMap()).toList(),
    };
  }
}

enum LyricFormat {
  plainLrc,
  enhancedLrc,
  krc,
  yrcQrc,
  plainText,
}

class ParsedLyric {
  final List<LyricLine> lines;
  final LyricFormat format;
  final bool hasWordTiming;
  final int offsetMs;

  const ParsedLyric({
    required this.lines,
    required this.format,
    required this.hasWordTiming,
    this.offsetMs = 0,
  });

  int indexAt(int positionMs) {
    if (lines.isEmpty || positionMs < lines.first.startMs) {
      return -1;
    }

    int low = 0;
    int high = lines.length - 1;
    int result = -1;

    while (low <= high) {
      final int mid = low + ((high - low) >> 1);
      if (lines[mid].startMs <= positionMs) {
        result = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    return result;
  }

  Map<String, dynamic> toNativePayload({
    String songId = 'unknown',
    String songName = '',
    String artist = '',
    String album = '',
    int durationMs = 0,
    String rawSource = '',
  }) {
    final StringBuffer lrcBuffer = StringBuffer();
    final StringBuffer rawLyricBuffer = StringBuffer();
    final StringBuffer translationBuffer = StringBuffer();
    final StringBuffer romaBuffer = StringBuffer();

    bool anyWordTiming = hasWordTiming;

    for (final LyricLine line in lines) {
      final String tag = _formatLrcTag(line.startMs);
      lrcBuffer.writeln('$tag${line.text}');

      final List<LyricWord>? lineWords = line.words;
      if (lineWords != null && lineWords.isNotEmpty) {
        anyWordTiming = true;
        final int lineDur = line.endMs >= line.startMs ? line.endMs - line.startMs : 0;
        rawLyricBuffer.write('[${line.startMs},$lineDur]');
        for (final LyricWord word in lineWords) {
          final int wordDur = word.endMs >= word.startMs ? word.endMs - word.startMs : 0;
          rawLyricBuffer.write('<${word.startMs},$wordDur>${word.text}');
        }
        rawLyricBuffer.writeln();
      } else {
        rawLyricBuffer.writeln('$tag${line.text}');
      }

      final String? trans = line.translation;
      if (trans != null && trans.isNotEmpty) {
        translationBuffer.writeln('$tag$trans');
      }

      final String? roma = line.phonetic;
      if (roma != null && roma.isNotEmpty) {
        romaBuffer.writeln('$tag$roma');
      }
    }

    final String lrcText = lrcBuffer.toString().trimRight();
    final String rawLyric = anyWordTiming
        ? (rawLyricBuffer.isNotEmpty
            ? rawLyricBuffer.toString().trimRight()
            : rawSource.trimRight())
        : lrcText;

    return <String, dynamic>{
      'songId': songId,
      'songName': songName,
      'artist': artist,
      'album': album,
      'durationMs': durationMs,
      'lrcText': lrcText,
      'rawLyric': rawLyric,
      'translation': translationBuffer.toString().trimRight(),
      'roma': romaBuffer.toString().trimRight(),
      'hasWordTiming': anyWordTiming,
      'lines': lines.map((LyricLine line) => line.toMap()).toList(),
    };
  }

  static String _formatLrcTag(int ms) {
    final int clamped = ms < 0 ? 0 : ms;
    final int minutes = clamped ~/ 60000;
    final int seconds = (clamped % 60000) ~/ 1000;
    final int millis = clamped % 1000;
    final String mm = minutes.toString().padLeft(2, '0');
    final String ss = seconds.toString().padLeft(2, '0');
    final String sss = millis.toString().padLeft(3, '0');
    return '[$mm:$ss.$sss]';
  }
}
