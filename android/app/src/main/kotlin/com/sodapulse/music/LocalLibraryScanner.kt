package com.sodapulse.music

import android.content.ContentUris
import android.content.Context
import android.net.Uri
import android.provider.MediaStore
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
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

        if (resolvedPath.isNullOrBlank()) {
            return emptyLyricResult()
        }

        val audioFile = File(resolvedPath)
        val parentDir = audioFile.parentFile
        if (parentDir == null || !parentDir.exists() || !parentDir.isDirectory) {
            return emptyLyricResult()
        }

        val baseName = audioFile.nameWithoutExtension
        if (baseName.isBlank()) {
            return emptyLyricResult()
        }

        var rawContent: String? = null
        var formatHint: String? = null
        var sourceLabel: String? = null

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
        val translationContent = if (translationFile.exists() && translationFile.isFile && translationFile.canRead()) {
            readFileTextSafely(translationFile)?.takeIf { it.isNotBlank() }
        } else {
            null
        }

        val romaFile = File(parentDir, "$baseName.roma.lrc")
        val romaContent = if (romaFile.exists() && romaFile.isFile && romaFile.canRead()) {
            readFileTextSafely(romaFile)?.takeIf { it.isNotBlank() }
        } else {
            null
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
}
