import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:soda_pulse/lyrics/lyric_models.dart';

class KaraokeLyricView extends StatefulWidget {
  const KaraokeLyricView({
    super.key,
    required this.lyrics,
    required this.positionProvider,
    this.offsetMs = 0,
    this.onSeekToMs,
    this.accentColor = const Color(0xFF4CE0B3),
  });

  final ParsedLyric? lyrics;
  final int Function() positionProvider;
  final int offsetMs;
  final ValueChanged<int>? onSeekToMs;
  final Color accentColor;

  @override
  State<KaraokeLyricView> createState() => _KaraokeLyricViewState();
}

class _KaraokeLyricViewState extends State<KaraokeLyricView>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final ScrollController _scrollController;
  late final ValueNotifier<int> _positionNotifier;

  final Map<int, double> _itemHeights = <int, double>{};
  int _activeLineIndex = -1;
  bool _isUserScrolling = false;
  Timer? _resumeAutoScrollTimer;

  static const double _defaultItemExtent = 76.0;
  static const double _topPadding = 120.0;

  List<LyricLine> get _lines => widget.lyrics?.lines ?? const <LyricLine>[];

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _positionNotifier = ValueNotifier<int>(_effectivePositionMs());
    _activeLineIndex = _findActiveLineIndex(_positionNotifier.value);

    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(covariant KaraokeLyricView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lyrics != widget.lyrics) {
      _itemHeights.clear();
      final pos = _effectivePositionMs();
      _positionNotifier.value = pos;
      _activeLineIndex = _findActiveLineIndex(pos);
      if (_scrollController.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scrollToLine(_activeLineIndex, animate: false);
        });
      }
    }
  }

  @override
  void dispose() {
    _resumeAutoScrollTimer?.cancel();
    _ticker.dispose();
    _scrollController.dispose();
    _positionNotifier.dispose();
    super.dispose();
  }

  int _effectivePositionMs() {
    return widget.positionProvider() + widget.offsetMs;
  }

  void _onTick(Duration _) {
    if (!mounted) return;
    final pos = _effectivePositionMs();
    if (pos != _positionNotifier.value) {
      _positionNotifier.value = pos;
    }

    final nextIndex = _findActiveLineIndex(pos);
    if (nextIndex != _activeLineIndex) {
      setState(() {
        _activeLineIndex = nextIndex;
      });
      if (!_isUserScrolling && nextIndex >= 0) {
        _scrollToLine(nextIndex);
      }
    }
  }

  int _findActiveLineIndex(int posMs) {
    final lines = _lines;
    if (lines.isEmpty) return -1;
    if (posMs < lines.first.startMs) return 0;

    int low = 0;
    int high = lines.length - 1;
    int result = 0;

    while (low <= high) {
      final mid = (low + high) >> 1;
      if (lines[mid].startMs <= posMs) {
        result = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return result;
  }

  int _resolveLineEndMs(int index) {
    final lines = _lines;
    final line = lines[index];
    if (line.endMs > line.startMs) {
      return line.endMs;
    }
    if (index + 1 < lines.length) {
      return math.max(line.startMs + 1, lines[index + 1].startMs);
    }
    if (line.words != null && line.words!.isNotEmpty) {
      return math.max(line.startMs + 1, line.words!.last.endMs);
    }
    return line.startMs + 4000;
  }

  void _scrollToLine(int index, {bool animate = true}) {
    if (!_scrollController.hasClients || index < 0 || _lines.isEmpty) return;

    double targetOffset = _topPadding;
    for (int i = 0; i < index; i++) {
      targetOffset += _itemHeights[i] ?? _defaultItemExtent;
    }

    final viewportHeight = _scrollController.position.viewportDimension;
    final currentHeight = _itemHeights[index] ?? _defaultItemExtent;
    final centeredOffset =
        targetOffset - (viewportHeight * 0.36) + (currentHeight * 0.5);

    final clamped = centeredOffset.clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );

    if (animate) {
      _scrollController.animateTo(
        clamped,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scrollController.jumpTo(clamped);
    }
  }

  void _onUserDragStart() {
    if (!_isUserScrolling) {
      setState(() {
        _isUserScrolling = true;
      });
    }
    _resumeAutoScrollTimer?.cancel();
    _resumeAutoScrollTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() {
        _isUserScrolling = false;
      });
      if (_activeLineIndex >= 0) {
        _scrollToLine(_activeLineIndex);
      }
    });
  }

  void _jumpBackToCurrent() {
    _resumeAutoScrollTimer?.cancel();
    setState(() {
      _isUserScrolling = false;
    });
    if (_activeLineIndex >= 0) {
      _scrollToLine(_activeLineIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = _lines;
    if (lines.isEmpty) {
      return _EmptyLyricPlaceholder(accentColor: widget.accentColor);
    }

    return Stack(
      children: [
        ShaderMask(
          shaderCallback: (Rect bounds) {
            return const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Colors.transparent,
                Colors.white,
                Colors.white,
                Colors.transparent,
              ],
              stops: <double>[0.0, 0.1, 0.86, 1.0],
            ).createShader(bounds);
          },
          blendMode: BlendMode.dstIn,
          child: NotificationListener<ScrollNotification>(
            onNotification: (ScrollNotification notification) {
              if (notification is ScrollStartNotification &&
                  notification.dragDetails != null) {
                _onUserDragStart();
              } else if (notification is ScrollUpdateNotification &&
                  notification.dragDetails != null) {
                _onUserDragStart();
              }
              return false;
            },
            child: ListView.builder(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(
                top: _topPadding,
                bottom: 180.0,
                left: 24.0,
                right: 24.0,
              ),
              itemCount: lines.length,
              itemBuilder: (BuildContext context, int index) {
                final line = lines[index];
                final isActive = index == _activeLineIndex;
                final isPast = index < _activeLineIndex;
                final lineEndMs = _resolveLineEndMs(index);

                return _MeasuredItem(
                  onSizeChanged: (Size size) {
                    _itemHeights[index] = size.height;
                  },
                  child: _LyricLineItem(
                    line: line,
                    lineEndMs: lineEndMs,
                    isActive: isActive,
                    isPast: isPast,
                    positionListenable: _positionNotifier,
                    accentColor: widget.accentColor,
                    onTap: () {
                      widget.onSeekToMs?.call(line.startMs);
                      _resumeAutoScrollTimer?.cancel();
                      if (_isUserScrolling) {
                        setState(() {
                          _isUserScrolling = false;
                        });
                      }
                    },
                  ),
                );
              },
            ),
          ),
        ),
        Positioned(
          bottom: 20.0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            ignoring: !_isUserScrolling,
            child: AnimatedOpacity(
              opacity: _isUserScrolling ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 220),
              child: Center(
                child: GestureDetector(
                  onTap: _jumpBackToCurrent,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 8.0,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(24.0),
                      border: Border.all(
                        color: widget.accentColor.withValues(alpha: 0.45),
                        width: 1.0,
                      ),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: widget.accentColor.withValues(alpha: 0.18),
                          blurRadius: 16.0,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.my_location_rounded,
                          size: 15.0,
                          color: widget.accentColor,
                        ),
                        const SizedBox(width: 6.0),
                        const Text(
                          '回到当前',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LyricLineItem extends StatelessWidget {
  const _LyricLineItem({
    required this.line,
    required this.lineEndMs,
    required this.isActive,
    required this.isPast,
    required this.positionListenable,
    required this.accentColor,
    required this.onTap,
  });

  final LyricLine line;
  final int lineEndMs;
  final bool isActive;
  final bool isPast;
  final ValueNotifier<int> positionListenable;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasTranslation =
        line.translation != null && line.translation!.trim().isNotEmpty;

    final baseStyle = TextStyle(
      fontSize: isActive ? 23.0 : 18.0,
      height: 1.38,
      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
      letterSpacing: 0.2,
    );

    final inactiveColor = isPast
        ? Colors.white.withValues(alpha: 0.32)
        : Colors.white.withValues(alpha: 0.44);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 6.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (!isActive)
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 260),
                style: baseStyle.copyWith(color: inactiveColor),
                child: Text(line.text),
              )
            else
              ValueListenableBuilder<int>(
                valueListenable: positionListenable,
                builder: (BuildContext context, int posMs, _) {
                  final displayWords = resolveDisplayWords(
                    line,
                    fallbackEndMs: lineEndMs,
                  );
                  return Wrap(
                    alignment: WrapAlignment.start,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: displayWords.map((LyricWord word) {
                      return _KaraokeWordSweep(
                        word: word,
                        positionMs: posMs,
                        style: baseStyle,
                        accentColor: Colors.white,
                        baseColor: Colors.white.withValues(alpha: 0.36),
                      );
                    }).toList(growable: false),
                  );
                },
              ),
            if (hasTranslation) ...<Widget>[
              const SizedBox(height: 6.0),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 260),
                style: TextStyle(
                  fontSize: isActive ? 14.5 : 13.0,
                  height: 1.35,
                  fontWeight: isActive ? FontWeight.w500 : FontWeight.w400,
                  color: isActive
                      ? Colors.white.withValues(alpha: 0.76)
                      : Colors.white.withValues(alpha: 0.28),
                ),
                child: Text(line.translation!.trim()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _KaraokeWordSweep extends StatelessWidget {
  const _KaraokeWordSweep({
    required this.word,
    required this.positionMs,
    required this.style,
    required this.accentColor,
    required this.baseColor,
  });

  final LyricWord word;
  final int positionMs;
  final TextStyle style;
  final Color accentColor;
  final Color baseColor;

  @override
  Widget build(BuildContext context) {
    final duration = math.max(1, word.endMs - word.startMs);
    final double progress;
    if (positionMs <= word.startMs) {
      progress = 0.0;
    } else if (positionMs >= word.endMs) {
      progress = 1.0;
    } else {
      progress = (positionMs - word.startMs) / duration;
    }

    if (progress <= 0.0) {
      return Text(word.text, style: style.copyWith(color: baseColor));
    }
    if (progress >= 1.0) {
      return Text(word.text, style: style.copyWith(color: accentColor));
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final painter = TextPainter(
          text: TextSpan(text: word.text, style: style),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout(maxWidth: constraints.maxWidth);

        final wordWidth = math.max(1.0, painter.width);
        final sweepFraction =
            ((wordWidth * progress) / wordWidth).clamp(0.0, 1.0);
        const double feather = 0.10;
        final double stopStart = (sweepFraction - feather).clamp(0.0, 1.0);
        final double stopEnd = (sweepFraction + feather).clamp(0.0, 1.0);

        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (Rect bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: <Color>[
                accentColor,
                accentColor,
                baseColor,
                baseColor,
              ],
              stops: <double>[
                0.0,
                stopStart,
                stopEnd,
                1.0,
              ],
            ).createShader(Rect.fromLTWH(0, 0, wordWidth, bounds.height));
          },
          child: Text(
            word.text,
            style: style.copyWith(color: Colors.white),
          ),
        );
      },
    );
  }
}

// ignore: unused_element
class _WholeLineSweep extends StatelessWidget {
  const _WholeLineSweep({
    required this.text,
    required this.progress,
    required this.style,
    required this.accentColor,
    required this.baseColor,
  });

  final String text;
  final double progress;
  final TextStyle style;
  final Color accentColor;
  final Color baseColor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);

        final lineCount = painter.computeLineMetrics().length;
        if (lineCount > 1) {
          final highlighted = Color.lerp(baseColor, accentColor, progress)!;
          return Text(text, style: style.copyWith(color: highlighted));
        }

        final lineWidth = math.max(1.0, painter.width);
        const double feather = 0.08;
        final double stopStart = (progress - feather).clamp(0.0, 1.0);
        final double stopEnd = (progress + feather).clamp(0.0, 1.0);

        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (Rect bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: <Color>[
                accentColor,
                accentColor,
                baseColor,
                baseColor,
              ],
              stops: <double>[
                0.0,
                stopStart,
                stopEnd,
                1.0,
              ],
            ).createShader(Rect.fromLTWH(0, 0, lineWidth, bounds.height));
          },
          child: Text(
            text,
            style: style.copyWith(color: Colors.white),
          ),
        );
      },
    );
  }
}

