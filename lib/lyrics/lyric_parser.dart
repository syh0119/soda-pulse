import 'lyric_models.dart';

class LyricParser {
  static final RegExp _offsetRegex = RegExp(
    r'^\[offset:\s*([+-]?\d+)\s*\]$',
    caseSensitive: false,
  );
  static final RegExp _metadataRegex = RegExp(
    r'^\[[a-zA-Z]+:.*\]$',
  );
  static final RegExp _lrcTagRegex = RegExp(
    r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]',
  );
  static final RegExp _enhancedWordTagRegex = RegExp(
    r'<(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?>',
  );
  static final RegExp _msLinePrefixRegex = RegExp(
    r'^\[(\d+),(\d+)\](.*)$',
  );
  static final RegExp _krcWordTagRegex = RegExp(
    r'<(\d+),(\d+)(?:,\d+)?>',
  );
  static final RegExp _yrcQrcWordTagRegex = RegExp(
    r'\((\d+),(\d+)(?:,\d+)?\)',
  );

  static ParsedLyric parse(
    String raw, {
    String? translationRaw,
    String? romaRaw,
    int durationMs = 0,
  }) {
    final _RawParseResult mainResult = _parseInternal(
      raw,
      durationMs: durationMs,
    );

    List<LyricLine> lines = mainResult.lines;

    if (translationRaw != null && translationRaw.trim().isNotEmpty && lines.isNotEmpty) {
      final _RawParseResult transResult = _parseInternal(
        translationRaw,
        durationMs: durationMs,
      );
      lines = _alignAuxiliaryLines(
        lines,
        transResult.lines,
        isTranslation: true,
      );
    }

    if (romaRaw != null && romaRaw.trim().isNotEmpty && lines.isNotEmpty) {
      final _RawParseResult romaResult = _parseInternal(
        romaRaw,
        durationMs: durationMs,
      );
      lines = _alignAuxiliaryLines(
        lines,
        romaResult.lines,
        isTranslation: false,
      );
    }

    return ParsedLyric(
      lines: lines,
      format: mainResult.format,
      hasWordTiming: mainResult.hasWordTiming,
      offsetMs: mainResult.offsetMs,
    );
  }

  static _RawParseResult _parseInternal(
    String raw, {
    required int durationMs,
  }) {
    final String normalized = raw
        .replaceFirst('\uFEFF', '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');

    if (normalized.trim().isEmpty) {
      return const _RawParseResult(
        lines: <LyricLine>[],
        format: LyricFormat.plainText,
        hasWordTiming: false,
        offsetMs: 0,
      );
    }

    final List<String> rawLines = normalized.split('\n');
    int offsetMs = 0;

    for (final String line in rawLines) {
      final String trimmed = line.trim();
      final Match? offsetMatch = _offsetRegex.firstMatch(trimmed);
      if (offsetMatch != null) {
        offsetMs = int.tryParse(offsetMatch.group(1)!) ?? 0;
        break;
      }
    }

    final List<_MutableLine> parsedLines = <_MutableLine>[];
    final List<String> plainTextCandidates = <String>[];
    int orderCounter = 0;

    bool sawKrc = false;
    bool sawYrcQrc = false;
    bool sawEnhancedLrc = false;
    bool sawPlainLrc = false;

    for (final String rawLine in rawLines) {
      final String trimmed = rawLine.trim();
      if (trimmed.isEmpty) {
        continue;
      }

      if (_offsetRegex.hasMatch(trimmed)) {
        continue;
      }

      final Match? msLineMatch = _msLinePrefixRegex.firstMatch(trimmed);
      if (msLineMatch != null) {
        final int lineStart = int.parse(msLineMatch.group(1)!);
        final int lineDur = int.parse(msLineMatch.group(2)!);
        final String body = msLineMatch.group(3) ?? '';

        if (_krcWordTagRegex.hasMatch(body)) {
          sawKrc = true;
          final List<LyricWord> words = _parseKrcWords(body, lineStart);
          final String text = words.map((LyricWord w) => w.text).join();
          parsedLines.add(
            _MutableLine(
              text: text,
              startMs: lineStart,
              endMs: lineStart + lineDur,
              hasExplicitEnd: true,
              words: words.isEmpty ? null : words,
              sourceOrder: orderCounter++,
            ),
          );
          continue;
        }

        if (_yrcQrcWordTagRegex.hasMatch(body)) {
          sawYrcQrc = true;
          final List<LyricWord> words = _parseYrcQrcWords(body);
          final String text = words.map((LyricWord w) => w.text).join();
          parsedLines.add(
            _MutableLine(
              text: text,
              startMs: lineStart,
              endMs: lineStart + lineDur,
              hasExplicitEnd: true,
              words: words.isEmpty ? null : words,
              sourceOrder: orderCounter++,
            ),
          );
          continue;
        }

        sawPlainLrc = true;
        parsedLines.add(
          _MutableLine(
            text: body,
            startMs: lineStart,
            endMs: lineStart + lineDur,
            hasExplicitEnd: true,
            sourceOrder: orderCounter++,
          ),
        );
        continue;
      }

      final List<Match> lrcMatches = _lrcTagRegex.allMatches(trimmed).toList();
      if (lrcMatches.isNotEmpty) {
        final int contentStart = lrcMatches.last.end;
        final String body = trimmed.substring(contentStart);

        if (_enhancedWordTagRegex.hasMatch(body)) {
          sawEnhancedLrc = true;
          for (final Match tag in lrcMatches) {
            final int lineStart = _parseLrcMatchMs(tag);
            final List<LyricWord> words = _parseEnhancedWords(body, lineStart);
            final String text = words.map((LyricWord w) => w.text).join();
            parsedLines.add(
              _MutableLine(
                text: text,
                startMs: lineStart,
                endMs: lineStart,
                hasExplicitEnd: false,
                words: words.isEmpty ? null : words,
                sourceOrder: orderCounter++,
              ),
            );
          }
        } else {
          sawPlainLrc = true;
          for (final Match tag in lrcMatches) {
            final int lineStart = _parseLrcMatchMs(tag);
            parsedLines.add(
              _MutableLine(
                text: body,
                startMs: lineStart,
                endMs: lineStart,
                hasExplicitEnd: false,
                sourceOrder: orderCounter++,
              ),
            );
          }
        }
        continue;
      }

      if (_metadataRegex.hasMatch(trimmed)) {
        continue;
      }

      plainTextCandidates.add(trimmed);
    }

    if (parsedLines.isEmpty && plainTextCandidates.isNotEmpty) {
      final int count = plainTextCandidates.length;
      final int stepMs = durationMs > 0 && count > 0
          ? (durationMs ~/ count).clamp(1000, 10000)
          : 4000;
      for (int i = 0; i < count; i++) {
        final int start = i * stepMs;
        final int end = (i == count - 1 && durationMs > start)
            ? durationMs
            : start + stepMs;
        parsedLines.add(
          _MutableLine(
            text: plainTextCandidates[i],
            startMs: start,
            endMs: end,
            hasExplicitEnd: true,
            sourceOrder: orderCounter++,
          ),
        );
      }

      return _RawParseResult(
        lines: _finalizeLines(parsedLines, offsetMs: 0, durationMs: durationMs),
        format: LyricFormat.plainText,
        hasWordTiming: false,
        offsetMs: offsetMs,
      );
    }

    final LyricFormat format;
    if (sawKrc) {
      format = LyricFormat.krc;
    } else if (sawYrcQrc) {
      format = LyricFormat.yrcQrc;
    } else if (sawEnhancedLrc) {
      format = LyricFormat.enhancedLrc;
    } else if (sawPlainLrc) {
      format = LyricFormat.plainLrc;
    } else {
      format = LyricFormat.plainText;
    }

    final List<LyricLine> finalLines = _finalizeLines(
      parsedLines,
      offsetMs: offsetMs,
      durationMs: durationMs,
    );

    final bool hasWordTiming = finalLines.any(
      (LyricLine line) => line.words != null && line.words!.isNotEmpty,
    );

    return _RawParseResult(
      lines: finalLines,
      format: format,
      hasWordTiming: hasWordTiming,
      offsetMs: offsetMs,
    );
  }

  static List<LyricLine> _finalizeLines(
    List<_MutableLine> rawLines, {
    required int offsetMs,
    required int durationMs,
  }) {
    if (rawLines.isEmpty) {
      return const <LyricLine>[];
    }

    for (final _MutableLine line in rawLines) {
      final int shiftedStart = (line.startMs + offsetMs) < 0 ? 0 : (line.startMs + offsetMs);
      final int shiftedEnd = (line.endMs + offsetMs) < shiftedStart
          ? shiftedStart
          : (line.endMs + offsetMs);

      line.startMs = shiftedStart;
      line.endMs = shiftedEnd;

      if (line.words != null && offsetMs != 0) {
        line.words = line.words!.map((LyricWord w) {
          final int wStart = (w.startMs + offsetMs) < 0 ? 0 : (w.startMs + offsetMs);
          final int wEnd = w.endMs < 0
              ? -1
              : ((w.endMs + offsetMs) < wStart ? wStart : (w.endMs + offsetMs));
          return LyricWord(text: w.text, startMs: wStart, endMs: wEnd);
        }).toList();
      }
    }

    rawLines.sort((_MutableLine a, _MutableLine b) => a.startMs.compareTo(b.startMs));

    // Merge duplicate/near-timestamp lines (bilingual LRC within 150ms: earlier sourceOrder is main).
    final List<_MutableLine> merged = <_MutableLine>[];
    for (final _MutableLine current in rawLines) {
      if (merged.isNotEmpty &&
          (current.startMs - merged.last.startMs).abs() <= 150) {
        final _MutableLine prev = merged.last;
        if (current.sourceOrder < prev.sourceOrder) {
          final String oldMain = prev.text.trim();
          prev.text = current.text;
          prev.startMs = current.startMs;
          prev.sourceOrder = current.sourceOrder;
          if (oldMain.isNotEmpty) {
            prev.translation = oldMain;
          }
        } else {
          final String candidateText = current.text.trim();
          if (candidateText.isNotEmpty) {
            if (prev.translation == null || prev.translation!.isEmpty) {
              prev.translation = candidateText;
            } else if (prev.phonetic == null || prev.phonetic!.isEmpty) {
              prev.phonetic = candidateText;
            }
          }
        }
        if ((prev.words == null || prev.words!.isEmpty) &&
            current.words != null &&
            current.words!.isNotEmpty) {
          prev.words = current.words;
        }
        if (!prev.hasExplicitEnd && current.hasExplicitEnd) {
          prev.endMs = current.endMs;
          prev.hasExplicitEnd = true;
        }
      } else {
        merged.add(current);
      }
    }

    final List<LyricLine> result = <LyricLine>[];
    for (int i = 0; i < merged.length; i++) {
      final _MutableLine line = merged[i];
      int resolvedEnd;
      if (line.hasExplicitEnd && line.endMs >= line.startMs) {
        resolvedEnd = line.endMs;
      } else if (i + 1 < merged.length && merged[i + 1].startMs >= line.startMs) {
        resolvedEnd = merged[i + 1].startMs;
      } else if (durationMs > line.startMs) {
        resolvedEnd = durationMs;
      } else {
        resolvedEnd = line.startMs + 4000;
      }

      if (resolvedEnd < line.startMs) {
        resolvedEnd = line.startMs;
      }

      List<LyricWord>? cleanedWords;
      if (line.words != null && line.words!.isNotEmpty) {
        final List<LyricWord> sortedWords = line.words!.map((LyricWord w) {
          final int wStart = w.startMs < 0 ? 0 : w.startMs;
          int wEnd = w.endMs < 0 ? resolvedEnd : w.endMs;
          if (wEnd < wStart) {
            wEnd = wStart;
          }
          return LyricWord(text: w.text, startMs: wStart, endMs: wEnd);
        }).toList()
          ..sort((LyricWord a, LyricWord b) => a.startMs.compareTo(b.startMs));

        cleanedWords = sortedWords;
      }

      if (line.text.trim().isEmpty) {
        continue;
      }

      result.add(
        LyricLine(
          text: line.text,
          startMs: line.startMs,
          endMs: resolvedEnd,
          words: cleanedWords,
          translation: line.translation,
          phonetic: line.phonetic,
        ),
      );
    }

    return result;
  }

  static List<LyricLine> _alignAuxiliaryLines(
    List<LyricLine> mainLines,
    List<LyricLine> auxLines, {
    required bool isTranslation,
  }) {
    if (auxLines.isEmpty) {
      return mainLines;
    }

    const int windowMs = 150;
    final List<bool> usedAux = List<bool>.filled(auxLines.length, false);
    final List<LyricLine> updated = <LyricLine>[];

    for (final LyricLine mainLine in mainLines) {
      int bestIdx = -1;
      int bestDiff = windowMs + 1;

      for (int i = 0; i < auxLines.length; i++) {
        if (usedAux[i]) continue;
        final int diff = (auxLines[i].startMs - mainLine.startMs).abs();
        if (diff <= windowMs && diff < bestDiff) {
          bestDiff = diff;
          bestIdx = i;
        }
      }

      if (bestIdx != -1) {
        usedAux[bestIdx] = true;
        final String auxText = auxLines[bestIdx].text.trim();
        if (auxText.isNotEmpty) {
          updated.add(
            isTranslation
                ? mainLine.copyWith(translation: auxText)
                : mainLine.copyWith(phonetic: auxText),
          );
          continue;
        }
      }

      updated.add(mainLine);
    }

    return updated;
  }

  static int _parseLrcMatchMs(Match match) {
    final int minutes = int.parse(match.group(1)!);
    final int seconds = int.parse(match.group(2)!);
    final String? frac = match.group(3);
    int fracMs = 0;
    if (frac != null) {
      if (frac.length == 1) {
        fracMs = int.parse(frac) * 100;
      } else if (frac.length == 2) {
        fracMs = int.parse(frac) * 10;
      } else {
        fracMs = int.parse(frac);
      }
    }
    return minutes * 60000 + seconds * 1000 + fracMs;
  }

  static List<LyricWord> _parseEnhancedWords(String body, int lineStartMs) {
    final List<Match> matches = _enhancedWordTagRegex.allMatches(body).toList();
    if (matches.isEmpty) {
      return const <LyricWord>[];
    }

    final List<LyricWord> words = <LyricWord>[];
    final int firstTagMs = _parseLrcMatchMs(matches.first);
    if (matches.first.start > 0) {
      final String prefix = body.substring(0, matches.first.start);
      if (prefix.isNotEmpty) {
        words.add(
          LyricWord(
            text: prefix,
            startMs: lineStartMs,
            endMs: firstTagMs >= lineStartMs ? firstTagMs : lineStartMs,
          ),
        );
      }
    }

    for (int i = 0; i < matches.length; i++) {
      final Match current = matches[i];
      final int startMs = _parseLrcMatchMs(current);
      final int textEnd = i + 1 < matches.length ? matches[i + 1].start : body.length;
      final String wordText = body.substring(current.end, textEnd);
      if (wordText.isEmpty) {
        continue;
      }
      final int endMs = i + 1 < matches.length ? _parseLrcMatchMs(matches[i + 1]) : -1;
      words.add(
        LyricWord(
          text: wordText,
          startMs: startMs,
          endMs: endMs,
        ),
      );
    }

    return words;
  }

  static List<LyricWord> _parseKrcWords(String body, int lineStartMs) {
    final List<Match> matches = _krcWordTagRegex.allMatches(body).toList();
    if (matches.isEmpty) {
      return const <LyricWord>[];
    }

    final List<LyricWord> words = <LyricWord>[];
    for (int i = 0; i < matches.length; i++) {
      final Match current = matches[i];
      final int offsetMs = int.parse(current.group(1)!);
      final int durMs = int.parse(current.group(2)!);
      final int textEnd = i + 1 < matches.length ? matches[i + 1].start : body.length;
      final String wordText = body.substring(current.end, textEnd);
      if (wordText.isEmpty) {
        continue;
      }
      final int wordStart = lineStartMs + offsetMs;
      words.add(
        LyricWord(
          text: wordText,
          startMs: wordStart,
          endMs: wordStart + durMs,
        ),
      );
    }
    return words;
  }

  static List<LyricWord> _parseYrcQrcWords(String body) {
    final List<Match> matches = _yrcQrcWordTagRegex.allMatches(body).toList();
    if (matches.isEmpty) {
      return const <LyricWord>[];
    }

    final bool tagFirst = body.trimLeft().startsWith('(') && matches.first.start == body.indexOf('(');
    final List<LyricWord> words = <LyricWord>[];

    if (tagFirst) {
      for (int i = 0; i < matches.length; i++) {
        final Match current = matches[i];
        final int startMs = int.parse(current.group(1)!);
        final int durMs = int.parse(current.group(2)!);
        final int textEnd = i + 1 < matches.length ? matches[i + 1].start : body.length;
        final String wordText = body.substring(current.end, textEnd);
        if (wordText.isEmpty) {
          continue;
        }
        words.add(
          LyricWord(
            text: wordText,
            startMs: startMs,
            endMs: startMs + durMs,
          ),
        );
      }
    } else {
      int prevEnd = 0;
      for (final Match current in matches) {
        final String wordText = body.substring(prevEnd, current.start);
        prevEnd = current.end;
        if (wordText.isEmpty) {
          continue;
        }
        final int startMs = int.parse(current.group(1)!);
        final int durMs = int.parse(current.group(2)!);
        words.add(
          LyricWord(
            text: wordText,
            startMs: startMs,
            endMs: startMs + durMs,
          ),
        );
      }
    }

    return words;
  }

  static ParsedLyric demoLyrics() {
    const List<LyricLine> demoLines = <LyricLine>[
      LyricLine(
        text: '星光落入微风的夜里',
        startMs: 0,
        endMs: 4000,
        translation: 'Starlight falls into the breezy night',
        phonetic: 'xīng guāng luò rù wēi fēng de yè lǐ',
        words: <LyricWord>[
          LyricWord(text: '星', startMs: 0, endMs: 450),
          LyricWord(text: '光', startMs: 450, endMs: 900),
          LyricWord(text: '落', startMs: 900, endMs: 1350),
          LyricWord(text: '入', startMs: 1350, endMs: 1750),
          LyricWord(text: '微', startMs: 1750, endMs: 2200),
          LyricWord(text: '风', startMs: 2200, endMs: 2650),
          LyricWord(text: '的', startMs: 2650, endMs: 3000),
          LyricWord(text: '夜', startMs: 3000, endMs: 3500),
          LyricWord(text: '里', startMs: 3500, endMs: 4000),
        ],
      ),
      LyricLine(
        text: '旋律在指尖轻轻苏醒',
        startMs: 4000,
        endMs: 8000,
        translation: 'Melodies gently awaken at my fingertips',
        phonetic: 'xuán lǜ zài zhǐ jiān qīng qīng sū xǐng',
        words: <LyricWord>[
          LyricWord(text: '旋', startMs: 4000, endMs: 4450),
          LyricWord(text: '律', startMs: 4450, endMs: 4900),
          LyricWord(text: '在', startMs: 4900, endMs: 5300),
          LyricWord(text: '指', startMs: 5300, endMs: 5750),
          LyricWord(text: '尖', startMs: 5750, endMs: 6200),
          LyricWord(text: '轻', startMs: 6200, endMs: 6650),
          LyricWord(text: '轻', startMs: 6650, endMs: 7100),
          LyricWord(text: '苏', startMs: 7100, endMs: 7550),
          LyricWord(text: '醒', startMs: 7550, endMs: 8000),
        ],
      ),
      LyricLine(
        text: '跨越山海去听见你的声音',
        startMs: 8000,
        endMs: 12500,
        translation: 'Crossing mountains and seas to hear your voice',
        phonetic: 'kuà yuè shān hǎi qù tīng jiàn nǐ de shēng yīn',
        words: <LyricWord>[
          LyricWord(text: '跨', startMs: 8000, endMs: 8400),
          LyricWord(text: '越', startMs: 8400, endMs: 8800),
          LyricWord(text: '山', startMs: 8800, endMs: 9250),
          LyricWord(text: '海', startMs: 9250, endMs: 9700),
          LyricWord(text: '去', startMs: 9700, endMs: 10050),
          LyricWord(text: '听', startMs: 10050, endMs: 10500),
          LyricWord(text: '见', startMs: 10500, endMs: 10900),
          LyricWord(text: '你', startMs: 10900, endMs: 11250),
          LyricWord(text: '的', startMs: 11250, endMs: 11600),
          LyricWord(text: '声', startMs: 11600, endMs: 12050),
          LyricWord(text: '音', startMs: 12050, endMs: 12500),
        ],
      ),
      LyricLine(
        text: '每一秒心跳都与节拍共鸣',
        startMs: 12500,
        endMs: 17000,
        translation: 'Every heartbeat resonates with the rhythm',
        phonetic: 'měi yī miǎo xīn tiào dōu yǔ jié pāi gòng míng',
        words: <LyricWord>[
          LyricWord(text: '每', startMs: 12500, endMs: 12900),
          LyricWord(text: '一', startMs: 12900, endMs: 13250),
          LyricWord(text: '秒', startMs: 13250, endMs: 13700),
          LyricWord(text: '心', startMs: 13700, endMs: 14150),
          LyricWord(text: '跳', startMs: 14150, endMs: 14600),
          LyricWord(text: '都', startMs: 14600, endMs: 15000),
          LyricWord(text: '与', startMs: 15000, endMs: 15350),
          LyricWord(text: '节', startMs: 15350, endMs: 15750),
          LyricWord(text: '拍', startMs: 15750, endMs: 16150),
          LyricWord(text: '共', startMs: 16150, endMs: 16550),
          LyricWord(text: '鸣', startMs: 16550, endMs: 17000),
        ],
      ),
      LyricLine(
        text: '即使黎明未至仍有光同行',
        startMs: 17000,
        endMs: 20500,
        translation: 'Even before dawn arrives, light walks beside us',
        phonetic: 'jí shǐ lí míng wèi zhì réng yǒu guāng tóng xíng',
        words: <LyricWord>[
          LyricWord(text: '即', startMs: 17000, endMs: 17350),
          LyricWord(text: '使', startMs: 17350, endMs: 17700),
          LyricWord(text: '黎', startMs: 17700, endMs: 18050),
          LyricWord(text: '明', startMs: 18050, endMs: 18450),
          LyricWord(text: '未', startMs: 18450, endMs: 18800),
          LyricWord(text: '至', startMs: 18800, endMs: 19150),
          LyricWord(text: '仍', startMs: 19150, endMs: 19450),
          LyricWord(text: '有', startMs: 19450, endMs: 19750),
          LyricWord(text: '光', startMs: 19750, endMs: 20050),
          LyricWord(text: '同', startMs: 20050, endMs: 20275),
          LyricWord(text: '行', startMs: 20275, endMs: 20500),
        ],
      ),
      LyricLine(
        text: '把此刻唱成永恒的风景',
        startMs: 20500,
        endMs: 24000,
        translation: 'Singing this moment into an eternal scenery',
        phonetic: 'bǎ cǐ kè chàng chéng yǒng héng de fēng jǐng',
        words: <LyricWord>[
          LyricWord(text: '把', startMs: 20500, endMs: 20850),
          LyricWord(text: '此', startMs: 20850, endMs: 21200),
          LyricWord(text: '刻', startMs: 21200, endMs: 21550),
          LyricWord(text: '唱', startMs: 21550, endMs: 21950),
          LyricWord(text: '成', startMs: 21950, endMs: 22300),
          LyricWord(text: '永', startMs: 22300, endMs: 22700),
          LyricWord(text: '恒', startMs: 22700, endMs: 23100),
          LyricWord(text: '的', startMs: 23100, endMs: 23400),
          LyricWord(text: '风', startMs: 23400, endMs: 23700),
          LyricWord(text: '景', startMs: 23700, endMs: 24000),
        ],
      ),
    ];

    return const ParsedLyric(
      lines: demoLines,
      format: LyricFormat.enhancedLrc,
      hasWordTiming: true,
      offsetMs: 0,
    );
  }
}

class _RawParseResult {
  final List<LyricLine> lines;
  final LyricFormat format;
  final bool hasWordTiming;
  final int offsetMs;

  const _RawParseResult({
    required this.lines,
    required this.format,
    required this.hasWordTiming,
    required this.offsetMs,
  });
}

class _MutableLine {
  String text;
  int startMs;
  int endMs;
  bool hasExplicitEnd;
  List<LyricWord>? words;
  String? translation;
  String? phonetic;
  int sourceOrder;

  _MutableLine({
    required this.text,
    required this.startMs,
    required this.endMs,
    required this.hasExplicitEnd,
    this.words,
    required this.sourceOrder,
  });
}
