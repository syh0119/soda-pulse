package com.sodapulse.music

import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.UnstableApi
import java.nio.ByteBuffer
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.math.tanh

@OptIn(UnstableApi::class)
class SodaEqAudioProcessor : BaseAudioProcessor() {

    private var channelCount = 0
    private var sampleRate = 0
    private var encoding = C.ENCODING_INVALID

    @Volatile
    private var bandDb = sBandDb.copyOf()

    @Volatile
    private var preGainDb = sPreGainDb

    @Volatile
    private var loudnessNormEnabled = sLoudnessNormEnabled

    @Volatile
    private var targetRms = sTargetRms

    @Volatile
    private var coeffsDirty = true

    private var bypassed = true
    private var preGainLinear = 1.0f

    private val b0 = DoubleArray(NUM_BANDS) { 1.0 }
    private val b1 = DoubleArray(NUM_BANDS)
    private val b2 = DoubleArray(NUM_BANDS)
    private val a1 = DoubleArray(NUM_BANDS)
    private val a2 = DoubleArray(NUM_BANDS)

    private var z1 = Array(MAX_CHANNELS) { DoubleArray(NUM_BANDS) }
    private var z2 = Array(MAX_CHANNELS) { DoubleArray(NUM_BANDS) }

    private var envelope = 0.0
    private var attackCoeff = 0.0
    private var releaseCoeff = 0.0

    private var rmsSq = targetRms * targetRms
    private var currentNormGain = 1.0
    private var samplesSinceReset = 0L
    private var fastConvergeSamples = 57600L
    private var alphaFast = 0.0
    private var alphaDown = 0.0
    private var alphaUp = 0.0

    private var rawFrameSamples = FloatArray(MAX_CHANNELS)
    private var frameSamples = FloatArray(MAX_CHANNELS)