class _MeasuredItem extends StatefulWidget {
  const _MeasuredItem({
    required this.onSizeChanged,
    required this.child,
  });

  final ValueChanged<Size> onSizeChanged;
  final Widget child;

  @override
  State<_MeasuredItem> createState() => _MeasuredItemState();
}

class _MeasuredItemState extends State<_MeasuredItem> {
  Size? _lastSize;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final renderObject = context.findRenderObject();
      if (renderObject is RenderBox && renderObject.hasSize) {
        final size = renderObject.size;
        if (_lastSize != size) {
          _lastSize = size;
          widget.onSizeChanged(size);
        }
      }
    });
    return widget.child;
  }
}

class _EmptyLyricPlaceholder extends StatelessWidget {
  const _EmptyLyricPlaceholder({required this.accentColor});

  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 56.0,
            height: 56.0,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accentColor.withValues(alpha: 0.12),
              border: Border.all(
                color: accentColor.withValues(alpha: 0.28),
              ),
            ),
            child: Icon(
              Icons.music_note_rounded,
              color: accentColor.withValues(alpha: 0.85),
              size: 26.0,
            ),
          ),
          const SizedBox(height: 14.0),
          Text(
            '暂无歌词 · 纯享时刻',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 14.5,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _LyricToken {
  String text;
  final bool isCjk;
  int nonSpaceChars;

  _LyricToken({
    required this.text,
    required this.isCjk,
    required this.nonSpaceChars,
  });

  double get weight {
    if (isCjk) return 1.0;
    return 0.52 * nonSpaceChars + 0.12;
  }
}

bool _isCjkRune(int rune) {
  return (rune >= 0x4E00 && rune <= 0x9FFF) || // CJK Unified Ideographs
      (rune >= 0x3400 && rune <= 0x4DBF) || // CJK Extension A
      (rune >= 0x3040 && rune <= 0x309F) || // Hiragana
      (rune >= 0x30A0 && rune <= 0x30FF) || // Katakana
      (rune >= 0xAC00 && rune <= 0xD7AF) || // Hangul Syllables
      (rune >= 0xF900 && rune <= 0xFAFF); // CJK Compatibility Ideographs
}

bool _isWhitespaceRune(int rune) {
  return rune == 0x20 ||
      rune == 0x09 ||
      rune == 0x0A ||
      rune == 0x0D ||
      rune == 0x3000;
}

bool _isPunctuationRune(int rune) {
  const String punctuation = '.,!?;:"()[]{}<>-—…，。！？；：、（）《》「」『』【】“”‘’~·';
  if (punctuation.codeUnits.contains(rune)) return true;
  // ASCII punctuation ranges excluding apostrophe (handled inline for contractions)
  return (rune >= 0x21 && rune <= 0x26) ||
      (rune >= 0x28 && rune <= 0x2F) ||
      (rune >= 0x3A && rune <= 0x40) ||
      (rune >= 0x5B && rune <= 0x60) ||
      (rune >= 0x7B && rune <= 0x7E);
}

List<LyricWord> resolveDisplayWords(LyricLine line, {int? fallbackEndMs}) {
  final existing = line.words;
  if (existing != null && existing.isNotEmpty) {
    return existing;
  }
  final String text = line.text;
  if (text.isEmpty) {
    return const <LyricWord>[];
  }

  final int totalDur = math.max(
    200,
    (((fallbackEndMs ?? line.endMs) - line.startMs) * 0.94).round(),
  );

  final List<_LyricToken> tokens = <_LyricToken>[];
  final List<int> runes = text.runes.toList(growable: false);
  final StringBuffer pendingLeadingSpaces = StringBuffer();
  int i = 0;

  while (i < runes.length) {
    final int rune = runes[i];

    if (_isWhitespaceRune(rune)) {
      final String ch = String.fromCharCode(rune);
      if (tokens.isNotEmpty) {
        tokens.last.text += ch;
      } else {
        pendingLeadingSpaces.write(ch);
      }
      i++;
      continue;
    }

    if (_isCjkRune(rune)) {
      final String prefix = pendingLeadingSpaces.toString();
      pendingLeadingSpaces.clear();
      tokens.add(
        _LyricToken(
          text: '$prefix${String.fromCharCode(rune)}',
          isCjk: true,
          nonSpaceChars: 1,
        ),
      );
      i++;
      continue;
    }

    if (_isPunctuationRune(rune)) {
      final String ch = String.fromCharCode(rune);
      if (tokens.isNotEmpty) {
        tokens.last.text += ch;
      } else {
        final String prefix = pendingLeadingSpaces.toString();
        pendingLeadingSpaces.clear();
        tokens.add(
          _LyricToken(
            text: '$prefix$ch',
            isCjk: false,
            nonSpaceChars: 1,
          ),
        );
      }
      i++;
      continue;
    }

    // Latin / digit / contraction word
    final StringBuffer wordBuf = StringBuffer();
    if (pendingLeadingSpaces.isNotEmpty) {
      wordBuf.write(pendingLeadingSpaces.toString());
      pendingLeadingSpaces.clear();
    }
    int nonSpaceCount = 0;

    while (i < runes.length) {
      final int r = runes[i];
      if (_isWhitespaceRune(r) || _isCjkRune(r) || _isPunctuationRune(r)) {
        break;
      }
      wordBuf.writeCharCode(r);
      nonSpaceCount++;
      i++;
    }

    // Attach trailing spaces directly to the Latin/digit token
    while (i < runes.length && _isWhitespaceRune(runes[i])) {
      wordBuf.writeCharCode(runes[i]);
      i++;
    }

    tokens.add(
      _LyricToken(
        text: wordBuf.toString(),
        isCjk: false,
        nonSpaceChars: nonSpaceCount,
      ),
    );
  }

  if (tokens.isEmpty) {
    return <LyricWord>[
      LyricWord(
        text: text,
        startMs: line.startMs,
        endMs: line.startMs + totalDur,
      ),
    ];
  }

  final double totalWeight = tokens.fold<double>(
    0.0,
    (double sum, _LyricToken t) => sum + t.weight,
  );

  final List<LyricWord> result = <LyricWord>[];
  int currentMs = line.startMs;
  double accumulatedWeight = 0.0;

  for (int idx = 0; idx < tokens.length; idx++) {
    final _LyricToken token = tokens[idx];
    final int startMs = currentMs;
    int endMs;

    if (idx == tokens.length - 1) {
      final int targetEnd = line.startMs + totalDur;
      endMs = targetEnd > startMs ? targetEnd : startMs + 1;
    } else {
      accumulatedWeight += token.weight;
      final double ratio = totalWeight > 0 ? accumulatedWeight / totalWeight : 1.0;
      final int targetEnd = line.startMs + (ratio * totalDur).round();
      endMs = targetEnd > startMs ? targetEnd : startMs + 1;
    }

    result.add(
      LyricWord(
        text: token.text,
        startMs: startMs,
        endMs: endMs,
      ),
    );
    currentMs = endMs;
  }

  return result;
}

class KaraokeSingleLineSweep extends StatelessWidget {
  final LyricLine line;
  final int positionMs;
  final TextStyle style;
  final Color activeColor;
  final Color inactiveColor;
  final Color? glowColor;

  const KaraokeSingleLineSweep({
    super.key,
    required this.line,
    required this.positionMs,
    required this.style,
    this.activeColor = Colors.white,
    this.inactiveColor = const Color(0x6BFFFFFF),
    this.glowColor,
  });

  @override
  Widget build(BuildContext context) {
    final List<LyricWord> words = resolveDisplayWords(line);
    if (words.isEmpty) {
      return Text(
        line.text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style.copyWith(color: inactiveColor),
      );
    }

    final List<Shadow>? activeShadows = glowColor != null
        ? <Shadow>[
            Shadow(
              color: glowColor!,
              blurRadius: 10,
            ),
          ]
        : style.shadows;

    final TextStyle activeStyle = style.copyWith(
      color: activeColor,
      shadows: activeShadows,
    );
    final TextStyle inactiveStyle = style.copyWith(
      color: inactiveColor,
    );
    final TextStyle maskBaseStyle = style.copyWith(
      color: Colors.white,
      shadows: activeShadows,
    );

    return ClipRect(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: words.map((LyricWord word) {
            final int duration = word.endMs - word.startMs;
            final double progress = duration <= 0
                ? (positionMs >= word.endMs ? 1.0 : 0.0)
                : ((positionMs - word.startMs) / duration).clamp(0.0, 1.0);

            if (progress <= 0.0) {
              return Text(
                word.text,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
                style: inactiveStyle,
              );
            }

            if (progress >= 1.0) {
              return Text(
                word.text,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
                style: activeStyle,
              );
            }

            final double featherStart = (progress - 0.02).clamp(0.0, 1.0);
            final double featherEnd = (progress + 0.02).clamp(0.0, 1.0);

            return ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (Rect bounds) {
                return LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: <Color>[
                    activeColor,
                    activeColor,
                    inactiveColor,
                    inactiveColor,
                  ],
                  stops: <double>[
                    0.0,
                    featherStart,
                    featherEnd,
                    1.0,
                  ],
                ).createShader(bounds);
              },
              child: Text(
                word.text,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
                style: maskBaseStyle,
              ),
            );
          }).toList(growable: false),
        ),
      ),
    );
  }
}

