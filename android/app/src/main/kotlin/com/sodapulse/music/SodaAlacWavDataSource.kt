package com.sodapulse.music

import android.content.ContentResolver
import android.content.Context
import android.net.Uri
import android.os.ParcelFileDescriptor
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.PlaybackException
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSourceException
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.TransferListener
import java.io.File
import java.io.FileInputStream
import java.io.IOException
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.channels.FileChannel

@OptIn(UnstableApi::class)
class SodaAlacWavDataSource(
    private val context: Context,
    private val fallback: DataSource
) : DataSource {

    class Factory(
        private val context: Context,
        private val fallbackFactory: DataSource.Factory
    ) : DataSource.Factory {
        override fun createDataSource(): DataSource {
            return SodaAlacWavDataSource(
                context = context.applicationContext,
                fallback = fallbackFactory.createDataSource()
            )
        }
    }

    private val transferListeners = ArrayList<TransferListener>()

    private var usingFallback = false
    private var opened = false
    private var currentDataSpec: DataSpec? = null
    private var openedUri: Uri? = null

    private var trackInfo: AlacTrackInfo? = null
    private var decoder: SodaAlacDecoder? = null
    private var wavHeader: ByteArray? = null
    private var packetPcmStart: LongArray? = null

    private var raf: RandomAccessFile? = null
    private var pfd: ParcelFileDescriptor? = null
    private var fileChannel: FileChannel? = null

    private var position = 0L
    private var bytesRemaining = 0L

    private var cachedPacketIndex = -1
    private var cachedPcm: ByteArray? = null

    override fun addTransferListener(transferListener: TransferListener) {
        if (!transferListeners.contains(transferListener)) {
            transferListeners.add(transferListener)
        }
        fallback.addTransferListener(transferListener)
    }

    @Throws(IOException::class)
    override fun open(dataSpec: DataSpec): Long {
        val scheme = dataSpec.uri.scheme?.lowercase()
        if (scheme != ContentResolver.SCHEME_FILE && scheme != ContentResolver.SCHEME_CONTENT) {
            usingFallback = true
            return fallback.open(dataSpec)
        }

        val info = SodaAlacMp4Parser.parse(context, dataSpec.uri)
        if (info == null) {
            usingFallback = true
            return fallback.open(dataSpec)
        }

        usingFallback = false
        currentDataSpec = dataSpec
        openedUri = dataSpec.uri
        for (i in transferListeners.indices) {
            transferListeners[i].onTransferInitializing(this, dataSpec, false)
        }

        try {
            openBackingFile(dataSpec.uri, scheme)
            val alacDecoder = SodaAlacDecoder(info.alacCookie)

            val bytesPerSample = (info.bitDepth + 7) / 8
            val frameBytes = info.channels * bytesPerSample
            val starts = LongArray(info.sampleDurations.size + 1)
            var pcmBytes = 0L
            for (i in info.sampleDurations.indices) {
                starts[i] = pcmBytes
                pcmBytes += info.sampleDurations[i] * frameBytes
            }
            starts[info.sampleDurations.size] = pcmBytes

            val totalBytes = 44L + pcmBytes
            if (dataSpec.position > totalBytes) {
                throw DataSourceException(PlaybackException.ERROR_CODE_IO_READ_POSITION_OUT_OF_RANGE)
            }

            trackInfo = info
            decoder = alacDecoder
            packetPcmStart = starts
            wavHeader = buildWavHeader(
                totalBytes = totalBytes,
                pcmBytes = pcmBytes,
                sampleRate = info.sampleRate,
                channels = info.channels,
                bitDepth = info.bitDepth
            )

            position = dataSpec.position
            bytesRemaining = if (dataSpec.length != C.LENGTH_UNSET.toLong()) {
                minOf(dataSpec.length, totalBytes - position)
            } else {
                totalBytes - position
            }

            cachedPacketIndex = -1
            cachedPcm = null
            opened = true

            for (i in transferListeners.indices) {
                transferListeners[i].onTransferStart(this, dataSpec, false)
            }

            return if (dataSpec.length != C.LENGTH_UNSET.toLong()) {
                bytesRemaining
            } else {
                totalBytes - position
            }
        } catch (e: IOException) {
            releaseResources()
            throw e
        } catch (e: Exception) {
            releaseResources()
            throw IOException("Failed to open ALAC stream", e)
        }
    }

    @Throws(IOException::class)
    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
        if (usingFallback) {
            return fallback.read(buffer, offset, length)
        }
        if (length == 0) return 0
        if (bytesRemaining == 0L) return C.RESULT_END_OF_INPUT

        val header = wavHeader ?: return C.RESULT_END_OF_INPUT
        val starts = packetPcmStart ?: return C.RESULT_END_OF_INPUT
        val info = trackInfo ?: return C.RESULT_END_OF_INPUT

        val toRead = minOf(length.toLong(), bytesRemaining).toInt()
        var totalRead = 0

        while (totalRead < toRead) {
            if (position < 44L) {
                val hdrOff = position.toInt()
                val n = minOf(44 - hdrOff, toRead - totalRead)
                System.arraycopy(header, hdrOff, buffer, offset + totalRead, n)
                position += n
                totalRead += n
                bytesRemaining -= n
            } else {
                val pcmPos = position - 44L
                val packetIdx = if (
                    cachedPacketIndex >= 0 &&
                    cachedPacketIndex + 1 < starts.size &&
                    pcmPos >= starts[cachedPacketIndex] &&
                    pcmPos < starts[cachedPacketIndex + 1]
                ) {
                    cachedPacketIndex
                } else {
                    findPacketIndex(starts, pcmPos)
                }

                if (packetIdx != cachedPacketIndex || cachedPcm == null) {
                    cachedPcm = decodePacket(info, packetIdx)
                    cachedPacketIndex = packetIdx
                }

                val pcm = cachedPcm ?: break
                val inPacketOffset = (pcmPos - starts[packetIdx]).toInt()
                val availInPacket = pcm.size - inPacketOffset
                if (availInPacket <= 0) break

                val n = minOf(availInPacket, toRead - totalRead)
                System.arraycopy(pcm, inPacketOffset, buffer, offset + totalRead, n)
                position += n
                totalRead += n
                bytesRemaining -= n
            }
        }

        if (totalRead == 0) return C.RESULT_END_OF_INPUT

        val spec = currentDataSpec
        if (spec != null) {
            for (i in transferListeners.indices) {
                transferListeners[i].onBytesTransferred(this, spec, false, totalRead)
            }
        }
        return totalRead
    }

    override fun getUri(): Uri? {
        return if (usingFallback) fallback.uri else openedUri
    }

    override fun getResponseHeaders(): Map<String, List<String>> {
        return if (usingFallback) fallback.responseHeaders else emptyMap()
    }

    @Throws(IOException::class)
    override fun close() {
        if (usingFallback) {
            try {
                fallback.close()
            } finally {
                usingFallback = false
                openedUri = null
                currentDataSpec = null
            }
            return
        }

        try {
            releaseResources()
        } finally {
            if (opened) {
                opened = false
                val spec = currentDataSpec
                if (spec != null) {
                    for (i in transferListeners.indices) {
                        transferListeners[i].onTransferEnd(this, spec, false)
                    }
                }
            }
            openedUri = null
            currentDataSpec = null
        }
    }

    @Throws(IOException::class)
    private fun openBackingFile(uri: Uri, scheme: String) {
        when (scheme) {
            ContentResolver.SCHEME_FILE -> {
                val path = uri.path ?: throw IOException("Missing file path for URI: $uri")
                raf = RandomAccessFile(File(path), "r")
            }
            ContentResolver.SCHEME_CONTENT -> {
                val descriptor = context.contentResolver.openFileDescriptor(uri, "r")
                    ?: throw IOException("Unable to open ParcelFileDescriptor for URI: $uri")
                pfd = descriptor
                fileChannel = FileInputStream(descriptor.fileDescriptor).channel
            }
        }
    }

    @Throws(IOException::class)
    private fun decodePacket(info: AlacTrackInfo, packetIndex: Int): ByteArray {
        val packetSize = info.sampleSizes[packetIndex]
        val packetOffset = info.sampleOffsets[packetIndex]
        val encoded = ByteArray(packetSize)
        readPacketBytes(packetOffset, encoded, packetSize)
        val dec = decoder ?: throw IOException("ALAC decoder not initialized")
        return dec.decode(encoded)
    }

    @Throws(IOException::class)
    private fun readPacketBytes(offset: Long, dest: ByteArray, length: Int) {
        val r = raf
        if (r != null) {
            r.seek(offset)
            var total = 0
            while (total < length) {
                val read = r.read(dest, total, length - total)
                if (read < 0) throw IOException("Unexpected EOF reading ALAC packet")
                total += read
            }
            return
        }

        val ch = fileChannel ?: throw IOException("No backing file handle open")
        val bb = ByteBuffer.wrap(dest, 0, length)
        var pos = offset
        while (bb.hasRemaining()) {
            val read = ch.read(bb, pos)
            if (read < 0) throw IOException("Unexpected EOF reading ALAC packet")
            pos += read
        }
    }

    private fun releaseResources() {
        cachedPcm = null
        cachedPacketIndex = -1
        trackInfo = null
        decoder = null
        wavHeader = null
        packetPcmStart = null

        try {
            raf?.close()
        } catch (_: IOException) {
        } finally {
            raf = null
        }

        try {
            fileChannel?.close()
        } catch (_: IOException) {
        } finally {
            fileChannel = null
        }

        try {
            pfd?.close()
        } catch (_: IOException) {
        } finally {
            pfd = null
        }
    }

    private fun findPacketIndex(starts: LongArray, pcmPos: Long): Int {
        var low = 0
        var high = starts.size - 2
        while (low <= high) {
            val mid = (low + high) ushr 1
            val start = starts[mid]
            val end = starts[mid + 1]
            when {
                pcmPos < start -> high = mid - 1
                pcmPos >= end -> low = mid + 1
                else -> return mid
            }
        }
        return (starts.size - 2).coerceAtLeast(0)
    }

    private fun buildWavHeader(
        totalBytes: Long,
        pcmBytes: Long,
        sampleRate: Int,
        channels: Int,
        bitDepth: Int
    ): ByteArray {
        val bytesPerSample = (bitDepth + 7) / 8
        val blockAlign = channels * bytesPerSample
        val byteRate = sampleRate * blockAlign
        val riffChunkSize = (totalBytes - 8L).coerceAtMost(0xFFFFFFFFL).toInt()
        val dataChunkSize = pcmBytes.coerceAtMost(0xFFFFFFFFL).toInt()

        val bb = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
        bb.put('R'.code.toByte()).put('I'.code.toByte()).put('F'.code.toByte()).put('F'.code.toByte())
        bb.putInt(riffChunkSize)
        bb.put('W'.code.toByte()).put('A'.code.toByte()).put('V'.code.toByte()).put('E'.code.toByte())
        bb.put('f'.code.toByte()).put('m'.code.toByte()).put('t'.code.toByte()).put(' '.code.toByte())
        bb.putInt(16) // PCM subchunk1 size
        bb.putShort(1.toShort()) // AudioFormat = 1 (PCM)
        bb.putShort(channels.toShort())
        bb.putInt(sampleRate)
        bb.putInt(byteRate)
        bb.putShort(blockAlign.toShort())
        bb.putShort(bitDepth.toShort())
        bb.put('d'.code.toByte()).put('a'.code.toByte()).put('t'.code.toByte()).put('a'.code.toByte())
        bb.putInt(dataChunkSize)
        return bb.array()
    }
}