    override fun onConfigure(
        inputAudioFormat: AudioProcessor.AudioFormat
    ): AudioProcessor.AudioFormat {
        val enc = inputAudioFormat.encoding
        val ch = inputAudioFormat.channelCount
        val sr = inputAudioFormat.sampleRate

        if ((enc != C.ENCODING_PCM_16BIT && enc != C.ENCODING_PCM_FLOAT) ||
            ch !in 1..MAX_CHANNELS ||
            sr <= 0
        ) {
            throw AudioProcessor.UnhandledAudioFormatException(inputAudioFormat)
        }

        encoding = enc
        channelCount = ch
        sampleRate = sr

        attackCoeff = exp(-1.0 / (0.001 * sr))
        releaseCoeff = exp(-1.0 / (0.080 * sr))
        fastConvergeSamples = (FAST_CONVERGE_SECONDS * sr).toLong()
        alphaFast = 1.0 - exp(-1.0 / (TAU_FAST * sr))
        alphaDown = 1.0 - exp(-1.0 / (TAU_DOWN * sr))
        alphaUp = 1.0 - exp(-1.0 / (TAU_UP * sr))

        bandDb = sBandDb.copyOf()
        preGainDb = sPreGainDb
        loudnessNormEnabled = sLoudnessNormEnabled
        targetRms = sTargetRms
        coeffsDirty = true
        sActive = this

        resetFilterStates()
        return inputAudioFormat
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        if (!inputBuffer.hasRemaining()) {
            return
        }

        if (coeffsDirty) {
            recomputeCoeffs()
        }

        val remaining = inputBuffer.remaining()
        val outputBuffer = replaceOutputBuffer(remaining)

        if (bypassed) {
            outputBuffer.put(inputBuffer)
            outputBuffer.flip()
            return
        }

        val chCount = channelCount
        val bytesPerSample = if (encoding == C.ENCODING_PCM_16BIT) 2 else 4
        val frameSize = chCount * bytesPerSample
        val frameCount = remaining / frameSize
        val normActive = loudnessNormEnabled

        for (f in 0 until frameCount) {
            var sumSq = 0.0
            for (ch in 0 until chCount) {
                val raw = if (encoding == C.ENCODING_PCM_16BIT) {
                    inputBuffer.short.toFloat() / 32768.0f
                } else {
                    inputBuffer.float
                }
                rawFrameSamples[ch] = raw
                sumSq += raw.toDouble() * raw.toDouble()
            }

            var normGain = 1.0
            if (normActive) {
                val frameMeanSq = sumSq / chCount
                if (frameMeanSq >= SILENCE_GATE_SQ) {
                    val isFastPhase = samplesSinceReset < fastConvergeSamples
                    val alphaRms = when {
                        isFastPhase -> alphaFast
                        frameMeanSq > rmsSq -> alphaDown
                        else -> alphaUp
                    }
                    rmsSq += alphaRms * (frameMeanSq - rmsSq)

                    val currentRms = sqrt(rmsSq.coerceAtLeast(SILENCE_GATE_SQ))
                    val desiredGain = (targetRms / currentRms).coerceIn(MIN_NORM_GAIN, MAX_NORM_GAIN)
                    val alphaGain = when {
                        isFastPhase -> alphaFast
                        desiredGain < currentNormGain -> alphaDown
                        else -> alphaUp
                    }
                    currentNormGain += alphaGain * (desiredGain - currentNormGain)
                    samplesSinceReset++
                }
                normGain = currentNormGain
            }

            var framePeak = 0.0f
            val combinedPre = normGain * preGainLinear.toDouble()
            for (ch in 0 until chCount) {
                var x = rawFrameSamples[ch].toDouble() * combinedPre
                val chZ1 = z1[ch]
                val chZ2 = z2[ch]

                for (b in 0 until NUM_BANDS) {
                    val y = b0[b] * x + chZ1[b]
                    chZ1[b] = b1[b] * x - a1[b] * y + chZ2[b]
                    chZ2[b] = b2[b] * x - a2[b] * y
                    x = y
                }

                val outSample = x.toFloat()
                frameSamples[ch] = outSample
                framePeak = max(framePeak, abs(outSample))
            }

            val peakD = framePeak.toDouble()
            envelope = if (peakD > envelope) {
                attackCoeff * envelope + (1.0 - attackCoeff) * peakD
            } else {
                releaseCoeff * envelope + (1.0 - releaseCoeff) * peakD
            }

            val limiterGain = if (envelope > LIMIT) {
                (LIMIT / envelope).toFloat()
            } else {
                1.0f
            }

            for (ch in 0 until chCount) {
                val limited = frameSamples[ch] * limiterGain
                val guarded = softClip(limited)

                if (encoding == C.ENCODING_PCM_16BIT) {
                    val pcm = (guarded * 32767.0f).roundToInt().coerceIn(-32768, 32767).toShort()
                    outputBuffer.putShort(pcm)
                } else {
                    outputBuffer.putFloat(guarded)
                }
            }
        }

        if (inputBuffer.hasRemaining()) {
            outputBuffer.put(inputBuffer)
        }

        outputBuffer.flip()
    }

    override fun onFlush() {
        resetFilterStates()
    }

    override fun onReset() {
        resetFilterStates()
        channelCount = 0
        sampleRate = 0
        encoding = C.ENCODING_INVALID
        if (sActive === this) {
            sActive = null
        }
    }

    private fun updateParams(gains: FloatArray, preGain: Float) {
        val copy = FloatArray(NUM_BANDS)
        val count = minOf(gains.size, NUM_BANDS)
        for (i in 0 until count) {
            copy[i] = gains[i].coerceIn(-15.0f, 15.0f)
        }
        bandDb = copy
        preGainDb = preGain.coerceIn(-15.0f, 15.0f)
        coeffsDirty = true
    }

    private fun updateLoudnessNorm(enabled: Boolean, targetLufs: Float) {
        loudnessNormEnabled = enabled
        targetRms = 10.0.pow(targetLufs.coerceIn(-24.0f, -6.0f).toDouble() / 20.0)
        coeffsDirty = true
    }

