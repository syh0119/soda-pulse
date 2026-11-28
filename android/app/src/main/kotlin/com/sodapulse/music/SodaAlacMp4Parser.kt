package com.sodapulse.music

import android.content.ContentResolver
import android.content.Context
import android.net.Uri
import java.io.File
import java.io.FileInputStream
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.nio.charset.StandardCharsets

data class AlacTrackInfo(
    val timescale: Long,
    val sampleRate: Int,
    val channels: Int,
    val bitDepth: Int,
    val alacCookie: ByteArray,
    val sampleOffsets: LongArray,
    val sampleSizes: IntArray,
    val sampleDurations: LongArray
)

object SodaAlacMp4Parser {

    private interface BoxReader {
        val length: Long
        fun readAt(position: Long, buffer: ByteArray, offset: Int, length: Int): Boolean
    }

    private class RafBoxReader(
        private val raf: RandomAccessFile,
        override val length: Long
    ) : BoxReader {
        override fun readAt(position: Long, buffer: ByteArray, offset: Int, length: Int): Boolean {
            if (position < 0L || length < 0 || position + length > this.length) return false
            raf.seek(position)
            var total = 0
            while (total < length) {
                val read = raf.read(buffer, offset + total, length - total)
                if (read <= 0) return false
                total += read
            }
            return true
        }
    }

    private class ChannelBoxReader(
        private val channel: FileChannel,
        override val length: Long
    ) : BoxReader {
        override fun readAt(position: Long, buffer: ByteArray, offset: Int, length: Int): Boolean {
            if (position < 0L || length < 0 || position + length > this.length) return false
            val bb = ByteBuffer.wrap(buffer, offset, length)
            var pos = position
            while (bb.hasRemaining()) {
                val read = channel.read(bb, pos)
                if (read <= 0) return false
                pos += read
            }
            return true
        }
    }

    private data class BoxHeader(
        val type: String,
        val payloadStart: Long,
        val end: Long
    )

    private data class StscEntry(
        val firstChunk: Long,
        val samplesPerChunk: Long
    )

    private data class SttsEntry(
        val sampleCount: Long,
        val sampleDelta: Long
    )

    private data class AlacSampleEntry(
        val cookie: ByteArray,
        val sampleRate: Int,
        val channels: Int,
        val bitDepth: Int
    )

    fun parse(file: File): AlacTrackInfo? {
        if (!file.isFile || !file.canRead()) return null
        return try {
            RandomAccessFile(file, "r").use { raf ->
                parse(raf, raf.length())
            }
        } catch (_: Exception) {
            null
        }
    }

    fun parse(raf: RandomAccessFile, fileLength: Long): AlacTrackInfo? {
        if (fileLength <= 8L) return null
        return try {
            parse(RafBoxReader(raf, fileLength))
        } catch (_: Exception) {
            null
        }
    }

