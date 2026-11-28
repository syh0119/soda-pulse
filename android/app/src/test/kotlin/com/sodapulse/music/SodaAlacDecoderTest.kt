package com.sodapulse.music

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

class SodaAlacDecoderTest {

    private class BitWriter {
        private val out = ByteArrayOutputStream()
        private var currentByte = 0
        private var bitPos = 0

        fun writeBits(value: Int, numBits: Int) {
            for (i in (numBits - 1) downTo 0) {
                val bit = (value ushr i) and 1
                currentByte = (currentByte shl 1) or bit
                bitPos++
                if (bitPos == 8) {
                    out.write(currentByte)
                    currentByte = 0
                    bitPos = 0
                }
            }
        }

        fun toByteArray(): ByteArray {
            if (bitPos > 0) {
                out.write(currentByte shl (8 - bitPos))
            }
            return out.toByteArray()
        }
    }

    private fun buildAlacCookie(
        frameLength: Int = 4,
        bitDepth: Int = 16,
        pb: Int = 40,
        mb: Int = 10,
        kb: Int = 14,
        channels: Int = 2,
        sampleRate: Int = 44100
    ): ByteArray {
        val buf = ByteBuffer.allocate(24).order(ByteOrder.BIG_ENDIAN)
        buf.putInt(frameLength)
        buf.put(0) // compatibleVersion
        buf.put(bitDepth.toByte())
        buf.put(pb.toByte())
        buf.put(mb.toByte())
        buf.put(kb.toByte())
        buf.put(channels.toByte())
        buf.putShort(255) // maxRun
        buf.putInt(0) // maxFrameBytes
        buf.putInt(0) // avgBitRate
        buf.putInt(sampleRate)
        return buf.array()
    }

    private fun box(type: String, payload: ByteArray): ByteArray {
        val buf = ByteBuffer.allocate(8 + payload.size).order(ByteOrder.BIG_ENDIAN)
        buf.putInt(8 + payload.size)
        buf.put(type.toByteArray(Charsets.US_ASCII))
        buf.put(payload)
        return buf.array()
    }

    private fun fullBox(type: String, version: Int, flags: Int, payload: ByteArray): ByteArray {
        val buf = ByteBuffer.allocate(4 + payload.size).order(ByteOrder.BIG_ENDIAN)
        buf.putInt(((version and 0xFF) shl 24) or (flags and 0xFFFFFF))
        buf.put(payload)
        return box(type, buf.array())
    }

    @Test
    fun parseCookie_supports24ByteRawAnd36ByteAtom() {
        val raw = buildAlacCookie(frameLength = 4096, bitDepth = 24, channels = 2, sampleRate = 96000)
        val cfg1 = AlacConfig.parse(raw)
        assertEquals(4096, cfg1.frameLength)
        assertEquals(24, cfg1.bitDepth)
        assertEquals(2, cfg1.numChannels)
        assertEquals(96000, cfg1.sampleRate)

        val atom36 = fullBox("alac", 0, 0, raw)
        assertEquals(36, atom36.size)
        val cfg2 = AlacConfig.parse(atom36)
        assertEquals(cfg1, cfg2)
    }

    @Test
    fun decode_uncompressed16BitAnd24BitStereoPackets() {
        // 16-bit stereo uncompressed (escapeFlag = 1)
        val cookie16 = buildAlacCookie(frameLength = 2, bitDepth = 16, channels = 2, sampleRate = 44100)
        val dec16 = SodaAlacDecoder(cookie16)
        val w16 = BitWriter().apply {
            writeBits(1, 3) // ID_CPE
            writeBits(0, 4) // tag
            writeBits(0, 12) // unused
            writeBits(1, 1) // hasSize = 1
            writeBits(0, 2) // bytesShifted = 0
            writeBits(1, 1) // escapeFlag = 1
            writeBits(2, 32) // 2 samples
            // Sample 0: L = 0x1234, R = -1000 (0xFC18)
            writeBits(0x1234, 16)
            writeBits(0xFC18, 16)
            // Sample 1: L = -32768 (0x8000), R = 32767 (0x7FFF)
            writeBits(0x8000, 16)
            writeBits(0x7FFF, 16)
            writeBits(7, 3) // ID_END
        }.toByteArray()

        val pcm16 = dec16.decode(w16)
        assertEquals(8, pcm16.size)
        val expected16 = ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN)
            .putShort(0x1234)
            .putShort((-1000).toShort())
            .putShort(Short.MIN_VALUE)
            .putShort(Short.MAX_VALUE)
            .array()
        assertArrayEquals(expected16, pcm16)

