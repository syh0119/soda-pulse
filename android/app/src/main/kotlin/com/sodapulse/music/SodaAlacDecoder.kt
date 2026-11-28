package com.sodapulse.music

import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.min

data class AlacConfig(
    val frameLength: Int,
    val compatibleVersion: Int,
    val bitDepth: Int,
    val pb: Int,
    val mb: Int,
    val kb: Int,
    val numChannels: Int,
    val maxRun: Int,
    val maxFrameBytes: Int,
    val avgBitRate: Int,
    val sampleRate: Int
) {
    companion object {
        fun parse(cookie: ByteArray): AlacConfig {
            val offset = when {
                cookie.size >= 36 &&
                    cookie[4] == 'a'.code.toByte() &&
                    cookie[5] == 'l'.code.toByte() &&
                    cookie[6] == 'a'.code.toByte() &&
                    cookie[7] == 'c'.code.toByte() -> 12
                cookie.size == 28 -> 4
                cookie.size >= 24 -> 0
                else -> throw IllegalArgumentException("Invalid ALAC magic cookie size: ${cookie.size}")
            }

            val buf = ByteBuffer.wrap(cookie, offset, 24).order(ByteOrder.BIG_ENDIAN)
            return AlacConfig(
                frameLength = buf.int,
                compatibleVersion = buf.get().toInt() and 0xFF,
                bitDepth = buf.get().toInt() and 0xFF,
                pb = buf.get().toInt() and 0xFF,
                mb = buf.get().toInt() and 0xFF,
                kb = buf.get().toInt() and 0xFF,
                numChannels = buf.get().toInt() and 0xFF,
                maxRun = buf.short.toInt() and 0xFFFF,
                maxFrameBytes = buf.int,
                avgBitRate = buf.int,
                sampleRate = buf.int
            )
        }
    }
}

class SodaAlacDecoder(val config: AlacConfig) {

    constructor(cookie: ByteArray) : this(AlacConfig.parse(cookie))

    val bytesPerSample: Int = when {
        config.bitDepth <= 16 -> 2
        config.bitDepth <= 24 -> 3
        else -> 4
    }

    fun decode(packet: ByteArray): ByteArray = decode(packet, 0, packet.size)

    fun decode(packet: ByteArray, offset: Int, length: Int): ByteArray {
        require(offset >= 0 && length >= 0 && offset + length <= packet.size) {
            "Invalid packet slice: offset=$offset, length=$length, size=${packet.size}"
        }

        val reader = BitReader(packet, offset, length)
        val channels = mutableListOf<IntArray>()
        var numSamples = 0

        loop@ while (reader.bitsRemaining() >= 3) {
            val tag = reader.readBits(3)
            when (tag) {
                ID_SCE, ID_LFE -> {
                    val decoded = decodeSingleChannel(reader)
                    numSamples = decoded.size
                    channels.add(decoded)
                }
                ID_CPE -> {
                    val (left, right) = decodeChannelPair(reader)
                    numSamples = left.size
                    channels.add(left)
                    channels.add(right)
                }
                ID_DSE -> {
                    reader.skipBits(4) // elementInstanceTag
                    val dataByteAlignFlag = reader.readBit()
                    var count = reader.readBits(8)
                    if (count == 255) {
                        count += reader.readBits(8)
                    }
                    if (dataByteAlignFlag != 0) {
                        reader.byteAlign()
                    }
                    reader.skipBits(count * 8)
                }
                ID_FIL -> {
                    var count = reader.readBits(4)
                    if (count == 15) {
                        count += reader.readBits(8) - 1
                    }
                    reader.skipBits(count * 8)
                }
                ID_END -> break@loop
                else -> throw IllegalArgumentException("Unsupported ALAC element tag: $tag")
            }
        }

        if (channels.isEmpty() || numSamples == 0) {
            return ByteArray(0)
        }

        return interleavePcm(channels, numSamples)
    }

