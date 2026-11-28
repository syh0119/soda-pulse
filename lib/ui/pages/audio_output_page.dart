import 'package:flutter/material.dart';

import '../../core/app_store.dart';
import '../sheets/player_sheets.dart';
import '../theme/soda_theme.dart';

class AudioOutputPage extends StatefulWidget {
  const AudioOutputPage({super.key, required this.store});

  final AppStore store;

  @override
  State<AudioOutputPage> createState() => _AudioOutputPageState();
}

class _AudioOutputPageState extends State<AudioOutputPage> {
  Map<String, dynamic>? _probe;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _runProbe();
  }

  Future<void> _runProbe() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final res = await widget.store.probeAudioHardware();
      if (!mounted) return;
      setState(() {
        _probe = res;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final probe = _probe ?? const <String, dynamic>{};
        final activeName = (probe['activeDeviceName'] ?? '系统默认输出').toString();
        final activeType = (probe['activeDeviceType'] ?? '默认').toString();
        final rawDevices = probe['devices'];
        final devices = rawDevices is List
            ? rawDevices
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
            : <Map<String, dynamic>>[];

        return Scaffold(
          backgroundColor: SodaColors.background,
          appBar: AppBar(
            backgroundColor: SodaColors.background,
            elevation: 0,
            title: const Text(
              '音频输出与硬件探测',
              style: TextStyle(
                color: SodaColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            actions: [
              IconButton(
                tooltip: '重新探测',
                onPressed: _loading ? null : _runProbe,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          body: RefreshIndicator(
            color: SodaColors.cyan,
            backgroundColor: SodaColors.surface,
            onRefresh: _runProbe,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _buildActiveOutputCard(activeName, activeType),
                const SizedBox(height: 16),
                _buildDspStatusCard(context),
                const SizedBox(height: 16),
                _buildHardwareProbeCard(probe),
                const SizedBox(height: 16),
                _buildDevicesListCard(devices),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActiveOutputCard(String name, String type) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            SodaColors.cyan.withValues(alpha: 0.16),
            SodaColors.lime.withValues(alpha: 0.08),
            SodaColors.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SodaColors.cyan.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: SodaColors.cyan.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.speaker_group_rounded,
              color: SodaColors.cyan,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '当前优先输出路由',
                  style: TextStyle(
                    color: SodaColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _loading ? '正在探测音频路由...' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: SodaColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  type,
                  style: const TextStyle(
                    color: SodaColors.cyan,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
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
    );
  }

  Widget _buildDspStatusCard(BuildContext context) {
    final qualityOption = AudioQualityOptions.byId(widget.store.audioQuality);
    final eqActive = widget.store.eqGains.any((g) => g.abs() > 0.05) ||
        widget.store.eqPreGain.abs() > 0.05;

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
            'SodaPulse 实时音频引擎 (ExoPlayer DSP)',
            style: TextStyle(
              color: SodaColors.textPrimary,
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          _InfoKvRow(
            label: '首选音质档位',
            value: '${qualityOption.title} (${qualityOption.badge})',
            valueColor: SodaColors.cyan,
          ),
          const SizedBox(height: 10),
          _InfoKvRow(
            label: '多段均衡器 (EQ)',
            value: eqActive
                ? '已激活 (${widget.store.eqPresetShortLabel})'
                : '直通 (${widget.store.eqPresetShortLabel})',
            valueColor: eqActive ? SodaColors.lime : SodaColors.textSecondary,
          ),
          const SizedBox(height: 10),
          _InfoKvRow(
            label: '响度平衡 (-14 LUFS)',
            value: widget.store.loudnessNormEnabled ? '已开启' : '已关闭',
            valueColor: widget.store.loudnessNormEnabled
                ? SodaColors.lime
                : SodaColors.textSecondary,
          ),
          const SizedBox(height: 10),
          _InfoKvRow(
            label: '播放倍速',
            value: '${widget.store.playbackSpeed.toStringAsFixed(2)}x',
            valueColor: SodaColors.textPrimary,
          ),
          const SizedBox(height: 10),
          const _InfoKvRow(
            label: 'ALAC 无损软解',
            value: '已内置 · 16/24-bit WAV 虚拟流',
            valueColor: SodaColors.lime,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => showSoundEffectSheet(context, widget.store),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: SodaColors.cyan,
                    side: BorderSide(
                      color: SodaColors.cyan.withValues(alpha: 0.45),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.equalizer_rounded, size: 18),
                  label: const Text('调音台 & EQ'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => showAudioQualitySheet(context, widget.store),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: SodaColors.lime,
                    side: BorderSide(
                      color: SodaColors.lime.withValues(alpha: 0.45),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.high_quality_rounded, size: 18),
                  label: const Text('切换音质'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHardwareProbeCard(Map<String, dynamic> probe) {
    final eqSupported = probe['equalizerSupported'] == true;
    final eqBands = (probe['equalizerBands'] as num?)?.toInt() ?? 0;
    final rangeRaw = probe['equalizerRangeMb'];
    String rangeText = '--';
    if (rangeRaw is List && rangeRaw.length >= 2) {
      final minDb = ((rangeRaw[0] as num).toDouble() / 100.0).toStringAsFixed(0);
      final maxDb = ((rangeRaw[1] as num).toDouble() / 100.0).toStringAsFixed(0);
      rangeText = '$minDb dB ~ +$maxDb dB';
    }
    final freqsRaw = probe['centerFreqsHz'];
    String freqsText = '--';
    if (freqsRaw is List && freqsRaw.isNotEmpty) {
      freqsText = freqsRaw
          .map((hz) {
            final v = (hz as num).toInt();
            return v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}k' : '${v}Hz';
          })
          .join(' · ');
    }
    final loudnessSupported = probe['loudnessEnhancerSupported'] == true;
    final sessionId = (probe['probeSessionId'] as num?)?.toInt() ?? 0;
    final probeError = probe['probeError']?.toString();

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
            'Android 硬件音效探测 (SfxProbe)',
            style: TextStyle(
              color: SodaColors.textPrimary,
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          _InfoKvRow(
            label: 'Equalizer 硬件支持',
            value: eqSupported ? '支持 ($eqBands 频段)' : '不可用',
            valueColor: eqSupported ? SodaColors.lime : const Color(0xFFFF5C7A),
          ),
          const SizedBox(height: 10),
          _InfoKvRow(
            label: '硬件增益范围',
            value: rangeText,
            valueColor: SodaColors.textPrimary,
          ),
          const SizedBox(height: 10),
          _InfoKvRow(
            label: '中心频点',
            value: freqsText,
            valueColor: SodaColors.textSecondary,
          ),
          const SizedBox(height: 10),
          _InfoKvRow(
            label: 'LoudnessEnhancer',
            value: loudnessSupported ? '支持' : '不可用',
            valueColor:
                loudnessSupported ? SodaColors.lime : const Color(0xFFFF5C7A),
          ),
          const SizedBox(height: 10),
          _InfoKvRow(
            label: '探测 AudioSession',
            value: sessionId > 0 ? '#$sessionId' : '--',
            valueColor: SodaColors.textSecondary,
          ),
          if (_error != null || (probeError != null && probeError.isNotEmpty)) ...[
            const SizedBox(height: 10),
            Text(
              '探测备注: ${_error ?? probeError}',
              style: const TextStyle(
                color: Color(0xFFFFB020),
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDevicesListCard(List<Map<String, dynamic>> devices) {
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
          Text(
            '已检测到输出设备 (${devices.length})',
            style: const TextStyle(
              color: SodaColors.textPrimary,
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          if (devices.isEmpty)
            const Text(
              '未检测到额外输出设备或正在探测中',
              style: TextStyle(color: SodaColors.textSecondary, fontSize: 13),
            )
          else
            ...devices.map((dev) {
              final name = (dev['name'] ?? '未知设备').toString();
              final typeName = (dev['typeName'] ?? '').toString();
              final rates = (dev['sampleRates'] is List &&
                      (dev['sampleRates'] as List).isNotEmpty)
                  ? (dev['sampleRates'] as List)
                      .map((r) => '${((r as num) / 1000).toStringAsFixed(1)}kHz')
                      .take(4)
                      .join(', ')
                  : '自适应采样率';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: SodaColors.cyan.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.audiotrack_rounded,
                        color: SodaColors.cyan,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: SodaColors.textPrimary,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$typeName · $rates',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: SodaColors.textSecondary,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _InfoKvRow extends StatelessWidget {
  const _InfoKvRow({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: SodaColors.textSecondary,
            fontSize: 13,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: valueColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