        // 24-bit stereo uncompressed (escapeFlag = 1)
        val cookie24 = buildAlacCookie(frameLength = 1, bitDepth = 24, channels = 2, sampleRate = 96000)
        val dec24 = SodaAlacDecoder(cookie24)
        val w24 = BitWriter().apply {
            writeBits(1, 3) // ID_CPE
            writeBits(0, 4)
            writeBits(0, 12)
            writeBits(0, 1) // hasSize = 0 -> use frameLength (1)
            writeBits(0, 2)
            writeBits(1, 1) // escapeFlag = 1
            writeBits(0x112233, 24)
            writeBits(0xFFFFFF, 24) // -1
            writeBits(7, 3)
        }.toByteArray()

        val pcm24 = dec24.decode(w24)
        assertArrayEquals(
            byteArrayOf(
                0x33, 0x22, 0x11,
                0xFF.toByte(), 0xFF.toByte(), 0xFF.toByte()
            ),
            pcm24
        )
    }

    @Test
    fun decode_compressedGolombRiceAndLpcStereoPacket() {
        // Test escapeFlag = 0, num = 0 (direct copy from dynDecomp), mixRes = 0, 2 samples mono (ID_SCE)
        // Using kb=14, mb=10, pb=40 -> initial k = 31 - clz((10 ushr 9)+3) = 31 - clz(3) = 1, m = 1
        // For k=1, dynGet returns prefix (count of 1-bits before 0-bit).
        // Zigzag: n=0 -> 0; n=1 -> -1; n=2 -> 1; n=4 -> 2
        val cookieMono = buildAlacCookie(frameLength = 2, bitDepth = 16, mb = 200, channels = 1, sampleRate = 44100)
        val decMono = SodaAlacDecoder(cookieMono)
        val compressedMono = BitWriter().apply {
            writeBits(0, 3) // ID_SCE
            writeBits(0, 4) // tag
            writeBits(0, 12) // unused
            writeBits(1, 1) // hasSize = 1
            writeBits(0, 2) // bytesShifted = 0
            writeBits(0, 1) // escapeFlag = 0 (compressed)
            writeBits(2, 32) // outputSamples = 2
            writeBits(0, 8) // mixBits
            writeBits(0, 8) // mixRes
            writeBits(0, 4) // mode
            writeBits(0, 4) // denShift
            writeBits(0, 4) // pbFactor
            writeBits(1, 5) // num = 1 (warmup out[1] = out[0] + pred[1])
            writeBits(0, 16) // coef[0]
            // Sample 0: n = 2 (two 1s + 0) -> del = +1; mb stays 10
            writeBits(0b110, 3)
            // Sample 1: next k = 31 - clz((90 ushr 9)+3) = 1; n = 4 (four 1s + 0) -> del = +2 -> out[1] = 1 + 2 = 3
            writeBits(0b11110, 5)
            writeBits(7, 3) // ID_END
        }.toByteArray()

        val pcm = decMono.decode(compressedMono)
        val expected = ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN)
            .putShort(1)
            .putShort(3)
            .array()
        assertArrayEquals(expected, pcm)
    }

    @Test
    fun mp4Parser_parsesSyntheticM4aAndDecodesPackets() {
        val cookie = buildAlacCookie(frameLength = 2, bitDepth = 16, channels = 2, sampleRate = 48000)

        fun makeUncompressedPacket(l0: Int, r0: Int, l1: Int, r1: Int): ByteArray {
            return BitWriter().apply {
                writeBits(1, 3)
                writeBits(0, 4)
                writeBits(0, 12)
                writeBits(1, 1)
                writeBits(0, 2)
                writeBits(1, 1)
                writeBits(2, 32)
                writeBits(l0 and 0xFFFF, 16)
                writeBits(r0 and 0xFFFF, 16)
                writeBits(l1 and 0xFFFF, 16)
                writeBits(r1 and 0xFFFF, 16)
                writeBits(7, 3)
            }.toByteArray()
        }

        val pkt0 = makeUncompressedPacket(100, -100, 200, -200)
        val pkt1 = makeUncompressedPacket(300, -300, 400, -400)
        val mdatData = pkt0 + pkt1

        val ftyp = box("ftyp", "M4A \u0000\u0000\u0000\u0000M4A mp42isom".toByteArray(Charsets.US_ASCII))

        // mdhd v0: created(4) + mod(4) + timescale(4) + duration(4) + lang(2) + qual(2) = 20B
        val mdhdPayload = ByteBuffer.allocate(20).order(ByteOrder.BIG_ENDIAN)
            .putInt(0).putInt(0).putInt(48000).putInt(4).putShort(0).putShort(0).array()
        val mdhd = fullBox("mdhd", 0, 0, mdhdPayload)

        // stsd: entryCount(4) + AudioSampleEntry('alac')
        val alacAtom = fullBox("alac", 0, 0, cookie)
        val audioEntryBody = ByteBuffer.allocate(28 + alacAtom.size).order(ByteOrder.BIG_ENDIAN).apply {
            put(ByteArray(6)) // reserved
            putShort(1) // dataRefIndex
            putInt(0); putInt(0) // reserved
            putShort(2) // channels
            putShort(16) // sampleSize
            putShort(0); putShort(0) // preDefined/reserved
            putInt(48000 shl 16) // sampleRate 16.16 fixed
            put(alacAtom)
        }.array()
        val alacEntry = box("alac", audioEntryBody)
        val stsd = fullBox("stsd", 0, 0, ByteBuffer.allocate(4 + alacEntry.size).order(ByteOrder.BIG_ENDIAN).putInt(1).put(alacEntry).array())

        val stts = fullBox("stts", 0, 0, ByteBuffer.allocate(12).order(ByteOrder.BIG_ENDIAN).putInt(1).putInt(2).putInt(2).array())
        val stsc = fullBox("stsc", 0, 0, ByteBuffer.allocate(16).order(ByteOrder.BIG_ENDIAN).putInt(1).putInt(1).putInt(2).putInt(1).array())
        val stsz = fullBox("stsz", 0, 0, ByteBuffer.allocate(16).order(ByteOrder.BIG_ENDIAN).putInt(0).putInt(2).putInt(pkt0.size).putInt(pkt1.size).array())

        // Compute mdat payload offset after ftyp + moov
        fun buildMoov(chunkOffset: Int): ByteArray {
            val stco = fullBox("stco", 0, 0, ByteBuffer.allocate(8).order(ByteOrder.BIG_ENDIAN).putInt(1).putInt(chunkOffset).array())
            val stbl = box("stbl", stsd + stts + stsc + stsz + stco)
            val minf = box("minf", stbl)
            val mdia = box("mdia", mdhd + minf)
            val trak = box("trak", mdia)
            return box("moov", trak)
        }

        val dummyMoov = buildMoov(0)
        val mdatOffset = ftyp.size + dummyMoov.size + 8
        val moov = buildMoov(mdatOffset)
        val mdat = box("mdat", mdatData)

        val tempFile = File.createTempFile("sodapulse_alac_test", ".m4a")
        try {
            tempFile.writeBytes(ftyp + moov + mdat)
            val info = SodaAlacMp4Parser.parse(tempFile)
            assertNotNull(info)
            info!!
            assertEquals(48000L, info.timescale)
            assertEquals(48000, info.sampleRate)
            assertEquals(2, info.channels)
            assertEquals(16, info.bitDepth)
            assertEquals(2, info.sampleOffsets.size)
            assertEquals(mdatOffset.toLong(), info.sampleOffsets[0])
            assertEquals((mdatOffset + pkt0.size).toLong(), info.sampleOffsets[1])

            val decoder = SodaAlacDecoder(info.alacCookie)
            val fileBytes = tempFile.readBytes()
            val decoded0 = decoder.decode(fileBytes, info.sampleOffsets[0].toInt(), info.sampleSizes[0])
            val decoded1 = decoder.decode(fileBytes, info.sampleOffsets[1].toInt(), info.sampleSizes[1])

            val exp0 = ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN)
                .putShort(100).putShort((-100).toShort()).putShort(200).putShort((-200).toShort()).array()
            val exp1 = ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN)
                .putShort(300).putShort((-300).toShort()).putShort(400).putShort((-400).toShort()).array()
            assertArrayEquals(exp0, decoded0)
            assertArrayEquals(exp1, decoded1)
        } finally {
            tempFile.delete()
        }
    }
}