    private fun decodeSingleChannel(reader: BitReader): IntArray {
        reader.skipBits(4) // elementInstanceTag
        reader.skipBits(12) // unused
        val hasSize = reader.readBit()
        val bytesShifted = reader.readBits(2)
        val escapeFlag = reader.readBit()
        val outputSamples = if (hasSize != 0) reader.readBits(32) else config.frameLength

        val out = IntArray(outputSamples)
        if (escapeFlag != 0) {
            val bitDepth = config.bitDepth
            for (i in 0 until outputSamples) {
                out[i] = reader.readSigned(bitDepth)
            }
            return out
        }

        val shift = bytesShifted * 8
        val chanBits = config.bitDepth - shift

        reader.skipBits(8) // mixBits (unused for mono)
        reader.skipBits(8) // mixRes (unused for mono)

        reader.skipBits(4) // modeU
        val denShiftU = reader.readBits(4)
        val pbFactorU = reader.readBits(4)
        val numU = reader.readBits(5)
        val coefsU = IntArray(32)
        for (i in 0 until numU) {
            coefsU[i] = reader.readSigned(16)
        }

        val shiftBuffer = if (bytesShifted != 0) {
            IntArray(outputSamples) { reader.readBits(shift) }
        } else {
            null
        }

        val pred = IntArray(outputSamples)
        dynDecomp(reader, pred, outputSamples, chanBits, pbFactorU)
        unpcBlock(pred, out, outputSamples, coefsU, numU, chanBits, denShiftU)

        if (shiftBuffer != null) {
            for (i in 0 until outputSamples) {
                out[i] = (out[i] shl shift) or shiftBuffer[i]
            }
        }

        return out
    }

    private fun decodeChannelPair(reader: BitReader): Pair<IntArray, IntArray> {
        reader.skipBits(4) // elementInstanceTag
        reader.skipBits(12) // unused
        val hasSize = reader.readBit()
        val bytesShifted = reader.readBits(2)
        val escapeFlag = reader.readBit()
        val outputSamples = if (hasSize != 0) reader.readBits(32) else config.frameLength

        val left = IntArray(outputSamples)
        val right = IntArray(outputSamples)

        if (escapeFlag != 0) {
            val bitDepth = config.bitDepth
            for (i in 0 until outputSamples) {
                left[i] = reader.readSigned(bitDepth)
                right[i] = reader.readSigned(bitDepth)
            }
            return left to right
        }

        val shift = bytesShifted * 8
        val chanBits = config.bitDepth - shift + 1

        val mixBits = reader.readBits(8)
        val mixRes = reader.readSigned(8)

        reader.skipBits(4) // modeU
        val denShiftU = reader.readBits(4)
        val pbFactorU = reader.readBits(4)
        val numU = reader.readBits(5)
        val coefsU = IntArray(32)
        for (i in 0 until numU) {
            coefsU[i] = reader.readSigned(16)
        }

        reader.skipBits(4) // modeV
        val denShiftV = reader.readBits(4)
        val pbFactorV = reader.readBits(4)
        val numV = reader.readBits(5)
        val coefsV = IntArray(32)
        for (i in 0 until numV) {
            coefsV[i] = reader.readSigned(16)
        }

        var shiftU: IntArray? = null
        var shiftV: IntArray? = null
        if (bytesShifted != 0) {
            shiftU = IntArray(outputSamples)
            shiftV = IntArray(outputSamples)
            for (i in 0 until outputSamples) {
                shiftU[i] = reader.readBits(shift)
                shiftV[i] = reader.readBits(shift)
            }
        }

        val predU = IntArray(outputSamples)
        val predV = IntArray(outputSamples)
        dynDecomp(reader, predU, outputSamples, chanBits, pbFactorU)
        dynDecomp(reader, predV, outputSamples, chanBits, pbFactorV)

        val u = IntArray(outputSamples)
        val v = IntArray(outputSamples)
        unpcBlock(predU, u, outputSamples, coefsU, numU, chanBits, denShiftU)
        unpcBlock(predV, v, outputSamples, coefsV, numV, chanBits, denShiftV)

        if (mixRes != 0) {
            val mixResL = mixRes.toLong()
            for (i in 0 until outputSamples) {
                val vVal = v[i]
                val l = u[i] + vVal - ((mixResL * vVal.toLong()) shr mixBits).toInt()
                val r = l - vVal
                left[i] = l
                right[i] = r
            }
        } else {
            u.copyInto(left)
            v.copyInto(right)
        }

        if (shiftU != null && shiftV != null) {
            for (i in 0 until outputSamples) {
                left[i] = (left[i] shl shift) or shiftU[i]
                right[i] = (right[i] shl shift) or shiftV[i]
            }
        }

        return left to right
    }