class RollingPreviewLyrics extends StatelessWidget {
  const RollingPreviewLyrics({
    super.key,
    required this.lines,
    required this.activeIndex,
    required this.positionMs,
    required this.accentColor,
    this.visibleLines = 5,
    this.scale = 1.0,
  });

  final List<LyricLine> lines;
  final int activeIndex;
  final int positionMs;
  final Color accentColor;
  final int visibleLines;
  final double scale;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty || activeIndex < 0) {
      return const SizedBox.shrink();
    }

    final double inactiveRowH = 22.0 * scale;
    final double activeRowH = 29.0 * scale;
    final int centerSlot = visibleLines ~/ 2;
    final double viewportH = (visibleLines - 1) * inactiveRowH + activeRowH;

    final int startIdx =
        (activeIndex - centerSlot - 1).clamp(0, lines.length - 1);
    final int endIdx =
        (activeIndex + centerSlot + 1).clamp(0, lines.length - 1);

    return ClipRect(
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (Rect bounds) {
          return const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: <double>[0.0, 0.14, 0.86, 1.0],
            colors: <Color>[
              Colors.transparent,
              Colors.white,
              Colors.white,
              Colors.transparent,
            ],
          ).createShader(bounds);
        },
        child: SizedBox(
          width: double.infinity,
          height: viewportH,
          child: Stack(
            children: <Widget>[
              for (int idx = startIdx; idx <= endIdx; idx++)
                _buildRow(
                  line: lines[idx],
                  idx: idx,
                  inactiveRowH: inactiveRowH,
                  activeRowH: activeRowH,
                  centerSlot: centerSlot,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow({
    required LyricLine line,
    required int idx,
    required double inactiveRowH,
    required double activeRowH,
    required int centerSlot,
  }) {
    final int rel = idx - activeIndex;
    final double rowHeight = rel == 0 ? activeRowH : inactiveRowH;
    final double rowTop = rel == 0
        ? centerSlot * inactiveRowH
        : (rel < 0
            ? (centerSlot + rel) * inactiveRowH
            : centerSlot * inactiveRowH +
                activeRowH +
                (rel - 1) * inactiveRowH);
    final double targetOpacity = rel.abs() > centerSlot
        ? 0.0
        : (rel == 0 ? 1.0 : (rel.abs() == 1 ? 0.56 : 0.42));

    final String trimmed = line.text.trim();
    final Widget content;
    if (trimmed.isEmpty) {
      content = const SizedBox.shrink();
    } else if (rel == 0) {
      content = KaraokeSingleLineSweep(
        line: line,
        positionMs: positionMs,
        style: TextStyle(
          fontSize: 17.5 * scale,
          fontWeight: FontWeight.w700,
          height: 1.28,
        ),
        activeColor: Colors.white,
        inactiveColor: Colors.white.withValues(alpha: 0.44),
        glowColor: accentColor.withValues(alpha: 0.45),
      );
    } else {
      content = Text(
        trimmed,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13.5 * scale,
          fontWeight: FontWeight.w400,
          color: Colors.white,
          height: 1.24,
        ),
      );
    }

    return AnimatedPositioned(
      key: ValueKey<int>(idx),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      left: 0,
      right: 0,
      top: rowTop,
      height: rowHeight,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeOutCubic,
        opacity: targetOpacity,
        child: Align(
          alignment: Alignment.centerLeft,
          child: content,
        ),
      ),
    );
  }
}
