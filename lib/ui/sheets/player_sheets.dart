import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:soda_pulse/core/app_store.dart';
import 'package:soda_pulse/ui/pages/drive_page.dart';
import 'package:soda_pulse/core/daily_copy.dart';
import 'package:soda_pulse/models/track.dart';
import 'package:soda_pulse/ui/theme/soda_theme.dart';

const Color _sheetBg = Color(0xFF121826);

Future<T?> _showSodaSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (sheetContext) {
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: BoxDecoration(
              color: _sheetBg.withValues(alpha: 0.92),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              border: Border(
                top: BorderSide(
                  color: Colors.white.withValues(alpha: 0.12),
                  width: 1,
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: builder(sheetContext),
            ),
          ),
        ),
      );
    },
  );
}

Widget _sheetHandle() {
  return Center(
    child: Container(
      margin: const EdgeInsets.only(top: 12, bottom: 14),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

Widget _sheetHeader(String title, {Widget? trailing}) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ),
        if (trailing != null) trailing,
      ],
    ),
  );
}

Color _accentOf(BuildContext context) {
  return Theme.of(context).colorScheme.primary;
}

Future<void> showQueueSheet(BuildContext context, AppStore store) {
  return _showSodaSheet<void>(
    context: context,
    builder: (sheetContext) {
      final accent = _accentOf(sheetContext);
      final maxHeight = MediaQuery.of(sheetContext).size.height * 0.65;
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: ListenableBuilder(
          listenable: store,
          builder: (ctx, child) {
            final queue = store.queue;
            final currentId = store.currentTrack?.id;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _sheetHandle(),
                _sheetHeader('待播列表 (${queue.length})'),
                if (queue.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Text(
                      '暂无待播歌曲',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 14,
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      itemCount: queue.length,
                      itemBuilder: (itemContext, index) {
                        final track = queue[index];
                        final isCurrent = currentId == track.id;
                        final localCoverPath = store.coverPathFor(track);
                        if (!track.isOnlinePluginTrack &&
                            localCoverPath == null &&
                            (track.albumArtUri?.isNotEmpty ?? false)) {
                          WidgetsBinding.instance.addPostFrameCallback(
                            (_) => store.ensureCoverLoaded(track),
                          );
                        }
                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          decoration: BoxDecoration(
                            color: isCurrent
                                ? accent.withValues(alpha: 0.16)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            leading: SizedBox(
                              width: 44,
                              height: 44,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  CoverArtWidget(
                                    track: track,
                                    localPath: localCoverPath,
                                    accentColor: accent,
                                    size: 44,
                                    borderRadius: 10,
                                  ),
                                  if (isCurrent)
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: ColoredBox(
                                        color: Colors.black.withValues(alpha: 0.45),
                                        child: Icon(
                                          Icons.equalizer_rounded,
                                          color: accent,
                                          size: 22,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            title: Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isCurrent ? accent : Colors.white,
                                fontWeight: isCurrent
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                fontSize: 15,
                              ),
                            ),
                            subtitle: Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isCurrent
                                    ? accent.withValues(alpha: 0.8)
                                    : Colors.white.withValues(alpha: 0.55),
                                fontSize: 12,
                              ),
                            ),
                            onTap: () {
                              store.playTrackFromQueue(index);
                              Navigator.of(sheetContext).pop();
                            },
                          ),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      );
    },
  );
}

Future<void> showAudioQualitySheet(BuildContext context, AppStore store) {
  return _showSodaSheet<void>(
    context: context,
    builder: (sheetContext) {
      final accent = _accentOf(sheetContext);
      return ListenableBuilder(
        listenable: store,
        builder: (ctx, child) {
          final currentQuality = store.preferredQuality;
          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sheetHandle(),
                  _sheetHeader('切换音质 · 实时生效'),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Text(
                      '支持 128k / 320k / FLAC，切换后在线曲目将自动重新解析',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.58),
                        fontSize: 12,
                      ),
                    ),
                  ),
                  ...AudioQualityOptions.all.map((option) {
                    final selected = option.id == currentQuality;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            store.setPreferredQuality(option.id);
                            Navigator.of(sheetContext).pop();
                            ScaffoldMessenger.of(context)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(
                                SnackBar(
                                  content: Text('已切换至${option.title}'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                          },
                          child: Ink(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              color: selected
                                  ? accent.withValues(alpha: 0.14)
                                  : Colors.white.withValues(alpha: 0.06),
                              border: Border.all(
                                color: selected
                                    ? accent.withValues(alpha: 0.6)
                                    : Colors.white.withValues(alpha: 0.1),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 28,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    color: selected
                                        ? accent.withValues(alpha: 0.22)
                                        : Colors.white.withValues(alpha: 0.1),
                                    border: Border.all(
                                      color: selected
                                          ? accent.withValues(alpha: 0.55)
                                          : Colors.white.withValues(alpha: 0.12),
                                    ),
                                  ),
                                  child: Text(
                                    option.badge,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: selected ? accent : Colors.white70,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        option.title,
                                        style: TextStyle(
                                          color: selected ? accent : Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        option.subtitle,
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.55),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (selected)
                                  Icon(
                                    Icons.check_circle_rounded,
                                    color: accent,
                                    size: 22,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

Future<void> showSoundEffectSheet(BuildContext context, AppStore store) {
  const bandLabels = ['60Hz', '230Hz', '910Hz', '3.6kHz', '14kHz'];
  return _showSodaSheet<void>(
    context: context,
    builder: (sheetContext) {
      final accent = _accentOf(sheetContext);
      final maxHeight = MediaQuery.of(sheetContext).size.height * 0.8;
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: ListenableBuilder(
          listenable: store,
          builder: (ctx, child) {
            final gains = List<double>.from(store.eqGains);
            final preGain = store.eqPreGain;
            return SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sheetHandle(),
                  _sheetHeader('品牌调音 · 实时生效'),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Text(
                      '峰值包络限幅防爆音 · 5 段参数均衡实时生效',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    const Text(
                                      '响度平衡',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: accent.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '-14 LUFS',
                                        style: TextStyle(
                                          color: accent,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '自动拉齐不同音源与歌曲的音量差 · 防爆音限幅',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.55),
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Switch(
                            value: store.loudnessNormEnabled,
                            onChanged: store.setLoudnessNormEnabled,
                            activeThumbColor: accent,
                            activeTrackColor: accent.withValues(alpha: 0.42),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: SoundFxPresets.all.map((preset) {
                        final selected = store.eqPresetId == preset.id;
                        return FilterChip(
                          label: Text(preset.name),
                          selected: selected,
                          showCheckmark: false,
                          labelStyle: TextStyle(
                            color: selected
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.78),
                            fontSize: 13,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w400,
                          ),
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                          selectedColor: accent.withValues(alpha: 0.35),
                          side: BorderSide(
                            color: selected
                                ? accent
                                : Colors.white.withValues(alpha: 0.12),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          onSelected: (isSelected) {
                            store.applyEqPreset(preset.id);
                          },
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...List.generate(bandLabels.length, (index) {
                    final value = index < gains.length
                        ? gains[index].clamp(-12.0, 12.0)
                        : 0.0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 54,
                            child: Text(
                              bandLabels[index],
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.78),
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Slider(
                              value: value,
                              min: -12,
                              max: 12,
                              divisions: 48,
                              activeColor: accent,
                              inactiveColor:
                                  Colors.white.withValues(alpha: 0.15),
                              onChanged: (newVal) {
                                final updated = List<double>.from(gains);
                                while (updated.length < bandLabels.length) {
                                  updated.add(0.0);
                                }
                                updated[index] = newVal;
                                store.setCustomEq(updated, preGain);
                              },
                            ),
                          ),
                          SizedBox(
                            width: 56,
                            child: Text(
                              '${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)}dB',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.65),
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 54,
                          child: Text(
                            '前级',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Slider(
                            value: preGain.clamp(-12.0, 6.0),
                            min: -12,
                            max: 6,
                            divisions: 36,
                            activeColor: accent,
                            inactiveColor:
                                Colors.white.withValues(alpha: 0.15),
                            onChanged: (newVal) {
                              store.setCustomEq(gains, newVal);
                            },
                          ),
                        ),
                        SizedBox(
                          width: 56,
                          child: Text(
                            '${preGain >= 0 ? '+' : ''}${preGain.toStringAsFixed(1)}dB',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    },
  );
}

Future<void> showSleepAndSpeedSheet(BuildContext context, AppStore store) {
  const sleepOptions = [
    (label: '关闭', minutes: 0),
    (label: '15分钟', minutes: 15),
    (label: '30分钟', minutes: 30),
    (label: '45分钟', minutes: 45),
    (label: '60分钟', minutes: 60),
  ];
  const speedOptions = [0.75, 1.0, 1.25, 1.5, 2.0];

  return _showSodaSheet<void>(
    context: context,
    builder: (sheetContext) {
      final accent = _accentOf(sheetContext);
      return ListenableBuilder(
        listenable: store,
        builder: (ctx, child) {
          final speed = store.playbackSpeed.clamp(0.5, 2.0);
          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sheetHandle(),
                _sheetHeader('定时关闭与倍速'),
                if (store.sleepTimerRemaining != null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: SizedBox(
                        width: 108,
                        height: 108,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 100,
                              height: 100,
                              child: CircularProgressIndicator(
                                value: store.sleepTimerProgress,
                                strokeWidth: 6,
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.12),
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(accent),
                              ),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${store.sleepTimerRemaining!.inMinutes.toString().padLeft(2, '0')}:${(store.sleepTimerRemaining!.inSeconds % 60).toString().padLeft(2, '0')}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  '剩余时间',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.55),
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                  child: Text(
                    '定时关闭',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ...sleepOptions.map((option) {
                        final selected = option.minutes == 0
                            ? store.sleepTimerRemaining == null
                            : store.sleepTimerTotal?.inMinutes == option.minutes;
                        return ChoiceChip(
                          label: Text(option.label),
                          selected: selected,
                          showCheckmark: false,
                          labelStyle: TextStyle(
                            color: selected
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.78),
                            fontSize: 13,
                          ),
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                          selectedColor: accent.withValues(alpha: 0.35),
                          side: BorderSide(
                            color: selected
                                ? accent
                                : Colors.white.withValues(alpha: 0.12),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          onSelected: (isSelected) {
                            store.setSleepTimer(
                              option.minutes <= 0
                                  ? null
                                  : Duration(minutes: option.minutes),
                            );
                          },
                        );
                      }),
                      ActionChip(
                        label: const Text('自定义'),
                        labelStyle: TextStyle(
                          color: accent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        backgroundColor: accent.withValues(alpha: 0.14),
                        side: BorderSide(color: accent.withValues(alpha: 0.45)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        onPressed: () async {
                          final ctrl = TextEditingController();
                          final mins = await showDialog<int>(
                            context: sheetContext,
                            builder: (dCtx) => AlertDialog(
                              backgroundColor: _sheetBg,
                              title: const Text(
                                '自定义定时（分钟）',
                                style: TextStyle(color: Colors.white),
                              ),
                              content: TextField(
                                controller: ctrl,
                                keyboardType: TextInputType.number,
                                autofocus: true,
                                style: const TextStyle(color: Colors.white),
                                decoration: const InputDecoration(
                                  hintText: '1 ~ 240',
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(dCtx).pop(),
                                  child: const Text('取消'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    final v = int.tryParse(ctrl.text.trim());
                                    if (v != null && v > 0 && v <= 240) {
                                      Navigator.of(dCtx).pop(v);
                                    }
                                  },
                                  child: Text('确定', style: TextStyle(color: accent)),
                                ),
                              ],
                            ),
                          );
                          ctrl.dispose();
                          if (mins != null) {
                            store.setSleepTimer(Duration(minutes: mins));
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  activeThumbColor: accent,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  title: const Text(
                    '播完当前单曲后暂停',
                    style: TextStyle(color: Colors.white, fontSize: 15),
                  ),
                  value: store.stopAfterCurrent,
                  onChanged: store.setStopAfterCurrent,
                ),
                const Divider(color: Colors.white12, height: 24),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '播放倍速',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${speed.toStringAsFixed(2)}x',
                        style: TextStyle(
                          color: accent,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Slider(
                    value: speed,
                    min: 0.5,
                    max: 2.0,
                    divisions: 30,
                    activeColor: accent,
                    inactiveColor: Colors.white.withValues(alpha: 0.15),
                    onChanged: store.setPlaybackSpeed,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: speedOptions.map((val) {
                      final selected = (speed - val).abs() < 0.01;
                      return ChoiceChip(
                        label: Text('${val}x'),
                        selected: selected,
                        showCheckmark: false,
                        labelStyle: TextStyle(
                          color: selected
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.78),
                          fontSize: 13,
                        ),
                        backgroundColor: Colors.white.withValues(alpha: 0.08),
                        selectedColor: accent.withValues(alpha: 0.35),
                        side: BorderSide(
                          color: selected
                              ? accent
                              : Colors.white.withValues(alpha: 0.12),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        onSelected: (isSelected) {
                          store.setPlaybackSpeed(val);
                        },
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

Future<void> showSmartRecommendSheet(BuildContext context, AppStore store) {
  const modeMeta = [
    (title: '默认模式', desc: '均衡推荐熟悉旋律与新鲜发现，保持顺滑听感'),
    (title: '熟悉模式', desc: '优先播放红心收藏与高频循环的偏爱曲目'),
    (title: '新鲜模式', desc: '更多探索未听过的新歌与小众宝藏作品'),
  ];

  return _showSodaSheet<void>(
    context: context,
    builder: (sheetContext) {
      final accent = _accentOf(sheetContext);
      return ListenableBuilder(
        listenable: store,
        builder: (ctx, child) {
          final modes = RecommendMode.values;
          return Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _sheetHandle(),
                _sheetHeader('智能推荐模式'),
                ...List.generate(modes.length, (index) {
                  final mode = modes[index];
                  final meta = index < modeMeta.length
                      ? modeMeta[index]
                      : (title: mode.name, desc: '');
                  final selected = store.recommendMode == mode;
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () {
                        store.setRecommendMode(mode);
                        Navigator.of(sheetContext).pop();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: selected
                              ? accent.withValues(alpha: 0.18)
                              : Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: selected
                                ? accent
                                : Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    meta.title,
                                    style: TextStyle(
                                      color: selected ? accent : Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    meta.desc,
                                    style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.65),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (selected)
                              Icon(Icons.check_circle_rounded, color: accent),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          );
        },
      );
    },
  );
}

Future<void> showAddToPlaylistSheet(
  BuildContext context,
  AppStore store,
  Track track,
) {
  return _showSodaSheet<void>(
    context: context,
    builder: (sheetContext) {
      final accent = _accentOf(sheetContext);
      final maxHeight = MediaQuery.of(sheetContext).size.height * 0.65;
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: ListenableBuilder(
          listenable: store,
          builder: (ctx, child) {
            final playlists = store.playlists;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _sheetHandle(),
                _sheetHeader(
                  '添加到歌单',
                  trailing: TextButton.icon(
                    onPressed: () async {
                      final controller = TextEditingController();
                      final name = await showDialog<String>(
                        context: sheetContext,
                        builder: (dialogContext) {
                          return AlertDialog(
                            backgroundColor: _sheetBg,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            title: const Text(
                              '新建歌单',
                              style: TextStyle(color: Colors.white),
                            ),
                            content: TextField(
                              controller: controller,
                              autofocus: true,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: '输入歌单名称',
                                hintStyle: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.45),
                                ),
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.25),
                                  ),
                                ),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: accent),
                                ),
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(),
                                child: Text(
                                  '取消',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.65),
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  final trimmed = controller.text.trim();
                                  if (trimmed.isNotEmpty) {
                                    Navigator.of(dialogContext).pop(trimmed);
                                  }
                                },
                                child: Text(
                                  '创建',
                                  style: TextStyle(color: accent),
                                ),
                              ),
                            ],
                          );
                        },
                      );
                      controller.dispose();
                      if (name != null && name.isNotEmpty) {
                        final id = await store.createPlaylist(name);
                        if (id.isNotEmpty) {
                          await store.addTrackToPlaylist(id, track);
                        }
                        if (sheetContext.mounted) {
                          Navigator.of(sheetContext).pop();
                        }
                      }
                    },
                    icon: Icon(Icons.add_rounded, color: accent, size: 18),
                    label: Text(
                      '新建歌单',
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                if (playlists.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 36),
                    child: Text(
                      '暂无歌单，点击右上角新建',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 14,
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      itemCount: playlists.length,
                      itemBuilder: (itemContext, index) {
                        final playlist = playlists[index];
                        return ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          leading: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.queue_music_rounded,
                              color: accent,
                            ),
                          ),
                          title: Text(
                            playlist.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            '${playlist.trackIds.length} 首歌曲',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.55),
                              fontSize: 12,
                            ),
                          ),
                          onTap: () {
                            store.addTrackToPlaylist(playlist.id, track);
                            Navigator.of(sheetContext).pop();
                          },
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      );
    },
  );
}

Future<void> showSkinAndLayoutSheet(BuildContext context, AppStore store) {
  return _showSodaSheet<void>(
    context: context,
    builder: (sheetContext) {
      final accent = _accentOf(sheetContext);
      return ListenableBuilder(
        listenable: store,
        builder: (ctx, child) {
          final styles = PlayerStyle.values;
          final skins = AppSkin.values;
          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sheetHandle(),
                _sheetHeader('皮肤、布局与车机版式'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                  child: Text(
                    '播放器布局（共用同一队列）',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: List.generate(styles.length, (index) {
                      final style = styles[index];
                      final selected = store.playerStyle == style;
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            right: index == styles.length - 1 ? 0 : 8,
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => store.setPlayerStyle(style),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: selected
                                    ? accent.withValues(alpha: 0.25)
                                    : Colors.white.withValues(alpha: 0.07),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: selected
                                      ? accent
                                      : Colors.white.withValues(alpha: 0.12),
                                ),
                              ),
                              child: Text(
                                style.label,
                                style: TextStyle(
                                  color: selected
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.78),
                                  fontSize: 13,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Text(
                    '动态皮肤',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: skins.map((skin) {
                      final selected = store.appSkin == skin;
                      return ChoiceChip(
                        label: Text(skin.label),
                        selected: selected,
                        showCheckmark: false,
                        labelStyle: TextStyle(
                          color: selected
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.78),
                          fontSize: 13,
                        ),
                        backgroundColor: Colors.white.withValues(alpha: 0.08),
                        selectedColor: accent.withValues(alpha: 0.35),
                        side: BorderSide(
                          color: selected
                              ? accent
                              : Colors.white.withValues(alpha: 0.12),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        onSelected: (isSelected) => store.setAppSkin(skin),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Text(
                    '底栏样式 & 车机大字版式',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ...BottomBarStyle.values.map((bs) {
                        final sel = store.bottomBarStyle == bs;
                        return ChoiceChip(
                          label: Text(bs.label),
                          selected: sel,
                          showCheckmark: false,
                          selectedColor: accent.withValues(alpha: 0.35),
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                          labelStyle: const TextStyle(color: Colors.white, fontSize: 12),
                          onSelected: (_) => store.setBottomBarStyle(bs),
                        );
                      }),
                      ...CarLayoutMode.values.map((cm) {
                        final sel = store.carLayoutMode == cm;
                        return ChoiceChip(
                          label: Text('车机:${cm.label}'),
                          selected: sel,
                          showCheckmark: false,
                          selectedColor: accent.withValues(alpha: 0.35),
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                          labelStyle: const TextStyle(color: Colors.white, fontSize: 12),
                          onSelected: (_) => store.setCarLayoutMode(cm),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  activeThumbColor: accent,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  title: const Text(
                    '纯净模式',
                    style: TextStyle(color: Colors.white, fontSize: 15),
                  ),
                  subtitle: Text(
                    '隐藏多余操作按钮，专注音乐与歌词',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 12,
                    ),
                  ),
                  value: store.pureMode,
                  onChanged: store.setPureMode,
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

Future<void> showTrackOptionsSheet(
  BuildContext context,
  AppStore store,
  Track track,
) {
  return _showSodaSheet<void>(
    context: context,
    builder: (sheetContext) {
      final isFav = store.isFavorite(track.id);
      return SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                '${track.artist} · ${track.album}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            ListTile(
              leading: const Icon(Icons.play_arrow_rounded, color: Colors.white),
              title: const Text('立即播放', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                store.playTrack(track);
              },
            ),
            ListTile(
              leading: Icon(
                isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: isFav ? const Color(0xFFFF4D6D) : Colors.white,
              ),
              title: Text(
                isFav ? '取消喜欢' : '添加到我喜欢',
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                store.toggleFavorite(track);
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded, color: Colors.white),
              title: const Text('添加到歌单', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                showAddToPlaylistSheet(context, store, track);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_rounded, color: Colors.white),
              title: const Text('分享歌曲', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                store.bridge.shareText(
                  '${track.title} - ${track.artist}',
                  subject: track.title,
                );
              },
            ),
          ],
        ),
      );
    },
  );
}

Future<void> showModeSelectSheet(BuildContext context, AppStore store) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return AnimatedBuilder(
        animation: store,
        builder: (ctx, _) {
          final height = MediaQuery.of(ctx).size.height * 0.94;
          final isRecommend =
              !store.pureMode && store.playerStyle == PlayerStyle.recommend;
          final isFree =
              !store.pureMode && store.playerStyle == PlayerStyle.free;
          final isPure = store.pureMode;

          return Container(
            height: height,
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF133023),
                  Color(0xFF0B0E11),
                ],
                stops: [0.0, 0.38],
              ),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.24),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: IconButton(
                            onPressed: () => Navigator.of(sheetContext).pop(),
                            icon: Icon(
                              Icons.close_rounded,
                              color: Colors.white.withOpacity(0.78),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              const Text(
                                '模式选择',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '全页面 · 点选切换',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: Colors.white.withOpacity(0.50),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '切换后立即生效，并记住你的选择',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withOpacity(0.58),
                            ),
                          ),
                          const SizedBox(height: 20),
                          _ModeSelectCard(
                            icon: Icons.auto_awesome_rounded,
                            title: '推荐模式',
                            subtitle: '封面在上 · 信息在下，左右滑动切歌',
                            selected: isRecommend,
                            onTap: () {
                              store.setPureMode(false);
                              store.setPlayerStyle(PlayerStyle.recommend);
                              Navigator.of(sheetContext).pop();
                            },
                          ),
                          const SizedBox(height: 12),
                          _ModeSelectCard(
                            icon: Icons.blur_on_rounded,
                            title: 'Free 模式',
                            subtitle: '封面取色铺满全屏 · 底部发现 / 我的，中间一键播放',
                            selected: isFree,
                            onTap: () {
                              store.setPureMode(false);
                              store.setPlayerStyle(PlayerStyle.free);
                              Navigator.of(sheetContext).pop();
                            },
                          ),
                          const SizedBox(height: 12),
                          _ModeSelectCard(
                            icon: Icons.nightlight_round,
                            title: '纯净模式',
                            subtitle: '全屏无干扰 · 只留封面与三键控制',
                            selected: isPure,
                            onTap: () {
                              store.setPureMode(true);
                              Navigator.of(sheetContext).pop();
                            },
                          ),
                          const SizedBox(height: 12),
                          _ModeSelectCard(
                            icon: Icons.directions_car_rounded,
                            title: '驾驶模式',
                            subtitle: '超大字号与大按钮，行车时一眼可读',
                            selected: false,
                            onTap: () {
                              Navigator.of(sheetContext).pop();
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => DrivePage(store: store),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: const Color(0xFF14191C),
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.08),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.06),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                        Icons.grid_view_rounded,
                                        color: Color(0xFF2FE08B),
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            '车机版式',
                                            style: TextStyle(
                                              fontSize: 15.5,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '车机上建议开启，横竖屏自动适配大按钮 / 大字号',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.white
                                                  .withOpacity(0.55),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  children: List.generate(
                                    CarLayoutMode.values.length,
                                    (index) {
                                      final mode = CarLayoutMode.values[index];
                                      final selected =
                                          store.carLayoutMode == mode;
                                      const labels = ['自动', '开启', '关闭'];
                                      final label = index < labels.length
                                          ? labels[index]
                                          : mode.name;

                                      return Expanded(
                                        child: Padding(
                                          padding: EdgeInsets.only(
                                            right: index ==
                                                    CarLayoutMode
                                                            .values.length -
                                                        1
                                                ? 0
                                                : 8,
                                          ),
                                          child: GestureDetector(
                                            onTap: () =>
                                                store.setCarLayoutMode(mode),
                                            child: AnimatedContainer(
                                              duration: const Duration(
                                                milliseconds: 180,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                vertical: 10,
                                              ),
                                              alignment: Alignment.center,
                                              decoration: BoxDecoration(
                                                color: selected
                                                    ? const Color(0xFF123626)
                                                    : Colors.white
                                                        .withOpacity(0.05),
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                                border: Border.all(
                                                  color: selected
                                                      ? const Color(0xFF2FE08B)
                                                      : Colors.white
                                                          .withOpacity(0.08),
                                                  width: selected ? 1.2 : 1.0,
                                                ),
                                              ),
                                              child: Text(
                                                label,
                                                style: TextStyle(
                                                  fontSize: 13.5,
                                                  fontWeight: selected
                                                      ? FontWeight.w700
                                                      : FontWeight.w500,
                                                  color: selected
                                                      ? const Color(0xFF2FE08B)
                                                      : Colors.white
                                                          .withOpacity(0.75),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

class _ModeSelectCard extends StatelessWidget {
  const _ModeSelectCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF123626) : const Color(0xFF14191C),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected
                ? const Color(0xFF2FE08B)
                : Colors.white.withOpacity(0.08),
            width: selected ? 1.4 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFF2FE08B).withOpacity(0.16)
                    : Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                color: selected
                    ? const Color(0xFF2FE08B)
                    : Colors.white.withOpacity(0.82),
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color:
                          selected ? const Color(0xFF2FE08B) : Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: Colors.white.withOpacity(0.58),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (selected)
              const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF2FE08B),
                size: 24,
              )
            else
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withOpacity(0.26),
                    width: 1.5,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> showMoreRoamSheet(
  BuildContext context,
  AppStore store, {
  VoidCallback? onOpenLyrics,
  VoidCallback? onOpenIsland,
}) {
  const roamStyles = <({String label, Color tint})>[
    (label: '猜你喜欢', tint: Color(0xFF1F4E3D)),
    (label: 'Chill放松', tint: Color(0xFF1C3F52)),
    (label: '快乐时光', tint: Color(0xFF4D3E1C)),
    (label: '通勤必听', tint: Color(0xFF283A52)),
    (label: '驾车', tint: Color(0xFF3E2D52)),
    (label: '洗澡', tint: Color(0xFF1B4B4E)),
    (label: '夜晚', tint: Color(0xFF242B47)),
    (label: 'DJ模式', tint: Color(0xFF4F283A)),
    (label: '治愈', tint: Color(0xFF274936)),
  ];

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return AnimatedBuilder(
        animation: store,
        builder: (ctx, _) {
          final height = MediaQuery.of(ctx).size.height * 0.88;
          final track = store.currentTrack;
          final greeting = DailyCopy.now();
          final tip = DailyCopy.dailyTip();

          return Container(
            height: height,
            decoration: const BoxDecoration(
              color: Color(0xFF141619),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.22),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                track?.title ?? 'SodaPulse',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                track?.artist ?? '本地曲库',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: Colors.white.withOpacity(0.55),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            showAudioQualitySheet(context, store);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF123626),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: const Color(0xFF2FE08B),
                                width: 1.1,
                              ),
                            ),
                            child: Text(
                              store.preferredQualityLabel,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF2FE08B),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: Colors.white.withOpacity(0.06),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(22),
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFF14422D),
                                  Color(0xFF0F3021),
                                ],
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  greeting.title,
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  greeting.subtitle,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    color: Colors.white.withOpacity(0.76),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.10),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    tip,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: Colors.white.withOpacity(0.90),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 22),
                          const Row(
                            children: [
                              Icon(
                                Icons.tune_rounded,
                                color: Color(0xFF2FE08B),
                                size: 18,
                              ),
                              SizedBox(width: 8),
                              Text(
                                '选个模式听歌吧',
                                style: TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _RecommendModeCard(
                                  label: '新鲜模式',
                                  icon: Icons.explore_rounded,
                                  selected: store.recommendMode ==
                                      RecommendMode.fresh,
                                  onTap: () => store
                                      .setRecommendMode(RecommendMode.fresh),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _RecommendModeCard(
                                  label: '熟悉模式',
                                  icon: Icons.favorite_rounded,
                                  selected: store.recommendMode ==
                                      RecommendMode.familiar,
                                  onTap: () => store
                                      .setRecommendMode(RecommendMode.familiar),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _RecommendModeCard(
                                  label: '默认模式',
                                  icon: Icons.graphic_eq_rounded,
                                  selected: store.recommendMode ==
                                      RecommendMode.balanced,
                                  onTap: () => store
                                      .setRecommendMode(RecommendMode.balanced),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 22),
                          const Row(
                            children: [
                              Icon(
                                Icons.auto_awesome_rounded,
                                color: Color(0xFF2FE08B),
                                size: 18,
                              ),
                              SizedBox(width: 8),
                              Text(
                                '按风格漫游',
                                style: TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          GridView.count(
                            crossAxisCount: 3,
                            childAspectRatio: 2.35,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            children: roamStyles.map((item) {
                              return GestureDetector(
                                onTap: () {
                                  final messenger =
                                      ScaffoldMessenger.of(context);
                                  store.refreshRecommendQueue();
                                  Navigator.of(sheetContext).pop();
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text('已开启「${item.label}」漫游'),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                },
                                child: Container(
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: item.tint.withOpacity(0.55),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.08),
                                    ),
                                  ),
                                  child: Text(
                                    item.label,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 22),
                          Text(
                            '播放',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withOpacity(0.55),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF181C20),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Column(
                              children: [
                                _MorePlayTile(
                                  icon: Icons.lyrics_rounded,
                                  title: '查看歌词',
                                  onTap: () {
                                    Navigator.of(sheetContext).pop();
                                    onOpenLyrics?.call();
                                  },
                                ),
                                _MorePlayDivider(),
                                _MorePlayTile(
                                  icon: Icons.speaker_group_rounded,
                                  title: '音频输出',
                                  onTap: () {
                                    Navigator.of(sheetContext).pop();
                                    showSoundEffectSheet(context, store);
                                  },
                                ),
                                _MorePlayDivider(),
                                _MorePlayTile(
                                  icon: Icons.timer_rounded,
                                  title: '定时关闭与倍速',
                                  onTap: () {
                                    Navigator.of(sheetContext).pop();
                                    showSleepAndSpeedSheet(context, store);
                                  },
                                ),
                                _MorePlayDivider(),
                                _MorePlayTile(
                                  icon: Icons.subtitles_rounded,
                                  title: '灵动岛 & 逐字歌词',
                                  onTap: () {
                                    Navigator.of(sheetContext).pop();
                                    onOpenIsland?.call();
                                  },
                                ),
                                _MorePlayDivider(),
                                _MorePlayTile(
                                  icon: Icons.palette_rounded,
                                  title: '皮肤与底栏',
                                  onTap: () {
                                    Navigator.of(sheetContext).pop();
                                    showSkinAndLayoutSheet(context, store);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

class _RecommendModeCard extends StatelessWidget {
  const _RecommendModeCard({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF123626) : const Color(0xFF181C20),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? const Color(0xFF2FE08B)
                : Colors.white.withOpacity(0.08),
            width: selected ? 1.3 : 1.0,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color: selected
                  ? const Color(0xFF2FE08B)
                  : Colors.white.withOpacity(0.80),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? const Color(0xFF2FE08B) : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MorePlayTile extends StatelessWidget {
  const _MorePlayTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
      leading: Icon(
        icon,
        size: 21,
        color: Colors.white.withOpacity(0.85),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: Colors.white.withOpacity(0.38),
      ),
    );
  }
}

class _MorePlayDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: 54,
      endIndent: 18,
      color: Colors.white.withOpacity(0.06),
    );
  }
}