    private fun dynDecomp(
        reader: BitReader,
        out: IntArray,
        numSamples: Int,
        maxSize: Int,
        pbFactor: Int
    ) {
        val pb = (pbFactor * config.pb) / 4
        val kb = config.kb
        var mb = config.mb
        var zmode = 0
        var c = 0

        while (c < numSamples) {
            val mShift = mb ushr QBSHIFT
            var k = 31 - (mShift + 3).countLeadingZeroBits()
            if (k > kb) k = kb
            val m = (1 shl k) - 1

            var n = dynGet(reader, m, k, maxSize) + zmode
            zmode = 0

            val del = (n ushr 1) xor -(n and 1)
            out[c++] = del

            mb = pb * n + mb - ((pb * mb) shr QBSHIFT)
            if (n > N_MAX_MEAN_CLAMP) {
                mb = N_MEAN_CLAMP_VAL
            }

            if ((mb shl MMULSHIFT) < QB && c < numSamples) {
                val kz = mb.countLeadingZeroBits() - BITOFF + ((mb + MOFF) shr MDENSHIFT)
                val mz = (1 shl kz) - 1
                val runLength = dynGet(reader, mz, kz, 16)
                if (runLength > 0) {
                    val zeroCount = min(runLength, numSamples - c)
                    for (i in 0 until zeroCount) {
                        out[c + i] = 0
                    }
                    c += zeroCount
                }
                zmode = if (runLength < 65535) 1 else 0
                mb = 0
            }
        }
    }

    private fun dynGet(reader: BitReader, m: Int, k: Int, maxBits: Int): Int {
        var prefix = 0
        while (prefix < MAX_PREFIX && reader.readBit() == 1) {
            prefix++
        }

        if (prefix == MAX_PREFIX) {
            return reader.readBits(maxBits)
        }

        if (k <= 0) {
            return 0
        }
        if (k == 1) {
            return prefix
        }

        var r = reader.readBits(k - 1)
        if (r != 0) {
            r = ((r shl 1) or reader.readBit()) - 1
        }
        return prefix * m + r
    }

    private fun unpcBlock(
        pc1: IntArray,
        out: IntArray,
        num: Int,
        coefs: IntArray,
        numActive: Int,
        chanBits: Int,
        denShift: Int
    ) {
        if (num <= 0) return

        if (numActive == 0) {
            pc1.copyInto(out, 0, 0, num)
            return
        }

        val shiftBits = 32 - chanBits
        if (numActive == 31) {
            out[0] = pc1[0]
            for (i in 1 until num) {
                val v = out[i - 1] + pc1[i]
                out[i] = (v shl shiftBits) shr shiftBits
            }
            return
        }

        out[0] = pc1[0]
        if (num == 1) return

        val warmupEnd = min(numActive, num - 1)
        for (i in 1..warmupEnd) {
            val v = out[i - 1] + pc1[i]
            out[i] = (v shl shiftBits) shr shiftBits
        }

        val round = if (denShift > 0) 1 shl (denShift - 1) else 0
        for (i in (numActive + 1) until num) {
            val base = out[i - numActive - 1]
            var sum = round
            for (k in 0 until numActive) {
                sum += (out[i - 1 - k] - base) * coefs[k]
            }

            val del = pc1[i]
            var del0 = del
            val predicted = base + (sum shr denShift) + del
            out[i] = (predicted shl shiftBits) shr shiftBits

            if (del0 > 0) {
                var k = 0
                while (k < numActive && del0 > 0) {
                    val diff = out[i - 1 - k] - base
                    if (diff > 0) {
                        coefs[k] = (coefs[k] + 1).toShort().toInt()
                        del0 -= (diff shr denShift) * (k + 1)
                    } else if (diff < 0) {
                        coefs[k] = (coefs[k] - 1).toShort().toInt()
                        del0 -= ((-diff) shr denShift) * (k + 1)
                    }
                    k++
                }
            } else if (del0 < 0) {
                var k = 0
                while (k < numActive && del0 < 0) {
                    val diff = out[i - 1 - k] - base
                    if (diff > 0) {
                        coefs[k] = (coefs[k] - 1).toShort().toInt()
                        del0 += (diff shr denShift) * (k + 1)
                    } else if (diff < 0) {
                        coefs[k] = (coefs[k] + 1).toShort().toInt()
                        del0 += ((-diff) shr denShift) * (k + 1)
                    }
                    k++
                }
            }
        }
    }