    private fun recomputeCoeffs() {
        coeffsDirty = false
        val gains = bandDb
        val pre = preGainDb
        val sr = sampleRate.toDouble()

        var allZero = abs(pre) < 0.01f
        preGainLinear = 10.0.pow(pre / 20.0).toFloat()

        for (i in 0 until NUM_BANDS) {
            val gainDb = gains[i]
            if (abs(gainDb) >= 0.01f) {
                allZero = false
            }

            val freq = FREQS[i]
            if (sr <= 0.0 || freq >= sr * 0.499 || abs(gainDb) < 0.01f) {
                b0[i] = 1.0
                b1[i] = 0.0
                b2[i] = 0.0
                a1[i] = 0.0
                a2[i] = 0.0
                continue
            }

            val a = 10.0.pow(gainDb / 40.0)
            val w0 = 2.0 * Math.PI * freq / sr
            val cosW0 = cos(w0)
            val sinW0 = sin(w0)
            val alpha = sinW0 / (2.0 * QS[i])

            val a0 = 1.0 + alpha / a
            b0[i] = (1.0 + alpha * a) / a0
            b1[i] = (-2.0 * cosW0) / a0
            b2[i] = (1.0 - alpha * a) / a0
            a1[i] = (-2.0 * cosW0) / a0
            a2[i] = (1.0 - alpha / a) / a0
        }

        bypassed = allZero && !loudnessNormEnabled
    }

    private fun resetFilterStates() {
        for (ch in 0 until MAX_CHANNELS) {
            z1[ch].fill(0.0)
            z2[ch].fill(0.0)
        }
        envelope = 0.0
        rmsSq = targetRms * targetRms
        currentNormGain = 1.0
        samplesSinceReset = 0L
    }

    private fun softClip(x: Float): Float {
        if (x > SOFT_CLIP_THRESHOLD) {
            return SOFT_CLIP_THRESHOLD + SOFT_CLIP_HEADROOM *
                tanh(((x - SOFT_CLIP_THRESHOLD) / SOFT_CLIP_HEADROOM).toDouble()).toFloat()
        }
        if (x < -SOFT_CLIP_THRESHOLD) {
            return -SOFT_CLIP_THRESHOLD + SOFT_CLIP_HEADROOM *
                tanh(((x + SOFT_CLIP_THRESHOLD) / SOFT_CLIP_HEADROOM).toDouble()).toFloat()
        }
        return x
    }

    companion object {
        private const val NUM_BANDS = 5
        private const val MAX_CHANNELS = 8
        private const val LIMIT = 0.96f
        private const val SOFT_CLIP_THRESHOLD = 0.99f
        private const val SOFT_CLIP_HEADROOM = 0.01f
        private const val SILENCE_GATE_SQ = 1e-5
        private const val MIN_NORM_GAIN = 0.28
        private const val MAX_NORM_GAIN = 3.16
        private const val FAST_CONVERGE_SECONDS = 1.2
        private const val TAU_FAST = 0.25
        private const val TAU_DOWN = 0.15
        private const val TAU_UP = 1.5

        private val FREQS = doubleArrayOf(60.0, 230.0, 910.0, 3600.0, 14000.0)
        private val QS = doubleArrayOf(0.9, 1.0, 1.1, 1.15, 0.8)

        @Volatile
        private var sBandDb = FloatArray(NUM_BANDS)

        @Volatile
        private var sPreGainDb = 0.0f

        @Volatile
        private var sLoudnessNormEnabled = true

        @Volatile
        private var sTargetRms = 10.0.pow(-14.0 / 20.0)

        @Volatile
        private var sActive: SodaEqAudioProcessor? = null

        fun setParams(gains: FloatArray, preGainDb: Float) {
            val copy = FloatArray(NUM_BANDS)
            val count = minOf(gains.size, NUM_BANDS)
            for (i in 0 until count) {
                copy[i] = gains[i].coerceIn(-15.0f, 15.0f)
            }
            val clampedPre = preGainDb.coerceIn(-15.0f, 15.0f)
            sBandDb = copy
            sPreGainDb = clampedPre
            sActive?.updateParams(copy, clampedPre)
        }

        fun setLoudnessNorm(enabled: Boolean, targetLufs: Float = -14.0f) {
            val clampedLufs = targetLufs.coerceIn(-24.0f, -6.0f)
            sLoudnessNormEnabled = enabled
            sTargetRms = 10.0.pow(clampedLufs.toDouble() / 20.0)
            sActive?.updateLoudnessNorm(enabled, clampedLufs)
        }

        fun bypass() {
            val zeros = FloatArray(NUM_BANDS)
            sBandDb = zeros
            sPreGainDb = 0.0f
            sActive?.updateParams(zeros, 0.0f)
        }
    }
}
