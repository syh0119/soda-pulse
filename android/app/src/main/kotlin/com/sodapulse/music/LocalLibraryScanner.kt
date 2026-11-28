package com.sodapulse.music

import android.content.ContentUris
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Size
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import kotlin.math.PI
import kotlin.math.sin

object LocalLibraryScanner {

    private val LYRIC_PRIORITY = listOf("yrc", "qrc", "krc", "elrc", "lrc")

    fun scanAudio(context: Context): List<Map<String, Any?>> {
        val results = mutableListOf<Map<String, Any?>>()
        val contentResolver = context.contentResolver
        val collection = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI

        @Suppress("DEPRECATION")
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.ALBUM_ID,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.DATA
        )

        val selection = "${MediaStore.Audio.Media.IS_MUSIC} != 0 AND ${MediaStore.Audio.Media.DURATION} >= 5000"
        val sortOrder = "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE ASC"

        contentResolver.query(
            collection,
            projection,
            selection,
            null,
            sortOrder
        )?.use { cursor ->
            val idCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val titleCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val artistCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val albumCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val albumIdCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM_ID)
            val durationCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            @Suppress("DEPRECATION")
            val dataCol = cursor.getColumnIndex(MediaStore.Audio.Media.DATA)

            while (cursor.moveToNext()) {
                val id = cursor.getLong(idCol)
                val title = cursor.getString(titleCol)?.takeIf { it.isNotBlank() } ?: "Unknown Title"
                val artist = cursor.getString(artistCol)?.takeIf { it.isNotBlank() && it != "<unknown>" }
                    ?: "Unknown Artist"
                val album = cursor.getString(albumCol)?.takeIf { it.isNotBlank() && it != "<unknown>" }
                    ?: "Unknown Album"
                val albumId = cursor.getLong(albumIdCol)
                val durationMs = cursor.getLong(durationCol)
                val filePath = if (dataCol >= 0) cursor.getString(dataCol) else null
                val contentUri = ContentUris.withAppendedId(collection, id).toString()
                val albumArtUri = "content://media/external/audio/albumart/$albumId"

                results.add(
                    mapOf(
                        "id" to id,
                        "title" to title,
                        "artist" to artist,
                        "album" to album,
                        "durationMs" to durationMs,
                        "uri" to contentUri,
                        "filePath" to filePath,
                        "albumArtUri" to albumArtUri
                    )
                )
            }
        }

        return results
    }

    fun readSidecarLyrics(
        context: Context,
        filePath: String?,
        uri: String?
    ): Map<String, Any?> {
        val resolvedPath = filePath?.takeIf { it.isNotBlank() }
            ?: resolveFilePathFromUri(context, uri)

        var rawContent: String? = null
        var formatHint: String? = null
        var sourceLabel: String? = null
        var translationContent: String? = null
        var romaContent: String? = null

        if (!resolvedPath.isNullOrBlank()) {
            val audioFile = File(resolvedPath)
            val parentDir = audioFile.parentFile
            val baseName = audioFile.nameWithoutExtension
            if (parentDir != null && parentDir.exists() && parentDir.isDirectory && baseName.isNotBlank()) {
                for (ext in LYRIC_PRIORITY) {
                    val candidate = File(parentDir, "$baseName.$ext")
                    if (candidate.exists() && candidate.isFile && candidate.canRead()) {
                        val text = readFileTextSafely(candidate)
                        if (!text.isNullOrBlank()) {
                            rawContent = text
                            formatHint = ext
                            sourceLabel = candidate.absolutePath
                            break
                        }
                    }
                }

                val translationFile = File(parentDir, "$baseName.t.lrc")
                if (translationFile.exists() && translationFile.isFile && translationFile.canRead()) {
                    translationContent = readFileTextSafely(translationFile)?.takeIf { it.isNotBlank() }
                }

                val romaFile = File(parentDir, "$baseName.roma.lrc")
                if (romaFile.exists() && romaFile.isFile && romaFile.canRead()) {
                    romaContent = readFileTextSafely(romaFile)?.takeIf { it.isNotBlank() }
                }
            }
        }

        if (rawContent.isNullOrBlank()) {
            val embedded = extractEmbeddedLyrics(context, resolvedPath, uri)
            if (embedded != null && embedded.raw.isNotBlank()) {
                rawContent = embedded.raw
                formatHint = "embedded"
                sourceLabel = embedded.source
                if (translationContent.isNullOrBlank() && !embedded.translation.isNullOrBlank()) {
                    translationContent = embedded.translation
                }
            }
        }

        return mapOf(
            "raw" to rawContent,
            "formatHint" to formatHint,
            "translation" to translationContent,
            "roma" to romaContent,
            "source" to (sourceLabel ?: if (translationContent != null || romaContent != null) "sidecar-aux" else "none")
        )
    }

    fun prepareDemoAudio(context: Context): Map<String, Any?> {
        val demoDir = File(context.cacheDir, "demo")
        if (!demoDir.exists()) {
            demoDir.mkdirs()
        }
        val wavFile = File(demoDir, "sodapulse_demo.wav")

        val sampleRate = 44100
        val channels = 2
        val bitsPerSample = 16
        val durationSec = 25
        val totalFrames = sampleRate * durationSec
        val dataSize = totalFrames * channels * (bitsPerSample / 8)
        val expectedFileSize = 44L + dataSize.toLong()

        if (!wavFile.exists() || wavFile.length() != expectedFileSize) {
            generateChordWav(wavFile, sampleRate, channels, bitsPerSample, durationSec)
        }

        return mapOf(
            "id" to -1001L,
            "title" to "SodaPulse Breeze (Demo)",
            "artist" to "SodaPulse Synth",
            "album" to "Built-in Demo",
            "durationMs" to (durationSec * 1000L),
            "uri" to Uri.fromFile(wavFile).toString(),
            "filePath" to wavFile.absolutePath,
            "albumArtUri" to null
        )
    }

    private fun generateChordWav(
        outFile: File,
        sampleRate: Int,
        channels: Int,
        bitsPerSample: Int,
        durationSec: Int
    ) {
        val totalFrames = sampleRate * durationSec
        val dataSize = totalFrames * channels * (bitsPerSample / 8)
        val byteRate = sampleRate * channels * (bitsPerSample / 8)
        val blockAlign = channels * (bitsPerSample / 8)

        // Soft 4-chord ambient progression (Cmaj9 -> Am9 -> Fmaj9 -> G6), ~6.25s per chord
        val chords = arrayOf(
            doubleArrayOf(261.63, 329.63, 392.00, 493.88, 587.33), // Cmaj9
            doubleArrayOf(220.00, 261.63, 329.63, 392.00, 493.88), // Am9
            doubleArrayOf(174.61, 220.00, 261.63, 329.63, 392.00), // Fmaj9
            doubleArrayOf(196.00, 246.94, 293.66, 329.63, 440.00)  // G6
        )

        val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN).apply {
            put("RIFF".toByteArray(Charsets.US_ASCII))
            putInt(36 + dataSize)
            put("WAVE".toByteArray(Charsets.US_ASCII))
            put("fmt ".toByteArray(Charsets.US_ASCII))
            putInt(16) // PCM subchunk1Size
            putShort(1.toShort()) // AudioFormat = 1 (PCM)
            putShort(channels.toShort())
            putInt(sampleRate)
            putInt(byteRate)
            putShort(blockAlign.toShort())
            putShort(bitsPerSample.toShort())
            put("data".toByteArray(Charsets.US_ASCII))
            putInt(dataSize)
        }

        val framesPerChunk = 4096
        val chunkBuffer = ByteBuffer.allocate(framesPerChunk * blockAlign).order(ByteOrder.LITTLE_ENDIAN)
        val chordDurationSec = durationSec.toDouble() / chords.size

        BufferedOutputStream(FileOutputStream(outFile)).use { bos ->
            bos.write(header.array())

            var frameIndex = 0
            while (frameIndex < totalFrames) {
                chunkBuffer.clear()
                val framesInThisChunk = minOf(framesPerChunk, totalFrames - frameIndex)

                for (i in 0 until framesInThisChunk) {
                    val t = (frameIndex + i).toDouble() / sampleRate.toDouble()
                    val chordPos = (t / chordDurationSec).toInt().coerceIn(0, chords.lastIndex)
                    val localT = t - chordPos * chordDurationSec
                    val chord = chords[chordPos]

                    // Smooth chord envelope + global fade-in/fade-out
                    val chordFadeIn = (localT / 0.6).coerceIn(0.0, 1.0)
                    val chordFadeOut = ((chordDurationSec - localT) / 0.6).coerceIn(0.0, 1.0)
                    val globalFadeIn = (t / 1.0).coerceIn(0.0, 1.0)
                    val globalFadeOut = ((durationSec - t) / 1.5).coerceIn(0.0, 1.0)
                    val env = chordFadeIn * chordFadeOut * globalFadeIn * globalFadeOut

                    var left = 0.0
                    var right = 0.0
                    for (n in chord.indices) {
                        val freq = chord[n]
                        val detune = 1.0 + (n - 2) * 0.0012
                        val pan = (n.toDouble() / (chord.size - 1).coerceAtLeast(1)) // 0.0 .. 1.0
                        val fundamental = sin(2.0 * PI * freq * t)
                        val warmHarmonic = 0.25 * sin(2.0 * PI * (freq * 2.0 * detune) * t)
                        val voice = (fundamental + warmHarmonic) / chord.size
                        left += voice * (1.0 - pan * 0.35)
                        right += voice * (0.65 + pan * 0.35)
                    }

                    // Gentle amplitude scaling to prevent clipping
                    val masterGain = 0.42 * env
                    val leftSample = (left * masterGain * Short.MAX_VALUE).toInt()
                        .coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
                    val rightSample = (right * masterGain * Short.MAX_VALUE).toInt()
                        .coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()

                    chunkBuffer.putShort(leftSample)
                    chunkBuffer.putShort(rightSample)
                }

                bos.write(chunkBuffer.array(), 0, framesInThisChunk * blockAlign)
                frameIndex += framesInThisChunk
            }
            bos.flush()
        }
    }

    private fun resolveFilePathFromUri(context: Context, uriString: String?): String? {
        if (uriString.isNullOrBlank()) return null
        val parsed = Uri.parse(uriString)
        if (parsed.scheme == "file") {
            return parsed.path
        }
        if (parsed.scheme == "content") {
            @Suppress("DEPRECATION")
            val projection = arrayOf(MediaStore.Audio.Media.DATA)
            try {
                context.contentResolver.query(parsed, projection, null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        @Suppress("DEPRECATION")
                        val idx = cursor.getColumnIndex(MediaStore.Audio.Media.DATA)
                        if (idx >= 0) {
                            return cursor.getString(idx)
                        }
                    }
                }
            } catch (_: Exception) {
                return null
            }
        }
        return null
    }

    private fun readFileTextSafely(file: File): String? {
        return try {
            file.readText(Charsets.UTF_8)
        } catch (_: Exception) {
            null
        }
    }

    private fun emptyLyricResult(): Map<String, Any?> {
        return mapOf(
            "raw" to null,
            "formatHint" to null,
            "translation" to null,
            "roma" to null,
            "source" to "none"
        )
    }

    fun loadCoverBitmap(context: Context, uriString: String?, maxSize: Int = 512): Bitmap? {
        if (uriString.isNullOrBlank() || maxSize <= 0) return null
        val trimmed = uriString.trim()

        fun calculateInSampleSize(width: Int, height: Int): Int {
            var inSampleSize = 1
            val minDim = minOf(width, height)
            while (minDim / (inSampleSize * 2) >= maxSize) {
                inSampleSize *= 2
            }
            return inSampleSize
        }

        val decoded: Bitmap? = try {
            when {
                trimmed.startsWith("http://", ignoreCase = true) ||
                    trimmed.startsWith("https://", ignoreCase = true) -> {
                    var connection: HttpURLConnection? = null
                    try {
                        connection = (URL(trimmed).openConnection() as HttpURLConnection).apply {
                            connectTimeout = 5000
                            readTimeout = 5000
                            instanceFollowRedirects = true
                            setRequestProperty("User-Agent", "Mozilla/5.0")
                            if (trimmed.contains("music.126.net", ignoreCase = true)) {
                                setRequestProperty("Referer", "https://music.163.com/")
                            }
                        }
                        if (connection.responseCode !in 200..299) {
                            null
                        } else {
                            val bytes = connection.inputStream.use { it.readBytes() }
                            val boundsOpts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, boundsOpts)
                            if (boundsOpts.outWidth <= 0 || boundsOpts.outHeight <= 0) {
                                null
                            } else {
                                val decodeOpts = BitmapFactory.Options().apply {
                                    inSampleSize = calculateInSampleSize(boundsOpts.outWidth, boundsOpts.outHeight)
                                }
                                BitmapFactory.decodeByteArray(bytes, 0, bytes.size, decodeOpts)
                            }
                        }
                    } finally {
                        connection?.disconnect()
                    }
                }

                trimmed.startsWith("content://", ignoreCase = true) -> {
                    val uri = Uri.parse(trimmed)
                    var bmp: Bitmap? = try {
                        val boundsOpts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                        context.contentResolver.openInputStream(uri)?.use {
                            BitmapFactory.decodeStream(it, null, boundsOpts)
                        }
                        if (boundsOpts.outWidth > 0 && boundsOpts.outHeight > 0) {
                            val decodeOpts = BitmapFactory.Options().apply {
                                inSampleSize = calculateInSampleSize(boundsOpts.outWidth, boundsOpts.outHeight)
                            }
                            context.contentResolver.openInputStream(uri)?.use {
                                BitmapFactory.decodeStream(it, null, decodeOpts)
                            }
                        } else {
                            null
                        }
                    } catch (_: Exception) {
                        null
                    }

                    if (bmp == null &&
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
                        trimmed.startsWith("content://media/external/audio/albumart", ignoreCase = true)
                    ) {
                        bmp = try {
                            context.contentResolver.loadThumbnail(uri, Size(maxSize, maxSize), null)
                        } catch (_: Exception) {
                            null
                        }
                    }
                    bmp
                }

                trimmed.startsWith("file://", ignoreCase = true) || trimmed.startsWith("/") -> {
                    val path = if (trimmed.startsWith("file://", ignoreCase = true)) {
                        Uri.parse(trimmed).path
                    } else {
                        trimmed
                    }
                    if (path.isNullOrBlank()) {
                        null
                    } else {
                        val file = File(path)
                        if (!file.exists() || !file.isFile) {
                            null
                        } else {
                            val boundsOpts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                            BitmapFactory.decodeFile(path, boundsOpts)
                            if (boundsOpts.outWidth <= 0 || boundsOpts.outHeight <= 0) {
                                null
                            } else {
                                val decodeOpts = BitmapFactory.Options().apply {
                                    inSampleSize = calculateInSampleSize(boundsOpts.outWidth, boundsOpts.outHeight)
                                }
                                BitmapFactory.decodeFile(path, decodeOpts)
                            }
                        }
                    }
                }

                else -> null
            }
        } catch (_: OutOfMemoryError) {
            null
        } catch (_: Exception) {
            null
        }

        if (decoded == null) return null

        return try {
            val cropSize = minOf(decoded.width, decoded.height)
            if (cropSize <= 0) {
                decoded.recycle()
                return null
            }
            val x = (decoded.width - cropSize) / 2
            val y = (decoded.height - cropSize) / 2
            val squared = if (x == 0 && y == 0 && decoded.width == decoded.height) {
                decoded
            } else {
                Bitmap.createBitmap(decoded, x, y, cropSize, cropSize).also {
                    if (it !== decoded) decoded.recycle()
                }
            }
            if (squared.width > maxSize || squared.height > maxSize) {
                Bitmap.createScaledBitmap(squared, maxSize, maxSize, true).also {
                    if (it !== squared) squared.recycle()
                }
            } else {
                squared
            }
        } catch (_: OutOfMemoryError) {
            decoded.recycle()
            null
        } catch (_: Exception) {
            decoded.recycle()
            null
        }
    }

    fun getCoverArtInfo(context: Context, uriString: String?): Map<String, Any?> {
        if (uriString.isNullOrBlank()) {
            return mapOf("path" to null, "color" to null)
        }

        val sha256Hex = MessageDigest.getInstance("SHA-256")
            .digest(uriString.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }

        val artDir = File(context.cacheDir, "art")
        if (!artDir.exists()) {
            artDir.mkdirs()
        }
        val cacheFile = File(artDir, "$sha256Hex.jpg")

        var bitmap: Bitmap? = if (cacheFile.exists() && cacheFile.length() > 0) {
            try {
                BitmapFactory.decodeFile(cacheFile.absolutePath)
            } catch (_: Exception) {
                null
            }
        } else {
            null
        }

        if (bitmap == null) {
            bitmap = loadCoverBitmap(context, uriString, 512)
                ?: return mapOf("path" to null, "color" to null)
            try {
                FileOutputStream(cacheFile).use { out ->
                    bitmap.compress(Bitmap.CompressFormat.JPEG, 90, out)
                }
            } catch (_: Exception) {
                bitmap.recycle()
                return mapOf("path" to null, "color" to null)
            }
        }

        val dominantColor = try {
            val sampleSize = 24
            val small = Bitmap.createScaledBitmap(bitmap, sampleSize, sampleSize, true)
            val pixels = IntArray(sampleSize * sampleSize)
            small.getPixels(pixels, 0, sampleSize, 0, 0, sampleSize, sampleSize)
            if (small !== bitmap) {
                small.recycle()
            }

            val bucketCount = 24
            val bucketWeight = FloatArray(bucketCount)
            val bucketR = FloatArray(bucketCount)
            val bucketG = FloatArray(bucketCount)
            val bucketB = FloatArray(bucketCount)
            val bucketPixels = IntArray(bucketCount)
            val hsv = FloatArray(3)

            for (pixel in pixels) {
                if (Color.alpha(pixel) < 128) continue
                Color.colorToHSV(pixel, hsv)
                val hue = hsv[0]
                val sat = hsv[1]
                val value = hsv[2]
                if (sat < 0.25f || value < 0.15f || (value > 0.95f && sat < 0.15f)) continue

                val bucket = ((hue / 360f) * bucketCount).toInt().coerceIn(0, bucketCount - 1)
                val weight = sat * (0.5f + value * 0.5f)
                bucketWeight[bucket] += weight
                bucketR[bucket] += Color.red(pixel) * weight
                bucketG[bucket] += Color.green(pixel) * weight
                bucketB[bucket] += Color.blue(pixel) * weight
                bucketPixels[bucket]++
            }

            var bestBucket = -1
            var bestWeight = 0f
            for (i in 0 until bucketCount) {
                if (bucketPixels[i] > 0 && bucketWeight[i] > bestWeight) {
                    bestWeight = bucketWeight[i]
                    bestBucket = i
                }
            }

            if (bestBucket >= 0) {
                val r = (bucketR[bestBucket] / bestWeight).toInt().coerceIn(0, 255)
                val g = (bucketG[bestBucket] / bestWeight).toInt().coerceIn(0, 255)
                val b = (bucketB[bestBucket] / bestWeight).toInt().coerceIn(0, 255)
                Color.rgb(r, g, b)
            } else {
                0xFF38BDF8.toInt()
            }
        } catch (_: Exception) {
            0xFF38BDF8.toInt()
        } finally {
            bitmap.recycle()
        }

        return mapOf("path" to cacheFile.absolutePath, "color" to dominantColor)
    }

    data class EmbeddedLyricResult(val raw: String, val translation: String?, val source: String)

    private fun extractEmbeddedLyrics(
        context: Context,
        filePath: String?,
        uriString: String?
    ): EmbeddedLyricResult? {
        return try {
            val baseStream: InputStream = when {
                !uriString.isNullOrBlank() && uriString.startsWith("content://", ignoreCase = true) -> {
                    context.contentResolver.openInputStream(android.net.Uri.parse(uriString))
                }
                !filePath.isNullOrBlank() -> {
                    val file = java.io.File(filePath)
                    if (file.exists() && file.isFile) java.io.FileInputStream(file) else null
                }
                else -> null
            } ?: return null

            baseStream.use { rawStream ->
                val header = ByteArray(12)
                if (!readExact(rawStream, header)) return null

                val fullStream = java.io.SequenceInputStream(
                    java.io.ByteArrayInputStream(header),
                    rawStream
                )

                when {
                    header[0] == 'f'.code.toByte() &&
                        header[1] == 'L'.code.toByte() &&
                        header[2] == 'a'.code.toByte() &&
                        header[3] == 'C'.code.toByte() -> parseFlacLyrics(fullStream)

                    header[0] == 'I'.code.toByte() &&
                        header[1] == 'D'.code.toByte() &&
                        header[2] == '3'.code.toByte() -> parseId3Lyrics(fullStream)

                    header[4] == 'f'.code.toByte() &&
                        header[5] == 't'.code.toByte() &&
                        header[6] == 'y'.code.toByte() &&
                        header[7] == 'p'.code.toByte() -> parseMp4Lyrics(fullStream)

                    header[0] == 'O'.code.toByte() &&
                        header[1] == 'g'.code.toByte() &&
                        header[2] == 'g'.code.toByte() &&
                        header[3] == 'S'.code.toByte() -> parseOggLyrics(fullStream)

                    else -> null
                }
            }
        } catch (_: Throwable) {
            null
        }
    }

    private fun skipExact(stream: InputStream, count: Long): Boolean {
        if (count == 0L) return true
        if (count < 0L) return false
        var remaining = count
        while (remaining > 0L) {
            val skipped = stream.skip(remaining)
            if (skipped > 0L) {
                remaining -= skipped
            } else {
                if (stream.read() == -1) return false
                remaining -= 1L
            }
        }
        return true
    }

    private fun readExact(stream: InputStream, buf: ByteArray): Boolean {
        var offset = 0
        while (offset < buf.size) {
            val read = stream.read(buf, offset, buf.size - offset)
            if (read <= 0) return false
            offset += read
        }
        return true
    }

    private fun parseFlacLyrics(stream: InputStream): EmbeddedLyricResult? {
        if (!skipExact(stream, 4L)) return null // skip "fLaC"
        val blockHeader = ByteArray(4)

        while (readExact(stream, blockHeader)) {
            val isLast = (blockHeader[0].toInt() and 0x80) != 0
            val blockType = blockHeader[0].toInt() and 0x7F
            val len = ((blockHeader[1].toInt() and 0xFF) shl 16) or
                ((blockHeader[2].toInt() and 0xFF) shl 8) or
                (blockHeader[3].toInt() and 0xFF)

            if (blockType == 4) {
                if (len in 8..2_000_000) {
                    val data = ByteArray(len)
                    if (!readExact(stream, data)) return null
                    val parsed = parseVorbisCommentBlock(data, 0, data.size)
                    if (parsed != null) {
                        return EmbeddedLyricResult(parsed.first, parsed.second, "embedded-flac")
                    }
                } else if (!skipExact(stream, len.toLong())) {
                    return null
                }
            } else {
                if (!skipExact(stream, len.toLong())) return null
            }

            if (isLast) break
        }
        return null
    }

    private fun parseVorbisCommentBlock(
        data: ByteArray,
        startOffset: Int,
        limit: Int
    ): Pair<String, String?>? {
        var pos = startOffset
        if (pos + 4 > limit) return null
        val vendorLen = readLe32(data, pos)
        pos += 4
        if (vendorLen < 0 || pos + vendorLen + 4 > limit) return null
        pos += vendorLen

        val count = readLe32(data, pos)
        pos += 4
        if (count <= 0) return null

        val maxEntries = minOf(count, 2000)
        var syncedLyrics: String? = null
        var plainLyrics: String? = null
        var translation: String? = null

        for (i in 0 until maxEntries) {
            if (pos + 4 > limit) break
            val strLen = readLe32(data, pos)
            pos += 4
            if (strLen < 0 || pos + strLen > limit) break

            val entry = String(data, pos, strLen, Charsets.UTF_8)
            pos += strLen

            val eq = entry.indexOf('=')
            if (eq <= 0) continue

            val key = entry.substring(0, eq).trim().uppercase(java.util.Locale.ROOT)
            val value = entry.substring(eq + 1).trim()
            if (value.isEmpty()) continue

            when (key) {
                "SYNCEDLYRICS" -> if (syncedLyrics == null) syncedLyrics = value
                "LYRICS", "UNSYNCEDLYRICS", "UNSYNCED LYRICS", "LYRIC" -> {
                    if (hasLrcTimestamps(value)) {
                        if (syncedLyrics == null) syncedLyrics = value
                    } else {
                        if (plainLyrics == null) plainLyrics = value
                    }
                }
                "TLYRICS", "TRANSLATION", "LYRICS_TRANSLATION" -> {
                    if (translation == null) translation = value
                }
            }
        }

        val raw = syncedLyrics ?: plainLyrics ?: return null
        return raw to translation
    }

    private fun parseId3Lyrics(stream: InputStream): EmbeddedLyricResult? {
        val header = ByteArray(10)
        if (!readExact(stream, header)) return null

        val ver = header[3].toInt() and 0xFF
        if (ver != 3 && ver != 4) return null

        val flags = header[5].toInt() and 0xFF
        val tagSize = readSyncsafe32(header, 6)
        if (tagSize <= 0) return null

        val readSize = minOf(tagSize, 2_000_000)
        var tagData = ByteArray(readSize)
        if (!readExact(stream, tagData)) return null

        val globalUnsync = (flags and 0x80) != 0
        if (globalUnsync && ver == 3) {
            tagData = deunsync(tagData, 0, tagData.size)
        }

        var pos = 0
        if ((flags and 0x40) != 0 && pos + 4 <= tagData.size) {
            val extSize = if (ver == 4) {
                readSyncsafe32(tagData, pos)
            } else {
                4 + readBe32(tagData, pos)
            }
            if (extSize > 0 && pos + extSize <= tagData.size) {
                pos += extSize
            }
        }

        var syltLyrics: String? = null
        var syncedTextLyrics: String? = null
        var plainTextLyrics: String? = null

        while (pos + 10 <= tagData.size) {
            if (tagData[pos] == 0.toByte()) break

            val frameId = String(tagData, pos, 4, Charsets.ISO_8859_1)
            val frameSize = if (ver == 4) {
                readSyncsafe32(tagData, pos + 4)
            } else {
                readBe32(tagData, pos + 4)
            }
            val frameFlags1 = tagData[pos + 9].toInt() and 0xFF
            pos += 10

            if (frameSize <= 0 || pos + frameSize > tagData.size) break

            var payloadStart = pos
            var payloadEnd = pos + frameSize
            pos += frameSize

            if (frameId != "USLT" && frameId != "SYLT" && frameId != "TXXX") continue

            var payload = tagData
            if (ver == 4 && (globalUnsync || (frameFlags1 and 0x02) != 0)) {
                payload = deunsync(tagData, payloadStart, payloadEnd)
                payloadStart = 0
                payloadEnd = payload.size
            }

            if (ver == 4 && (frameFlags1 and 0x01) != 0) {
                if (payloadStart + 4 > payloadEnd) continue
                payloadStart += 4
            }

            when (frameId) {
                "USLT" -> {
                    if (payloadStart + 4 >= payloadEnd) continue
                    val encoding = payload[payloadStart].toInt() and 0xFF
                    val descEnd = findNullTerminator(payload, payloadStart + 4, payloadEnd, encoding)
                    val textStart = advancePastNull(descEnd, payloadEnd, encoding)
                    if (textStart < payloadEnd) {
                        val text = decodeId3Text(payload, textStart, payloadEnd, encoding).trim()
                        if (text.isNotEmpty()) {
                            if (hasLrcTimestamps(text)) {
                                if (syncedTextLyrics == null) syncedTextLyrics = text
                            } else if (plainTextLyrics == null) {
                                plainTextLyrics = text
                            }
                        }
                    }
                }
                "SYLT" -> {
                    if (payloadStart + 6 >= payloadEnd) continue
                    val encoding = payload[payloadStart].toInt() and 0xFF
                    val timestampFormat = payload[payloadStart + 4].toInt() and 0xFF
                    if (timestampFormat != 2) continue

                    val descEnd = findNullTerminator(payload, payloadStart + 6, payloadEnd, encoding)
                    var cur = advancePastNull(descEnd, payloadEnd, encoding)
                    val sb = StringBuilder()

                    while (cur < payloadEnd) {
                        val lineEnd = findNullTerminator(payload, cur, payloadEnd, encoding)
                        val lineText = decodeId3Text(payload, cur, lineEnd, encoding)
                            .replace("\r", "")
                            .replace("\n", " ")
                        val afterNull = advancePastNull(lineEnd, payloadEnd, encoding)
                        if (afterNull + 4 > payloadEnd) break

                        val ms = readBe32Unsigned(payload, afterNull)
                        cur = afterNull + 4

                        val mins = ms / 60_000L
                        val secs = (ms % 60_000L) / 1_000L
                        val centis = (ms % 1_000L) / 10L
                        if (sb.isNotEmpty()) sb.append('\n')
                        sb.append(
                            String.format(
                                java.util.Locale.ROOT,
                                "[%02d:%02d.%02d]%s",
                                mins,
                                secs,
                                centis,
                                lineText
                            )
                        )
                    }

                    val formatted = sb.toString().trim()
                    if (formatted.isNotEmpty() && syltLyrics == null) {
                        syltLyrics = formatted
                    }
                }
                "TXXX" -> {
                    if (payloadStart + 1 >= payloadEnd) continue
                    val encoding = payload[payloadStart].toInt() and 0xFF
                    val keyEnd = findNullTerminator(payload, payloadStart + 1, payloadEnd, encoding)
                    val key = decodeId3Text(payload, payloadStart + 1, keyEnd, encoding)
                        .trim()
                        .uppercase(java.util.Locale.ROOT)
                    if (key == "LYRICS" || key == "UNSYNCEDLYRICS" || key == "LYRIC" || key == "SYNCEDLYRICS") {
                        val valStart = advancePastNull(keyEnd, payloadEnd, encoding)
                        if (valStart < payloadEnd) {
                            val value = decodeId3Text(payload, valStart, payloadEnd, encoding).trim()
                            if (value.isNotEmpty()) {
                                if (key == "SYNCEDLYRICS" || hasLrcTimestamps(value)) {
                                    if (syncedTextLyrics == null) syncedTextLyrics = value
                                } else if (plainTextLyrics == null) {
                                    plainTextLyrics = value
                                }
                            }
                        }
                    }
                }
            }
        }

        val raw = syltLyrics ?: syncedTextLyrics ?: plainTextLyrics ?: return null
        return EmbeddedLyricResult(raw, null, "embedded-id3")
    }

    private fun parseMp4Lyrics(stream: InputStream): EmbeddedLyricResult? {
        val raw = walkMp4Boxes(stream, Long.MAX_VALUE, 0) ?: return null
        return EmbeddedLyricResult(raw, null, "embedded-mp4")
    }

    private fun walkMp4Boxes(stream: InputStream, containerRemaining: Long, depth: Int): String? {
        val boxHeader = ByteArray(8)
        val extHeader = ByteArray(8)
        var remaining = containerRemaining

        while (remaining >= 8L) {
            if (!readExact(stream, boxHeader)) return null
            val size32 = readBe32Unsigned(boxHeader, 0)
            val type = String(boxHeader, 4, 4, Charsets.ISO_8859_1)

            var headerBytes = 8L
            val boxSize: Long = when (size32) {
                1L -> {
                    if (remaining < 16L || !readExact(stream, extHeader)) return null
                    headerBytes = 16L
                    readBe64(extHeader, 0)
                }
                0L -> return null
                else -> size32
            }

            if (boxSize < headerBytes) return null
            val payloadSize = boxSize - headerBytes
            if (remaining != Long.MAX_VALUE && boxSize > remaining) return null
            if (remaining != Long.MAX_VALUE) remaining -= boxSize

            val shouldDescend = when (depth) {
                0 -> type == "moov"
                1 -> type == "udta"
                2 -> type == "meta"
                3 -> type == "ilst"
                4 -> type == "\u00A9lyr"
                else -> false
            }

            if (shouldDescend) {
                if (type == "meta") {
                    if (payloadSize < 4L || !skipExact(stream, 4L)) return null
                    val found = walkMp4Boxes(stream, payloadSize - 4L, depth + 1)
                    if (found != null) return found
                } else {
                    val found = walkMp4Boxes(stream, payloadSize, depth + 1)
                    if (found != null) return found
                }
            } else if (depth == 5 && type == "data") {
                if (payloadSize in 9L..2_000_000L) {
                    if (!skipExact(stream, 8L)) return null
                    val textBytes = ByteArray((payloadSize - 8L).toInt())
                    if (!readExact(stream, textBytes)) return null
                    val text = String(textBytes, Charsets.UTF_8).trim()
                    if (text.isNotEmpty()) return text
                } else if (!skipExact(stream, payloadSize)) {
                    return null
                }
            } else {
                if (!skipExact(stream, payloadSize)) return null
            }
        }
        return null
    }

    private fun parseOggLyrics(stream: InputStream): EmbeddedLyricResult? {
        val maxBytes = 262_144
        val buf = ByteArray(maxBytes)
        var total = 0
        while (total < maxBytes) {
            val n = stream.read(buf, total, maxBytes - total)
            if (n <= 0) break
            total += n
        }
        if (total <= 16) return null

        val vorbisMarker = byteArrayOf(
            0x03,
            'v'.code.toByte(),
            'o'.code.toByte(),
            'r'.code.toByte(),
            'b'.code.toByte(),
            'i'.code.toByte(),
            's'.code.toByte()
        )
        val opusMarker = "OpusTags".toByteArray(Charsets.US_ASCII)

        val commentStart = findBytes(buf, total, vorbisMarker)?.let { it + vorbisMarker.size }
            ?: findBytes(buf, total, opusMarker)?.let { it + opusMarker.size }
            ?: return null

        val parsed = parseVorbisCommentBlock(buf, commentStart, total) ?: return null
        return EmbeddedLyricResult(parsed.first, parsed.second, "embedded-ogg")
    }

    private fun findBytes(haystack: ByteArray, limit: Int, needle: ByteArray): Int? {
        if (needle.isEmpty() || limit < needle.size) return null
        val lastStart = limit - needle.size
        for (i in 0..lastStart) {
            var match = true
            for (j in needle.indices) {
                if (haystack[i + j] != needle[j]) {
                    match = false
                    break
                }
            }
            if (match) return i
        }
        return null
    }

    private fun deunsync(data: ByteArray, start: Int, end: Int): ByteArray {
        val out = ByteArray(end - start)
        var outIdx = 0
        var i = start
        while (i < end) {
            val b = data[i]
            out[outIdx++] = b
            if (b == 0xFF.toByte() && i + 1 < end && data[i + 1] == 0x00.toByte()) {
                i += 2
            } else {
                i += 1
            }
        }
        return out.copyOf(outIdx)
    }

    private fun findNullTerminator(data: ByteArray, start: Int, end: Int, encoding: Int): Int {
        if (encoding == 1 || encoding == 2) {
            var i = start
            while (i + 1 < end) {
                if (data[i] == 0.toByte() && data[i + 1] == 0.toByte()) return i
                i += 2
            }
            return end
        } else {
            for (i in start until end) {
                if (data[i] == 0.toByte()) return i
            }
            return end
        }
    }

    private fun advancePastNull(nullPos: Int, end: Int, encoding: Int): Int {
        val step = if (encoding == 1 || encoding == 2) 2 else 1
        return minOf(nullPos + step, end)
    }

    private fun decodeId3Text(data: ByteArray, start: Int, end: Int, encoding: Int): String {
        if (start >= end) return ""
        val len = end - start
        val raw = when (encoding) {
            1 -> String(data, start, len, Charsets.UTF_16)
            2 -> String(data, start, len, Charsets.UTF_16BE)
            3 -> String(data, start, len, Charsets.UTF_8)
            else -> decodeEncoding0(data, start, len)
        }
        return raw.trimEnd('\u0000')
    }

    private fun decodeEncoding0(data: ByteArray, start: Int, len: Int): String {
        var asciiOnly = true
        for (i in start until start + len) {
            if ((data[i].toInt() and 0x80) != 0) {
                asciiOnly = false
                break
            }
        }
        if (asciiOnly) return String(data, start, len, Charsets.ISO_8859_1)

        tryDecode(data, start, len, Charsets.UTF_8)?.let { return it }
        try {
            tryDecode(data, start, len, java.nio.charset.Charset.forName("GBK"))?.let { return it }
        } catch (_: Throwable) {
        }
        return String(data, start, len, Charsets.ISO_8859_1)
    }

    private fun tryDecode(
        data: ByteArray,
        start: Int,
        len: Int,
        charset: java.nio.charset.Charset
    ): String? {
        return try {
            val decoder = charset.newDecoder()
                .onMalformedInput(java.nio.charset.CodingErrorAction.REPORT)
                .onUnmappableCharacter(java.nio.charset.CodingErrorAction.REPORT)
            decoder.decode(java.nio.ByteBuffer.wrap(data, start, len)).toString()
        } catch (_: Throwable) {
            null
        }
    }

    private fun hasLrcTimestamps(text: String): Boolean {
        return Regex("""\[\d{1,3}:\d{2}(?:[.:]\d{1,3})?]""").containsMatchIn(text)
    }

    private fun readLe32(b: ByteArray, off: Int): Int {
        return (b[off].toInt() and 0xFF) or
            ((b[off + 1].toInt() and 0xFF) shl 8) or
            ((b[off + 2].toInt() and 0xFF) shl 16) or
            ((b[off + 3].toInt() and 0xFF) shl 24)
    }

    private fun readBe32(b: ByteArray, off: Int): Int {
        return ((b[off].toInt() and 0xFF) shl 24) or
            ((b[off + 1].toInt() and 0xFF) shl 16) or
            ((b[off + 2].toInt() and 0xFF) shl 8) or
            (b[off + 3].toInt() and 0xFF)
    }

    private fun readBe32Unsigned(b: ByteArray, off: Int): Long {
        return ((b[off].toLong() and 0xFFL) shl 24) or
            ((b[off + 1].toLong() and 0xFFL) shl 16) or
            ((b[off + 2].toLong() and 0xFFL) shl 8) or
            (b[off + 3].toLong() and 0xFFL)
    }

    private fun readBe64(b: ByteArray, off: Int): Long {
        var result = 0L
        for (i in 0 until 8) {
            result = (result shl 8) or (b[off + i].toLong() and 0xFFL)
        }
        return result
    }

    private fun readSyncsafe32(b: ByteArray, off: Int): Int {
        return ((b[off].toInt() and 0x7F) shl 21) or
            ((b[off + 1].toInt() and 0x7F) shl 14) or
            ((b[off + 2].toInt() and 0x7F) shl 7) or
            (b[off + 3].toInt() and 0x7F)
    }
}