    private fun interleavePcm(channels: List<IntArray>, numSamples: Int): ByteArray {
        val numChannels = channels.size
        val out = ByteArray(numSamples * numChannels * bytesPerSample)
        var pos = 0

        when (bytesPerSample) {
            2 -> {
                for (i in 0 until numSamples) {
                    for (ch in 0 until numChannels) {
                        val s = channels[ch][i]
                        out[pos++] = s.toByte()
                        out[pos++] = (s shr 8).toByte()
                    }
                }
            }
            3 -> {
                for (i in 0 until numSamples) {
                    for (ch in 0 until numChannels) {
                        val s = channels[ch][i]
                        out[pos++] = s.toByte()
                        out[pos++] = (s shr 8).toByte()
                        out[pos++] = (s shr 16).toByte()
                    }
                }
            }
            else -> {
                for (i in 0 until numSamples) {
                    for (ch in 0 until numChannels) {
                        val s = channels[ch][i]
                        out[pos++] = s.toByte()
                        out[pos++] = (s shr 8).toByte()
                        out[pos++] = (s shr 16).toByte()
                        out[pos++] = (s shr 24).toByte()
                    }
                }
            }
        }
        return out
    }

    private class BitReader(
        private val data: ByteArray,
        private val startOffset: Int,
        length: Int
    ) {
        private var bitIndex = 0
        private val totalBits = length * 8

        fun bitsRemaining(): Int = totalBits - bitIndex

        fun readBit(): Int {
            if (bitIndex >= totalBits) return 0
            val byteVal = data[startOffset + (bitIndex ushr 3)].toInt() and 0xFF
            val shift = 7 - (bitIndex and 7)
            bitIndex++
            return (byteVal ushr shift) and 1
        }

        fun readBits(n: Int): Int {
            if (n == 0) return 0
            var remaining = n
            var result = 0
            while (remaining > 0) {
                if (bitIndex >= totalBits) {
                    result = result shl remaining
                    break
                }
                val bitInByte = bitIndex and 7
                val availInByte = 8 - bitInByte
                val take = min(remaining, availInByte)
                val byteVal = data[startOffset + (bitIndex ushr 3)].toInt() and 0xFF
                val shift = availInByte - take
                val mask = (1 shl take) - 1
                result = (result shl take) or ((byteVal ushr shift) and mask)
                bitIndex += take
                remaining -= take
            }
            return result
        }

        fun readSigned(n: Int): Int {
            if (n == 0) return 0
            val v = readBits(n)
            val shift = 32 - n
            return (v shl shift) shr shift
        }

        fun skipBits(n: Int) {
            bitIndex = min(totalBits, bitIndex + n)
        }

        fun byteAlign() {
            val rem = bitIndex and 7
            if (rem != 0) {
                skipBits(8 - rem)
            }
        }
    }

    private companion object {
        const val ID_SCE = 0
        const val ID_CPE = 1
        const val ID_LFE = 3
        const val ID_DSE = 4
        const val ID_FIL = 6
        const val ID_END = 7

        const val MAX_PREFIX = 9
        const val QBSHIFT = 9
        const val QB = 1 shl QBSHIFT
        const val MMULSHIFT = 2
        const val MDENSHIFT = QBSHIFT - MMULSHIFT - 1
        const val MOFF = 1 shl (MDENSHIFT - 2)
        const val BITOFF = 24
        const val N_MAX_MEAN_CLAMP = 0xFFFF
        const val N_MEAN_CLAMP_VAL = 0xFFFF
    }
}