    fun parse(context: Context, uri: Uri): AlacTrackInfo? {
        return try {
            when (uri.scheme?.lowercase()) {
                ContentResolver.SCHEME_FILE -> {
                    val path = uri.path ?: return null
                    parse(File(path))
                }
                ContentResolver.SCHEME_CONTENT -> {
                    context.contentResolver.openAssetFileDescriptor(uri, "r")?.use { afd ->
                        FileInputStream(afd.fileDescriptor).channel.use { channel ->
                            val len = if (afd.length >= 0L) afd.length else channel.size()
                            if (len <= 8L) return null
                            parse(ChannelBoxReader(channel, len))
                        }
                    }
                }
                else -> null
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun parse(reader: BoxReader): AlacTrackInfo? {
        val moov = findChildBox(reader, 0L, reader.length, "moov") ?: return null
        var pos = moov.payloadStart
        while (pos < moov.end) {
            val child = readBoxHeader(reader, pos, moov.end) ?: break
            if (child.type == "trak") {
                val track = parseTrak(reader, child.payloadStart, child.end)
                if (track != null) return track
            }
            pos = child.end
        }
        return null
    }

    private fun parseTrak(reader: BoxReader, start: Long, end: Long): AlacTrackInfo? {
        val mdia = findChildBox(reader, start, end, "mdia") ?: return null
        val mdhd = findChildBox(reader, mdia.payloadStart, mdia.end, "mdhd") ?: return null
        val timescale = parseMdhdTimescale(reader, mdhd.payloadStart, mdhd.end) ?: return null
        if (timescale <= 0L) return null

        val minf = findChildBox(reader, mdia.payloadStart, mdia.end, "minf") ?: return null
        val stbl = findChildBox(reader, minf.payloadStart, minf.end, "stbl") ?: return null
        return parseStbl(reader, stbl.payloadStart, stbl.end, timescale)
    }

    private fun parseMdhdTimescale(reader: BoxReader, start: Long, end: Long): Long? {
        val size = (end - start).toInt()
        if (size < 20) return null
        val buf = readBytes(reader, start, minOf(size, 32)) ?: return null
        val version = buf[0].toInt() and 0xFF
        return when (version) {
            0 -> if (buf.size >= 16) readUInt32(buf, 12) else null
            1 -> if (buf.size >= 24) readUInt32(buf, 20) else null
            else -> null
        }
    }

    private fun parseStbl(
        reader: BoxReader,
        start: Long,
        end: Long,
        timescale: Long
    ): AlacTrackInfo? {
        var alacEntry: AlacSampleEntry? = null
        var sttsEntries: List<SttsEntry>? = null
        var stscEntries: List<StscEntry>? = null
        var sampleSizes: IntArray? = null
        var chunkOffsets: LongArray? = null

        var pos = start
        while (pos < end) {
            val box = readBoxHeader(reader, pos, end) ?: break
            when (box.type) {
                "stsd" -> alacEntry = parseStsdForAlac(reader, box.payloadStart, box.end)
                "stts" -> sttsEntries = parseStts(reader, box.payloadStart, box.end)
                "stsc" -> stscEntries = parseStsc(reader, box.payloadStart, box.end)
                "stsz" -> sampleSizes = parseStsz(reader, box.payloadStart, box.end)
                "stco" -> chunkOffsets = parseStco(reader, box.payloadStart, box.end)
                "co64" -> chunkOffsets = parseCo64(reader, box.payloadStart, box.end)
            }
            pos = box.end
        }

        val entry = alacEntry ?: return null
        val sizes = sampleSizes ?: return null
        val chunks = chunkOffsets ?: return null
        val stsc = stscEntries ?: return null
        val stts = sttsEntries ?: return null
        if (sizes.isEmpty() || chunks.isEmpty() || stsc.isEmpty() || stts.isEmpty()) return null

        val sampleCount = sizes.size
        val sampleOffsets = buildSampleOffsets(sampleCount, sizes, chunks, stsc) ?: return null
        val sampleDurations = buildSampleDurations(sampleCount, stts) ?: return null

        return AlacTrackInfo(
            timescale = timescale,
            sampleRate = entry.sampleRate,
            channels = entry.channels,
            bitDepth = entry.bitDepth,
            alacCookie = entry.cookie,
            sampleOffsets = sampleOffsets,
            sampleSizes = sizes,
            sampleDurations = sampleDurations
        )
    }

    private fun parseStsdForAlac(reader: BoxReader, start: Long, end: Long): AlacSampleEntry? {
        if (end - start < 8L) return null
        val header = readBytes(reader, start, 8) ?: return null
        val entryCount = readUInt32(header, 4)
        var pos = start + 8L
        var i = 0L
        while (i < entryCount && pos < end) {
            val entryBox = readBoxHeader(reader, pos, end) ?: break
            if (entryBox.type == "alac") {
                val parsed = parseAlacSampleEntry(reader, entryBox.payloadStart, entryBox.end)
                if (parsed != null) return parsed
            }
            pos = entryBox.end
            i++
        }
        return null
    }

    private fun parseAlacSampleEntry(
        reader: BoxReader,
        payloadStart: Long,
        end: Long
    ): AlacSampleEntry? {
        // AudioSampleEntry v0 is 28 bytes after the 8-byte sample entry box header
        if (end - payloadStart < 28L) return null
        val baseHeader = readBytes(reader, payloadStart, 28) ?: return null
        val version = readUInt16(baseHeader, 8)
        val extraBytes = when (version) {
            0 -> 0L
            1 -> 16L
            2 -> 36L
            else -> return null
        }

        val childStart = payloadStart + 28L + extraBytes
        if (childStart >= end) return null

        val alacBox = findAlacCookieBox(reader, childStart, end) ?: return null
        val boxLen = (alacBox.end - alacBox.payloadStart).toInt()
        if (boxLen < 24 || boxLen > 64) return null
        val payload = readBytes(reader, alacBox.payloadStart, boxLen) ?: return null

        val validCookie = validateAlacCookie(payload) ?: return null
        val configOffset = validCookie.size - 24
        if (configOffset < 0) return null

        val bitDepth = validCookie[configOffset + 5].toInt() and 0xFF
        val channels = validCookie[configOffset + 9].toInt() and 0xFF
        val sampleRate = readUInt32(validCookie, configOffset + 20).toInt()
        if (bitDepth <= 0 || channels <= 0 || sampleRate <= 0) return null

        return AlacSampleEntry(
            cookie = validCookie,
            sampleRate = sampleRate,
            channels = channels,
            bitDepth = bitDepth
        )
    }

    private fun findAlacCookieBox(reader: BoxReader, start: Long, end: Long): BoxHeader? {
        var pos = start
        while (pos < end) {
            val child = readBoxHeader(reader, pos, end) ?: break
            when (child.type) {
                "alac" -> return child
                "wave" -> {
                    val nested = findChildBox(reader, child.payloadStart, child.end, "alac")
                    if (nested != null) return nested
                }
            }
            pos = child.end
        }
        return null
    }

    private fun validateAlacCookie(payload: ByteArray): ByteArray? {
        val candidates = ArrayList<ByteArray>(3)
        candidates.add(payload)
        if (payload.size == 28) {
            candidates.add(payload.copyOfRange(4, 28))
        } else if (payload.size == 36) {
            candidates.add(payload.copyOfRange(8, 36))
            candidates.add(payload.copyOfRange(12, 36))
        }
        for (candidate in candidates) {
            val parsed = runCatching { AlacConfig.parse(candidate) }.getOrNull()
            if (parsed != null) return candidate
        }
        return null
    }

    private fun parseStts(reader: BoxReader, start: Long, end: Long): List<SttsEntry>? {
        if (end - start < 8L) return null
        val hdr = readBytes(reader, start, 8) ?: return null
        val count = readUInt32(hdr, 4)
        if (count <= 0L || count > 10_000_000L) return null
        val tableBytes = (count * 8L).toInt()
        if (start + 8L + tableBytes > end) return null
        val data = readBytes(reader, start + 8L, tableBytes) ?: return null
        val result = ArrayList<SttsEntry>(count.toInt())
        for (i in 0 until count.toInt()) {
            val off = i * 8
            result.add(
                SttsEntry(
                    sampleCount = readUInt32(data, off),
                    sampleDelta = readUInt32(data, off + 4)
                )
            )
        }
        return result
    }

    private fun parseStsc(reader: BoxReader, start: Long, end: Long): List<StscEntry>? {
        if (end - start < 8L) return null
        val hdr = readBytes(reader, start, 8) ?: return null
        val count = readUInt32(hdr, 4)
        if (count <= 0L || count > 10_000_000L) return null
        val tableBytes = (count * 12L).toInt()
        if (start + 8L + tableBytes > end) return null
        val data = readBytes(reader, start + 8L, tableBytes) ?: return null
        val result = ArrayList<StscEntry>(count.toInt())
        for (i in 0 until count.toInt()) {
            val off = i * 12
            result.add(
                StscEntry(
                    firstChunk = readUInt32(data, off),
                    samplesPerChunk = readUInt32(data, off + 4)
                )
            )
        }
        return result
    }

    private fun parseStsz(reader: BoxReader, start: Long, end: Long): IntArray? {
        if (end - start < 12L) return null
        val hdr = readBytes(reader, start, 12) ?: return null
        val uniformSize = readUInt32(hdr, 4)
        val sampleCount = readUInt32(hdr, 8)
        if (sampleCount <= 0L || sampleCount > 50_000_000L) return null
        val count = sampleCount.toInt()
        if (uniformSize > 0L) {
            return IntArray(count) { uniformSize.toInt() }
        }
        val tableBytes = count * 4
        if (start + 12L + tableBytes > end) return null
        val data = readBytes(reader, start + 12L, tableBytes) ?: return null
        return IntArray(count) { i ->
            readUInt32(data, i * 4).toInt()
        }
    }

    private fun parseStco(reader: BoxReader, start: Long, end: Long): LongArray? {
        if (end - start < 8L) return null
        val hdr = readBytes(reader, start, 8) ?: return null
        val count = readUInt32(hdr, 4)
        if (count <= 0L || count > 50_000_000L) return null
        val tableBytes = (count * 4L).toInt()
        if (start + 8L + tableBytes > end) return null
        val data = readBytes(reader, start + 8L, tableBytes) ?: return null
        return LongArray(count.toInt()) { i ->
            readUInt32(data, i * 4)
        }
    }

    private fun parseCo64(reader: BoxReader, start: Long, end: Long): LongArray? {
        if (end - start < 8L) return null
        val hdr = readBytes(reader, start, 8) ?: return null
        val count = readUInt32(hdr, 4)
        if (count <= 0L || count > 50_000_000L) return null
        val tableBytes = (count * 8L).toInt()
        if (start + 8L + tableBytes > end) return null
        val data = readBytes(reader, start + 8L, tableBytes) ?: return null
        return LongArray(count.toInt()) { i ->
            readUInt64(data, i * 8)
        }
    }

    private fun buildSampleOffsets(
        sampleCount: Int,
        sampleSizes: IntArray,
        chunkOffsets: LongArray,
        stsc: List<StscEntry>
    ): LongArray? {
        val offsets = LongArray(sampleCount)
        var sampleIdx = 0
        var stscIdx = 0

        for (chunkIdx in chunkOffsets.indices) {
            val oneBasedChunk = chunkIdx + 1L
            while (stscIdx + 1 < stsc.size && oneBasedChunk >= stsc[stscIdx + 1].firstChunk) {
                stscIdx++
            }
            val samplesInChunk = stsc[stscIdx].samplesPerChunk
            var offset = chunkOffsets[chunkIdx]
            var s = 0L
            while (s < samplesInChunk && sampleIdx < sampleCount) {
                offsets[sampleIdx] = offset
                offset += sampleSizes[sampleIdx].toLong()
                sampleIdx++
                s++
            }
            if (sampleIdx >= sampleCount) break
        }
        return if (sampleIdx == sampleCount) offsets else null
    }

    private fun buildSampleDurations(sampleCount: Int, stts: List<SttsEntry>): LongArray? {
        val durations = LongArray(sampleCount)
        var idx = 0
        for (entry in stts) {
            var c = 0L
            while (c < entry.sampleCount && idx < sampleCount) {
                durations[idx++] = entry.sampleDelta
                c++
            }
            if (idx >= sampleCount) break
        }
        return if (idx == sampleCount) durations else null
    }

    private fun findChildBox(
        reader: BoxReader,
        start: Long,
        end: Long,
        targetType: String
    ): BoxHeader? {
        var pos = start
        while (pos < end) {
            val box = readBoxHeader(reader, pos, end) ?: break
            if (box.type == targetType) return box
            pos = box.end
        }
        return null
    }

    private fun readBoxHeader(reader: BoxReader, pos: Long, limit: Long): BoxHeader? {
        if (pos + 8L > limit) return null
        val buf = readBytes(reader, pos, 8) ?: return null
        val size32 = readUInt32(buf, 0)
        val type = String(buf, 4, 4, StandardCharsets.ISO_8859_1)

        var headerSize = 8L
        val boxSize: Long = when (size32) {
            0L -> limit - pos
            1L -> {
                if (pos + 16L > limit) return null
                val ext = readBytes(reader, pos + 8L, 8) ?: return null
                headerSize = 16L
                readUInt64(ext, 0)
            }
            else -> size32
        }

        if (boxSize < headerSize) return null
        val boxEnd = pos + boxSize
        if (boxEnd > limit) return null

        return BoxHeader(type = type, payloadStart = pos + headerSize, end = boxEnd)
    }

    private fun readBytes(reader: BoxReader, position: Long, length: Int): ByteArray? {
        if (length < 0) return null
        val buf = ByteArray(length)
        return if (reader.readAt(position, buf, 0, length)) buf else null
    }

    private fun readUInt16(buf: ByteArray, offset: Int): Int {
        return ((buf[offset].toInt() and 0xFF) shl 8) or
            (buf[offset + 1].toInt() and 0xFF)
    }

    private fun readUInt32(buf: ByteArray, offset: Int): Long {
        return ((buf[offset].toLong() and 0xFFL) shl 24) or
            ((buf[offset + 1].toLong() and 0xFFL) shl 16) or
            ((buf[offset + 2].toLong() and 0xFFL) shl 8) or
            (buf[offset + 3].toLong() and 0xFFL)
    }

    private fun readUInt64(buf: ByteArray, offset: Int): Long {
        return ((buf[offset].toLong() and 0xFFL) shl 56) or
            ((buf[offset + 1].toLong() and 0xFFL) shl 48) or
            ((buf[offset + 2].toLong() and 0xFFL) shl 40) or
            ((buf[offset + 3].toLong() and 0xFFL) shl 32) or
            ((buf[offset + 4].toLong() and 0xFFL) shl 24) or
            ((buf[offset + 5].toLong() and 0xFFL) shl 16) or
            ((buf[offset + 6].toLong() and 0xFFL) shl 8) or
            (buf[offset + 7].toLong() and 0xFFL)
    }
}
