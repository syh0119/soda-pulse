package com.sodapulse.music

import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.util.Log
import android.webkit.JavascriptInterface
import android.webkit.WebView
import android.webkit.WebViewClient
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.zip.GZIPInputStream
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

object SodaJsPluginRuntime {

    private const val RPC_TIMEOUT_SECONDS = 25L
    private const val INIT_TIMEOUT_SECONDS = 12L

    private val mainHandler = Handler(Looper.getMainLooper())
    private val httpExecutor: ExecutorService = Executors.newCachedThreadPool()
    private val initLock = Any()

    private val isInitialized = AtomicBoolean(false)
    private val isReady = AtomicBoolean(false)

    @Volatile
    private var readyLatch = CountDownLatch(1)

    @Volatile
    private var webView: WebView? = null

    private val payloadStore = ConcurrentHashMap<String, String>()
    private val pendingRpc = ConcurrentHashMap<String, CompletableFuture<String>>()

    // -------------------------------------------------------------------------
    // Public API (blocking, safe to call from background executor)
    // -------------------------------------------------------------------------

    fun loadPlugin(
        context: Context,
        id: String,
        script: String,
        type: String
    ): Map<String, Any?> {
        ensureInitialized(context)
        val payloadKey = "script_${UUID.randomUUID()}"
        payloadStore[payloadKey] = script
        val resultJson = callRpc(
            "window.__sodaLoadPlugin('%s', '%s', '%s', '%s')",
            escapeJs(id),
            escapeJs(payloadKey),
            escapeJs(type)
        )
        payloadStore.remove(payloadKey)
        return parseJsonObjectToMap(resultJson)
    }

    fun unloadPlugin(id: String): Boolean {
        if (!isReady.get()) return false
        val escaped = escapeJs(id)
        val future = CompletableFuture<String>()
        mainHandler.post {
            val wv = webView
            if (wv == null) {
                future.complete("false")
                return@post
            }
            wv.evaluateJavascript(
                "(function(){ if(window.__sodaPlugins && window.__sodaPlugins['$escaped']){ delete window.__sodaPlugins['$escaped']; return 'true'; } return 'false'; })()"
            ) { res ->
                future.complete(res?.trim('"') ?: "false")
            }
        }
        return try {
            future.get(5, TimeUnit.SECONDS) == "true"
        } catch (_: Exception) {
            false
        }
    }

    fun testPlugin(context: Context, id: String): Map<String, Any?> {
        ensureInitialized(context)
        val resultJson = callRpc(
            "window.__sodaTestPlugin('%s', '%s')",
            escapeJs(id)
        )
        return parseJsonObjectToMap(resultJson)
    }

    fun searchTracks(
        context: Context,
        pluginId: String,
        query: String,
        page: Int = 1
    ): List<Map<String, Any?>> {
        ensureInitialized(context)
        val queryB64 = Base64.encodeToString(query.toByteArray(Charsets.UTF_8), Base64.NO_WRAP)
        val resultJson = callRpc(
            "window.__sodaSearch('%s', '%s', '%s', $page)",
            escapeJs(pluginId),
            escapeJs(queryB64)
        )
        val map = parseJsonObjectToMap(resultJson)
        @Suppress("UNCHECKED_CAST")
        return (map["tracks"] as? List<Map<String, Any?>>) ?: emptyList()
    }

    private data class ProbeResult(
        val ok: Boolean,
        val statusCode: Int,
        val contentType: String,
        val reason: String,
        val finalUrl: String = ""
    )

    private fun probeAudioUrl(url: String, headers: Map<String, String>): ProbeResult {
        var currentUrl = url
        val redirectCodes = setOf(301, 302, 303, 307, 308)
        try {
            for (hop in 0..3) {
                val parsedUrl = URL(currentUrl)
                val conn = (parsedUrl.openConnection() as HttpURLConnection).apply {
                    connectTimeout = 4000
                    readTimeout = 4000
                    instanceFollowRedirects = false
                    requestMethod = "GET"
                }
                try {
                    headers.forEach { (k, v) ->
                        if (k.isNotBlank() && v.isNotBlank()) {
                            conn.setRequestProperty(k, v)
                        }
                    }
                    conn.setRequestProperty("Range", "bytes=0-1")
                    conn.setRequestProperty("Accept-Encoding", "identity")
                    if (headers.keys.none { it.equals("User-Agent", ignoreCase = true) }) {
                        conn.setRequestProperty(
                            "User-Agent",
                            "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36"
                        )
                    }
                    val host = parsedUrl.host.orEmpty().lowercase()
                    if (host.contains("music.126.net") &&
                        headers.keys.none { it.equals("Referer", ignoreCase = true) }
                    ) {
                        conn.setRequestProperty("Referer", "https://music.163.com/")
                    }

                    val status = conn.responseCode
                    val rawContentType = conn.contentType.orEmpty()
                    val contentTypeLower = rawContentType.lowercase()

                    if (status in redirectCodes) {
                        val location = conn.getHeaderField("Location")
                        if (location.isNullOrBlank()) {
                            return ProbeResult(false, status, rawContentType, "HTTP $status (empty Location)", currentUrl)
                        }
                        currentUrl = URL(parsedUrl, location).toString()
                        continue
                    }

                    val isInvalidContentType = contentTypeLower.contains("text/html") ||
                        contentTypeLower.contains("application/json") ||
                        contentTypeLower.contains("text/plain")

                    return if (status in 200..299 && !isInvalidContentType) {
                        ProbeResult(true, status, rawContentType, "ok", currentUrl)
                    } else {
                        ProbeResult(false, status, rawContentType, "HTTP $status ($rawContentType)", currentUrl)
                    }
                } finally {
                    conn.disconnect()
                }
            }
            return ProbeResult(false, -1, "", "Too many redirects", currentUrl)
        } catch (e: Exception) {
            return ProbeResult(false, -1, "", e.message ?: e.javaClass.simpleName, currentUrl)
        }
    }

    private fun extractNumericWySongId(rawItemJson: String): String? {
        return try {
            val obj = JSONObject(rawItemJson)
            val rawId = obj.optString("id").takeIf { it.isNotBlank() }
                ?: obj.optString("songmid").takeIf { it.isNotBlank() }
                ?: return null
            val trimmed = rawId.trim()
            if (trimmed.isNotEmpty() && trimmed.all { it.isDigit() }) trimmed else null
        } catch (_: Exception) {
            null
        }
    }

    fun resolveMediaUrl(
        context: Context,
        pluginId: String,
        rawItemJson: String,
        quality: String = "standard",
        source: String = ""
    ): Map<String, Any?> {
        ensureInitialized(context)
        val startMs = System.currentTimeMillis()
        val itemB64 = Base64.encodeToString(rawItemJson.toByteArray(Charsets.UTF_8), Base64.NO_WRAP)
        val fallbackQ = when (quality.lowercase()) {
            "flac24bit", "24bit" -> "flac"
            "flac" -> "320k"
            "128k", "standard", "low" -> "320k"
            else -> "128k"
        }
        val candidates = listOf(quality, fallbackQ)
            .filter { it.isNotBlank() }
            .distinct()
        var lastError = "no_valid_url"

        fun attemptQuality(targetQuality: String): Map<String, Any?>? {
            val resultJson = callRpc(
                "window.__sodaResolveUrl('%s', '%s', '%s', '%s', '%s')",
                escapeJs(pluginId),
                escapeJs(itemB64),
                escapeJs(targetQuality),
                escapeJs(source)
            )
            val jsResult = parseJsonObjectToMap(resultJson)
            val url = (jsResult["url"] as? String)?.trim().orEmpty()
            val rawHdrs = jsResult["headers"] as? Map<*, *>
            val headers = mutableMapOf<String, String>()
            rawHdrs?.forEach { (k, v) ->
                val ks = k?.toString()?.trim()
                val vs = v?.toString()?.trim()
                if (!ks.isNullOrEmpty() && !vs.isNullOrEmpty()) {
                    headers[ks] = vs
                }
            }

            if (!url.startsWith("http://", ignoreCase = true) &&
                !url.startsWith("https://", ignoreCase = true)
            ) {
                val jsErr = jsResult["error"] as? String
                if (!jsErr.isNullOrBlank()) {
                    lastError = jsErr
                }
                Log.i(
                    "SodaPlugin",
                    "resolveMediaUrl plugin=$pluginId quality=$targetQuality elapsed=${System.currentTimeMillis() - startMs}ms emptyUrl err=$lastError"
                )
                return null
            }

            val probe = probeAudioUrl(url, headers)
            val host = runCatching { URL(probe.finalUrl.ifEmpty { url }).host }.getOrDefault("")
            Log.i(
                "SodaPlugin",
                "resolveMediaUrl plugin=$pluginId quality=$targetQuality elapsed=${System.currentTimeMillis() - startMs}ms " +
                    "probeOk=${probe.ok} status=${probe.statusCode} host=$host reason=${probe.reason}"
            )
            return if (probe.ok) {
                mapOf(
                    "ok" to true,
                    "url" to probe.finalUrl.ifEmpty { url },
                    "headers" to headers,
                    "quality" to (jsResult["quality"] as? String ?: targetQuality)
                )
            } else {
                lastError = probe.reason
                null
            }
        }

        candidates.forEachIndexed { idx, q ->
            if (idx > 0) {
                try {
                    Thread.sleep(1000L)
                } catch (_: InterruptedException) {
                }
            }
            attemptQuality(q)?.let { return it }
        }

        if (source.equals("wy", ignoreCase = true)) {
            val songId = extractNumericWySongId(rawItemJson)
            if (!songId.isNullOrEmpty()) {
                val outerUrl = "https://music.163.com/song/media/outer/url?id=$songId.mp3"
                val outerHeaders = mapOf("Referer" to "https://music.163.com/")
                val probe = probeAudioUrl(outerUrl, outerHeaders)
                val host = runCatching { URL(probe.finalUrl.ifEmpty { outerUrl }).host }.getOrDefault("")
                Log.i(
                    "SodaPlugin",
                    "resolveMediaUrl wy_outer_fallback ok=${probe.ok} status=${probe.statusCode} host=$host reason=${probe.reason}"
                )
                if (probe.ok) {
                    return mapOf(
                        "ok" to true,
                        "url" to probe.finalUrl.ifEmpty { outerUrl },
                        "headers" to outerHeaders,
                        "quality" to "128k"
                    )
                }
            }
        }

        return mapOf(
            "ok" to false,
            "error" to lastError
        )
    }

    fun resolveLyric(
        context: Context,
        pluginId: String,
        rawItemJson: String
    ): Map<String, Any?> {
        ensureInitialized(context)
        val itemB64 = Base64.encodeToString(rawItemJson.toByteArray(Charsets.UTF_8), Base64.NO_WRAP)
        val resultJson = callRpc(
            "window.__sodaResolveLyric('%s', '%s', '%s')",
            escapeJs(pluginId),
            escapeJs(itemB64)
        )
        return parseJsonObjectToMap(resultJson)
    }

    fun importMusicSheet(
        context: Context,
        pluginId: String,
        urlOrId: String
    ): List<Map<String, Any?>> {
        ensureInitialized(context)
        val argB64 = Base64.encodeToString(urlOrId.toByteArray(Charsets.UTF_8), Base64.NO_WRAP)
        val resultJson = callRpc(
            "window.__sodaImportSheet('%s', '%s', '%s')",
            escapeJs(pluginId),
            escapeJs(argB64)
        )
        val map = parseJsonObjectToMap(resultJson)
        @Suppress("UNCHECKED_CAST")
        return (map["tracks"] as? List<Map<String, Any?>>) ?: emptyList()
    }

    fun destroy() {
        synchronized(initLock) {
            isInitialized.set(false)
            isReady.set(false)
            payloadStore.clear()
            pendingRpc.values.forEach { it.cancel(true) }
            pendingRpc.clear()
            val oldWebView = webView
            webView = null
            readyLatch.countDown()
            readyLatch = CountDownLatch(1)
            if (oldWebView != null) {
                mainHandler.post {
                    try {
                        oldWebView.stopLoading()
                        oldWebView.removeJavascriptInterface("_SodaNative")
                        oldWebView.destroy()
                    } catch (_: Throwable) {
                    }
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // WebView Lifecycle & RPC
    // -------------------------------------------------------------------------

    @SuppressLint("SetJavaScriptEnabled", "JavascriptInterface")
    private fun ensureInitialized(context: Context) {
        if (isReady.get() && webView != null) return

        val appContext = context.applicationContext
        val latch: CountDownLatch

        synchronized(initLock) {
            if (isReady.get() && webView != null) return
            if (!isInitialized.getAndSet(true)) {
                readyLatch = CountDownLatch(1)
                latch = readyLatch
                mainHandler.post {
                    try {
                        val wv = WebView(appContext)
                        wv.settings.javaScriptEnabled = true
                        wv.settings.domStorageEnabled = true
                        wv.addJavascriptInterface(NativeBridge(), "_SodaNative")
                        wv.webViewClient = object : WebViewClient() {
                            private val bootstrapInjected = AtomicBoolean(false)

                            override fun onPageFinished(view: WebView?, url: String?) {
                                super.onPageFinished(view, url)
                                if (bootstrapInjected.compareAndSet(false, true)) {
                                    view?.evaluateJavascript(BOOTSTRAP_JS) {
                                        isReady.set(true)
                                        readyLatch.countDown()
                                    }
                                }
                            }
                        }
                        webView = wv
                        wv.loadDataWithBaseURL(
                            "https://localhost/",
                            "<!DOCTYPE html><html><head><meta charset='utf-8'></head><body></body></html>",
                            "text/html",
                            "UTF-8",
                            null
                        )
                    } catch (_: Throwable) {
                        isInitialized.set(false)
                        readyLatch.countDown()
                    }
                }
            } else {
                latch = readyLatch
            }
        }

        val completed = latch.await(INIT_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        if (!completed || !isReady.get()) {
            throw IllegalStateException("SodaJsPluginRuntime WebView initialization timed out or failed")
        }
    }

    private fun callRpc(template: String, vararg args: String): String {
        val callId = UUID.randomUUID().toString()
        val future = CompletableFuture<String>()
        pendingRpc[callId] = future

        val jsCall = String.format(template, callId, *args)
        mainHandler.post {
            val wv = webView
            if (wv == null) {
                pendingRpc.remove(callId)?.complete("""{"ok":false,"error":"WebView destroyed"}""")
            } else {
                wv.evaluateJavascript(jsCall, null)
            }
        }

        return try {
            future.get(RPC_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        } catch (e: Exception) {
            pendingRpc.remove(callId)
            JSONObject().apply {
                put("ok", false)
                put("error", e.message ?: "RPC timeout")
            }.toString()
        }
    }

    // -------------------------------------------------------------------------
    // NativeBridge exposed to JS as _SodaNative
    // -------------------------------------------------------------------------

    private class NativeBridge {

        @JavascriptInterface
        fun httpRequest(
            reqId: String,
            method: String,
            url: String,
            headersJson: String,
            body: String,
            responseType: String,
            timeoutMs: Int
        ) {
            httpExecutor.execute {
                val resultJson = executeHttpRequest(
                    method = method,
                    url = url,
                    headersJson = headersJson,
                    body = body,
                    responseType = responseType,
                    timeoutMs = timeoutMs
                )
                payloadStore[reqId] = resultJson
                val escapedReqId = escapeJs(reqId)
                mainHandler.post {
                    webView?.evaluateJavascript("window.__sodaOnHttp('$escapedReqId')", null)
                }
            }
        }

        @JavascriptInterface
        fun takePayload(reqId: String): String {
            return payloadStore.remove(reqId) ?: ""
        }

        @JavascriptInterface
        fun cryptoDigest(algo: String, text: String): String {
            return try {
                val normalized = when (algo.uppercase()) {
                    "MD5" -> "MD5"
                    "SHA1", "SHA-1" -> "SHA-1"
                    "SHA256", "SHA-256" -> "SHA-256"
                    else -> algo
                }
                val digest = MessageDigest.getInstance(normalized)
                val bytes = digest.digest(text.toByteArray(Charsets.UTF_8))
                bytesToHex(bytes)
            } catch (_: Exception) {
                ""
            }
        }

        @JavascriptInterface
        fun cryptoHmac(algo: String, key: String, text: String): String {
            return try {
                val normalized = when (algo.uppercase()) {
                    "HMACSHA1", "HMAC-SHA1", "SHA1" -> "HmacSHA1"
                    "HMACSHA256", "HMAC-SHA256", "SHA256" -> "HmacSHA256"
                    else -> algo
                }
                val mac = Mac.getInstance(normalized)
                mac.init(SecretKeySpec(key.toByteArray(Charsets.UTF_8), normalized))
                val bytes = mac.doFinal(text.toByteArray(Charsets.UTF_8))
                bytesToHex(bytes)
            } catch (_: Exception) {
                ""
            }
        }

        @JavascriptInterface
        fun onRpcResult(callId: String, resultJson: String) {
            pendingRpc.remove(callId)?.complete(resultJson)
        }
    }

    private fun executeHttpRequest(
        method: String,
        url: String,
        headersJson: String,
        body: String,
        responseType: String,
        timeoutMs: Int
    ): String {
        var conn: HttpURLConnection? = null
        return try {
            val clampedTimeout = timeoutMs.coerceIn(8000, 25000)
            val upperMethod = method.trim().uppercase().ifEmpty { "GET" }
            conn = (URL(url).openConnection() as HttpURLConnection).apply {
                requestMethod = upperMethod
                connectTimeout = clampedTimeout
                readTimeout = clampedTimeout
                instanceFollowRedirects = true
                useCaches = false
            }

            if (headersJson.isNotBlank()) {
                val headersObj = JSONObject(headersJson)
                val keys = headersObj.keys()
                while (keys.hasNext()) {
                    val k = keys.next().trim()
                    val v = headersObj.optString(k, "").trim()
                    if (k.isNotEmpty() && v.isNotEmpty()) {
                        conn.setRequestProperty(k, v)
                    }
                }
            }

            if ((upperMethod == "POST" || upperMethod == "PUT" || upperMethod == "PATCH") && body.isNotEmpty()) {
                conn.doOutput = true
                conn.outputStream.use { os ->
                    os.write(body.toByteArray(Charsets.UTF_8))
                    os.flush()
                }
            }

            val status = conn.responseCode
            val statusText = conn.responseMessage ?: ""
            val rawStream: InputStream? = if (status in 200..399) {
                conn.inputStream
            } else {
                conn.errorStream ?: conn.inputStream
            }

            val contentEncoding = conn.contentEncoding ?: ""
            val isGzip = contentEncoding.contains("gzip", ignoreCase = true)

            val rawBytes = if (rawStream != null) {
                val stream = if (isGzip) GZIPInputStream(rawStream) else rawStream
                stream.use { readAllBytes(it) }
            } else {
                ByteArray(0)
            }

            val respHeaders = JSONObject()
            conn.headerFields?.forEach { (key, values) ->
                if (key != null && !values.isNullOrEmpty()) {
                    respHeaders.put(key.lowercase(), values.joinToString(", "))
                }
            }

            val isBinary = responseType.equals("arraybuffer", ignoreCase = true) ||
                responseType.equals("base64", ignoreCase = true)
            val encodedBody = if (isBinary) {
                Base64.encodeToString(rawBytes, Base64.NO_WRAP)
            } else {
                String(rawBytes, Charsets.UTF_8)
            }

            JSONObject().apply {
                put("ok", status in 200..299)
                put("status", status)
                put("statusText", statusText)
                put("headers", respHeaders)
                put("body", encodedBody)
                put("isBase64", isBinary)
                put("error", JSONObject.NULL)
            }.toString()
        } catch (e: Exception) {
            JSONObject().apply {
                put("ok", false)
                put("status", 0)
                put("statusText", "")
                put("headers", JSONObject())
                put("body", "")
                put("isBase64", false)
                put("error", e.message ?: "HTTP request failed")
            }.toString()
        } finally {
            conn?.disconnect()
        }
    }

    private fun readAllBytes(input: InputStream): ByteArray {
        val buffer = ByteArrayOutputStream()
        val chunk = ByteArray(8192)
        var read: Int
        while (input.read(chunk).also { read = it } != -1) {
            buffer.write(chunk, 0, read)
        }
        return buffer.toByteArray()
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    private fun bytesToHex(bytes: ByteArray): String {
        val sb = StringBuilder(bytes.size * 2)
        for (b in bytes) {
            val v = b.toInt() and 0xFF
            sb.append(HEX_CHARS[v ushr 4])
            sb.append(HEX_CHARS[v and 0x0F])
        }
        return sb.toString()
    }

    private fun escapeJs(value: String): String {
        return value
            .replace("\\", "\\\\")
            .replace("'", "\\'")
            .replace("\n", "\\n")
            .replace("\r", "\\r")
    }

    private fun parseJsonObjectToMap(json: String): Map<String, Any?> {
        if (json.isBlank()) return emptyMap()
        return try {
            jsonObjectToMap(JSONObject(json))
        } catch (_: Exception) {
            mapOf("ok" to false, "error" to "Invalid JSON response")
        }
    }

    private fun jsonObjectToMap(obj: JSONObject): Map<String, Any?> {
        val map = LinkedHashMap<String, Any?>()
        val keys = obj.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            map[key] = jsonValueToKotlin(obj.opt(key))
        }
        return map
    }

    private fun jsonArrayToList(arr: JSONArray): List<Any?> {
        val list = ArrayList<Any?>(arr.length())
        for (i in 0 until arr.length()) {
            list.add(jsonValueToKotlin(arr.opt(i)))
        }
        return list
    }

    private fun jsonValueToKotlin(value: Any?): Any? {
        return when (value) {
            null, JSONObject.NULL -> null
            is JSONObject -> jsonObjectToMap(value)
            is JSONArray -> jsonArrayToList(value)
            else -> value
        }
    }

    private val HEX_CHARS = "0123456789abcdef".toCharArray()

    // -------------------------------------------------------------------------
    // Bootstrap JS Environment
    // -------------------------------------------------------------------------

    private val BOOTSTRAP_JS = """
(function() {
  if (window.__sodaBootstrapped) return;
  window.__sodaBootstrapped = true;

  // 1. Buffer Polyfill
  var textEncoder = new TextEncoder();
  var textDecoder = new TextDecoder('utf-8');

  function SodaBuffer(arg) {
    if (arg instanceof Uint8Array) {
      this._bytes = arg;
    } else if (Array.isArray(arg)) {
      this._bytes = new Uint8Array(arg);
    } else if (typeof arg === 'number') {
      this._bytes = new Uint8Array(arg);
    } else {
      this._bytes = new Uint8Array(0);
    }
    this.length = this._bytes.length;
    this.buffer = this._bytes.buffer;
  }

  SodaBuffer.prototype.toString = function(encoding) {
    var enc = (encoding || 'utf8').toLowerCase();
    var bytes = this._bytes;
    if (enc === 'utf8' || enc === 'utf-8') {
      return textDecoder.decode(bytes);
    }
    if (enc === 'hex') {
      var out = '';
      for (var i = 0; i < bytes.length; i++) {
        var h = bytes[i].toString(16);
        out += (h.length === 1 ? '0' + h : h);
      }
      return out;
    }
    if (enc === 'base64') {
      var bin = '';
      var chunk = 0x8000;
      for (var j = 0; j < bytes.length; j += chunk) {
        bin += String.fromCharCode.apply(null, bytes.subarray(j, j + chunk));
      }
      return btoa(bin);
    }
    if (enc === 'latin1' || enc === 'binary') {
      var lat = '';
      for (var k = 0; k < bytes.length; k++) {
        lat += String.fromCharCode(bytes[k]);
      }
      return lat;
    }
    return textDecoder.decode(bytes);
  };

  SodaBuffer.prototype.slice = function(start, end) {
    return new SodaBuffer(this._bytes.slice(start, end));
  };

  SodaBuffer.from = function(input, encoding) {
    if (input instanceof SodaBuffer) {
      return new SodaBuffer(new Uint8Array(input._bytes));
    }
    if (input instanceof Uint8Array) {
      return new SodaBuffer(new Uint8Array(input));
    }
    if (input instanceof ArrayBuffer) {
      return new SodaBuffer(new Uint8Array(input));
    }
    if (Array.isArray(input)) {
      return new SodaBuffer(new Uint8Array(input));
    }
    if (typeof input === 'string') {
      var enc = (encoding || 'utf8').toLowerCase();
      if (enc === 'utf8' || enc === 'utf-8') {
        return new SodaBuffer(textEncoder.encode(input));
      }
      if (enc === 'base64') {
        var cleaned = input.replace(/[\r\n\s]/g, '').replace(/-/g, '+').replace(/_/g, '/');
        while (cleaned.length % 4 !== 0) cleaned += '=';
        var bin = atob(cleaned);
        var arr = new Uint8Array(bin.length);
        for (var i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i);
        return new SodaBuffer(arr);
      }
      if (enc === 'hex') {
        var hex = input.replace(/[^0-9a-fA-F]/g, '');
        var hArr = new Uint8Array(Math.floor(hex.length / 2));
        for (var j = 0; j < hArr.length; j++) {
          hArr[j] = parseInt(hex.substr(j * 2, 2), 16);
        }
        return new SodaBuffer(hArr);
      }
      if (enc === 'latin1' || enc === 'binary') {
        var lArr = new Uint8Array(input.length);
        for (var k = 0; k < input.length; k++) lArr[k] = input.charCodeAt(k) & 0xff;
        return new SodaBuffer(lArr);
      }
      return new SodaBuffer(textEncoder.encode(input));
    }
    return new SodaBuffer(0);
  };

  SodaBuffer.alloc = function(size) {
    return new SodaBuffer(new Uint8Array(size || 0));
  };

  SodaBuffer.isBuffer = function(obj) {
    return obj instanceof SodaBuffer;
  };

  SodaBuffer.concat = function(list, totalLength) {
    if (!Array.isArray(list) || list.length === 0) return new SodaBuffer(0);
    var total = 0;
    var bufs = [];
    for (var i = 0; i < list.length; i++) {
      var b = SodaBuffer.isBuffer(list[i]) ? list[i] : SodaBuffer.from(list[i]);
      bufs.push(b);
      total += b.length;
    }
    if (typeof totalLength === 'number' && totalLength >= 0) {
      total = totalLength;
    }
    var out = new Uint8Array(total);
    var offset = 0;
    for (var j = 0; j < bufs.length && offset < total; j++) {
      var bytes = bufs[j]._bytes;
      var len = Math.min(bytes.length, total - offset);
      out.set(bytes.subarray(0, len), offset);
      offset += len;
    }
    return new SodaBuffer(out);
  };

  window.Buffer = SodaBuffer;

  // 2. qs Shim
  var qs = {
    stringify: function(obj, opts) {
      if (!obj || typeof obj !== 'object') return '';
      var parts = [];
      var encode = !(opts && opts.encode === false);
      Object.keys(obj).forEach(function(key) {
        var val = obj[key];
        if (val === undefined || val === null) return;
        if (Array.isArray(val)) {
          val.forEach(function(item) {
            if (item === undefined || item === null) return;
            var k = encode ? encodeURIComponent(key) : key;
            var v = encode ? encodeURIComponent(String(item)) : String(item);
            parts.push(k + '=' + v);
          });
        } else if (typeof val === 'object') {
          Object.keys(val).forEach(function(sub) {
            var k = encode ? encodeURIComponent(key + '[' + sub + ']') : (key + '[' + sub + ']');
            var v = encode ? encodeURIComponent(String(val[sub])) : String(val[sub]);
            parts.push(k + '=' + v);
          });
        } else {
          var k = encode ? encodeURIComponent(key) : key;
          var v = encode ? encodeURIComponent(String(val)) : String(val);
          parts.push(k + '=' + v);
        }
      });
      return parts.join('&');
    },
    parse: function(str) {
      var result = {};
      if (!str || typeof str !== 'string') return result;
      var cleaned = str.charAt(0) === '?' ? str.slice(1) : str;
      if (!cleaned) return result;
      cleaned.split('&').forEach(function(pair) {
        if (!pair) return;
        var idx = pair.indexOf('=');
        var k = idx >= 0 ? decodeURIComponent(pair.slice(0, idx).replace(/\+/g, ' ')) : decodeURIComponent(pair.replace(/\+/g, ' '));
        var v = idx >= 0 ? decodeURIComponent(pair.slice(idx + 1).replace(/\+/g, ' ')) : '';
        if (Object.prototype.hasOwnProperty.call(result, k)) {
          if (Array.isArray(result[k])) result[k].push(v);
          else result[k] = [result[k], v];
        } else {
          result[k] = v;
        }
      });
      return result;
    }
  };

  // 3. HTTP / Axios Shim
  var pendingHttp = {};
  var httpSeq = 0;

  window.__sodaOnHttp = function(reqId) {
    var cb = pendingHttp[reqId];
    if (!cb) return;
    delete pendingHttp[reqId];
    var raw = _SodaNative.takePayload(reqId);
    try {
      cb.resolve(JSON.parse(raw));
    } catch (e) {
      cb.reject(new Error('Failed to parse native HTTP payload'));
    }
  };

  function nativeHttp(method, url, headers, body, responseType, timeoutMs) {
    return new Promise(function(resolve, reject) {
      var reqId = 'http_' + (++httpSeq) + '_' + Date.now();
      pendingHttp[reqId] = { resolve: resolve, reject: reject };
      _SodaNative.httpRequest(
        reqId,
        String(method || 'GET'),
        String(url || ''),
        JSON.stringify(headers || {}),
        body == null ? '' : String(body),
        String(responseType || ''),
        Number(timeoutMs || 12000)
      );
    });
  }

  function appendParams(url, params) {
    if (!params || typeof params !== 'object') return url;
    var query = qs.stringify(params);
    if (!query) return url;
    return url + (url.indexOf('?') >= 0 ? '&' : '?') + query;
  }

  function createAxiosInstance(defaultConfig) {
    var defaults = Object.assign({ headers: {}, timeout: 12000 }, defaultConfig || {});

    function axiosCore(configOrUrl, maybeConfig) {
      var cfg = typeof configOrUrl === 'string'
        ? Object.assign({}, maybeConfig || {}, { url: configOrUrl })
        : Object.assign({}, configOrUrl || {});

      var method = (cfg.method || defaults.method || 'GET').toUpperCase();
      var baseURL = cfg.baseURL !== undefined ? cfg.baseURL : (defaults.baseURL || '');
      var rawUrl = cfg.url || '';
      var fullUrl = (baseURL && !/^https?:\/\//i.test(rawUrl))
        ? baseURL.replace(/\/+$/, '') + '/' + rawUrl.replace(/^\/+/, '')
        : rawUrl;

      var mergedParams = Object.assign({}, defaults.params || {}, cfg.params || {});
      if (Object.keys(mergedParams).length > 0) {
        fullUrl = appendParams(fullUrl, mergedParams);
      }

      var mergedHeaders = Object.assign(
        {},
        (defaults.headers && defaults.headers.common) || {},
        (defaults.headers && defaults.headers[method.toLowerCase()]) || {},
        defaults.headers || {},
        cfg.headers || {}
      );
      delete mergedHeaders.common;
      delete mergedHeaders.get;
      delete mergedHeaders.post;
      delete mergedHeaders.put;
      delete mergedHeaders.delete;

      var bodyStr = '';
      if (cfg.data !== undefined && cfg.data !== null) {
        if (typeof cfg.data === 'string') {
          bodyStr = cfg.data;
        } else {
          var ct = mergedHeaders['Content-Type'] || mergedHeaders['content-type'] || '';
          if (ct.indexOf('application/x-www-form-urlencoded') >= 0) {
            bodyStr = qs.stringify(cfg.data);
          } else {
            bodyStr = JSON.stringify(cfg.data);
            if (!ct) mergedHeaders['Content-Type'] = 'application/json';
          }
        }
      }

      var responseType = cfg.responseType || defaults.responseType || 'json';
      var timeout = cfg.timeout || defaults.timeout || 12000;

      return nativeHttp(method, fullUrl, mergedHeaders, bodyStr, responseType, timeout).then(function(res) {
        var data = res.body;
        if (res.isBase64) {
          var buf = SodaBuffer.from(res.body, 'base64');
          data = responseType === 'arraybuffer' ? buf.buffer : buf;
        } else if (responseType !== 'text' && typeof res.body === 'string') {
          var contentType = (res.headers && (res.headers['content-type'] || res.headers['Content-Type'])) || '';
          var trimmed = res.body.trim();
          if (contentType.indexOf('json') >= 0 || trimmed.charAt(0) === '{' || trimmed.charAt(0) === '[') {
            try { data = JSON.parse(trimmed); } catch (_) {}
          }
        }

        var responseObj = {
          data: data,
          status: res.status,
          statusText: res.statusText,
          headers: res.headers || {},
          config: cfg
        };

        var validate = cfg.validateStatus || defaults.validateStatus || function(s) { return s >= 200 && s < 300; };
        if (res.error || !validate(res.status)) {
          var err = new Error(res.error || ('Request failed with status code ' + res.status));
          err.response = responseObj;
          err.config = cfg;
          throw err;
        }
        return responseObj;
      });
    }

    axiosCore.defaults = defaults;
    axiosCore.request = function(cfg) { return axiosCore(cfg); };
    axiosCore.get = function(url, cfg) { return axiosCore(Object.assign({}, cfg || {}, { method: 'GET', url: url })); };
    axiosCore.delete = function(url, cfg) { return axiosCore(Object.assign({}, cfg || {}, { method: 'DELETE', url: url })); };
    axiosCore.post = function(url, data, cfg) { return axiosCore(Object.assign({}, cfg || {}, { method: 'POST', url: url, data: data })); };
    axiosCore.put = function(url, data, cfg) { return axiosCore(Object.assign({}, cfg || {}, { method: 'PUT', url: url, data: data })); };
    axiosCore.create = function(newDefaults) { return createAxiosInstance(Object.assign({}, defaults, newDefaults || {})); };
    return axiosCore;
  }

  var axios = createAxiosInstance();

  // 4. CryptoJS Shim
  function wrapWordArray(buf) {
    return {
      _buf: buf,
      toString: function(encoder) {
        if (!encoder || encoder === CryptoJS.enc.Hex) return buf.toString('hex');
        if (encoder === CryptoJS.enc.Base64) return buf.toString('base64');
        if (encoder === CryptoJS.enc.Utf8) return buf.toString('utf8');
        if (encoder === CryptoJS.enc.Latin1) return buf.toString('latin1');
        return buf.toString('hex');
      }
    };
  }

  function toUtf8String(input) {
    if (input == null) return '';
    if (typeof input === 'string') return input;
    if (input._buf) return input._buf.toString('utf8');
    if (SodaBuffer.isBuffer(input)) return input.toString('utf8');
    return String(input);
  }

  var CryptoJS = {
    enc: {
      Utf8: {
        parse: function(str) { return wrapWordArray(SodaBuffer.from(String(str), 'utf8')); },
        stringify: function(wa) { return wa && wa._buf ? wa._buf.toString('utf8') : String(wa || ''); }
      },
      Hex: {
        parse: function(str) { return wrapWordArray(SodaBuffer.from(String(str), 'hex')); },
        stringify: function(wa) { return wa && wa._buf ? wa._buf.toString('hex') : String(wa || ''); }
      },
      Base64: {
        parse: function(str) { return wrapWordArray(SodaBuffer.from(String(str), 'base64')); },
        stringify: function(wa) { return wa && wa._buf ? wa._buf.toString('base64') : String(wa || ''); }
      },
      Latin1: {
        parse: function(str) { return wrapWordArray(SodaBuffer.from(String(str), 'latin1')); },
        stringify: function(wa) { return wa && wa._buf ? wa._buf.toString('latin1') : String(wa || ''); }
      }
    },
    MD5: function(text) {
      var hex = _SodaNative.cryptoDigest('MD5', toUtf8String(text));
      return wrapWordArray(SodaBuffer.from(hex, 'hex'));
    },
    SHA1: function(text) {
      var hex = _SodaNative.cryptoDigest('SHA-1', toUtf8String(text));
      return wrapWordArray(SodaBuffer.from(hex, 'hex'));
    },
    SHA256: function(text) {
      var hex = _SodaNative.cryptoDigest('SHA-256', toUtf8String(text));
      return wrapWordArray(SodaBuffer.from(hex, 'hex'));
    },
    HmacSHA1: function(text, key) {
      var hex = _SodaNative.cryptoHmac('HmacSHA1', toUtf8String(key), toUtf8String(text));
      return wrapWordArray(SodaBuffer.from(hex, 'hex'));
    },
    HmacSHA256: function(text, key) {
      var hex = _SodaNative.cryptoHmac('HmacSHA256', toUtf8String(key), toUtf8String(text));
      return wrapWordArray(SodaBuffer.from(hex, 'hex'));
    }
  };

  // 5. Cheerio Shim
  var cheerio = {
    load: function(html) {
      var parser = new DOMParser();
      var doc = parser.parseFromString(String(html || ''), 'text/html');

      function CheerioSelection(elements) {
        this._els = elements || [];
        this.length = this._els.length;
        for (var i = 0; i < this._els.length; i++) {
          this[i] = this._els[i];
        }
      }

      CheerioSelection.prototype.text = function() {
        return this._els.map(function(el) { return el.textContent || ''; }).join('');
      };

      CheerioSelection.prototype.html = function() {
        return this._els.length > 0 ? (this._els[0].innerHTML || '') : null;
      };

      CheerioSelection.prototype.attr = function(k, v) {
        if (this._els.length === 0) return undefined;
        if (v === undefined) {
          var val = this._els[0].getAttribute(k);
          return val === null ? undefined : val;
        }
        this._els.forEach(function(el) { el.setAttribute(k, String(v)); });
        return this;
      };

      CheerioSelection.prototype.find = function(sel) {
        var found = [];
        this._els.forEach(function(el) {
          if (el && el.querySelectorAll) {
            var list = el.querySelectorAll(sel);
            for (var i = 0; i < list.length; i++) {
              if (found.indexOf(list[i]) === -1) found.push(list[i]);
            }
          }
        });
        return new CheerioSelection(found);
      };

      CheerioSelection.prototype.eq = function(idx) {
        var el = this._els[idx];
        return new CheerioSelection(el ? [el] : []);
      };

      CheerioSelection.prototype.first = function() {
        return this.eq(0);
      };

      CheerioSelection.prototype.last = function() {
        return this._els.length > 0 ? this.eq(this._els.length - 1) : new CheerioSelection([]);
      };

      CheerioSelection.prototype.each = function(fn) {
        for (var i = 0; i < this._els.length; i++) {
          if (fn.call(this._els[i], i, this._els[i]) === false) break;
        }
        return this;
      };

      CheerioSelection.prototype.map = function(fn) {
        var res = [];
        for (var i = 0; i < this._els.length; i++) {
          var val = fn.call(this._els[i], i, this._els[i]);
          if (val !== null && val !== undefined) res.push(val);
        }
        var sel = new CheerioSelection(res);
        sel.get = function() { return res; };
        return sel;
      };

      CheerioSelection.prototype.get = function(idx) {
        if (idx === undefined) return this._els.slice();
        return this._els[idx];
      };

      CheerioSelection.prototype.children = function(sel) {
        var out = [];
        this._els.forEach(function(el) {
          var ch = el.children || [];
          for (var i = 0; i < ch.length; i++) {
            if (!sel || ch[i].matches(sel)) out.push(ch[i]);
          }
        });
        return new CheerioSelection(out);
      };

      CheerioSelection.prototype.parent = function() {
        var out = [];
        this._els.forEach(function(el) {
          if (el.parentElement && out.indexOf(el.parentElement) === -1) out.push(el.parentElement);
        });
        return new CheerioSelection(out);
      };

      function ${'$'}(selector, context) {
        if (!selector) return new CheerioSelection([]);
        if (selector instanceof CheerioSelection) return selector;
        if (selector.nodeType) return new CheerioSelection([selector]);
        if (Array.isArray(selector)) return new CheerioSelection(selector);
        if (typeof selector === 'string') {
          var root = context ? (context._els ? context._els[0] : context) : doc;
          if (!root || !root.querySelectorAll) return new CheerioSelection([]);
          var nodes = root.querySelectorAll(selector);
          return new CheerioSelection(Array.prototype.slice.call(nodes));
        }
        return new CheerioSelection([]);
      }

      ${'$'}.html = function() {
        return doc.documentElement ? doc.documentElement.outerHTML : '';
      };

      return ${'$'};
    }
  };

  function makeRequire() {
    return function(name) {
      switch (name) {
        case 'axios': return axios;
        case 'crypto-js': return CryptoJS;
        case 'cheerio': return cheerio;
        case 'qs': return qs;
        case 'buffer': return { Buffer: SodaBuffer };
        case 'url': return { URL: window.URL, URLSearchParams: window.URLSearchParams };
        default: return {};
      }
    };
  }

  // 6. Plugin Registry & Normalization Helpers
  window.__sodaPlugins = {};

  function normalizeTrack(item, pluginId) {
    if (!item || typeof item !== 'object') return null;
    var durationSec = 0;
    if (typeof item.duration === 'number') {
      durationSec = item.duration > 10000 ? Math.floor(item.duration / 1000) : item.duration;
    } else if (typeof item.interval === 'number') {
      durationSec = item.interval;
    }
    var rawJson = '';
    try { rawJson = JSON.stringify(item); } catch (_) { rawJson = '{}'; }
    return {
      id: String(item.id || item.songmid || item.hash || ''),
      title: String(item.title || item.name || item.songname || 'Unknown'),
      artist: String(item.artist || item.singer || ''),
      album: String(item.album || item.albumName || ''),
      durationMs: Math.max(0, Math.round(durationSec * 1000)),
      albumArtUri: String(item.artwork || item.img || item.pic || item.cover || ''),
      pluginId: String(pluginId || ''),
      rawItemJson: rawJson
    };
  }

  function detectCapabilities(p) {
    var caps = [];
    if (p.type === 'lx' || p.lxHandler) {
      caps.push('musicUrl');
      if (p.lxSources && Object.keys(p.lxSources).length > 0) caps.push('sources');
    }
    var exp = p.exports || {};
    if (typeof exp.search === 'function') caps.push('search');
    if (typeof exp.getMediaSource === 'function') caps.push('getMediaSource');
    if (typeof exp.getLyric === 'function') caps.push('getLyric');
    if (typeof exp.importMusicSheet === 'function') caps.push('importMusicSheet');
    if (typeof exp.getTopLists === 'function') caps.push('getTopLists');
    return caps;
  }

  function withTimeout(promise, ms, msg) {
    return Promise.race([
      Promise.resolve(promise),
      new Promise(function(_, reject) {
        setTimeout(function() { reject(new Error(msg || 'Operation timed out')); }, ms);
      })
    ]);
  }

  window.__sodaLoadPlugin = function(callId, pluginId, scriptKey, type) {
    try {
      var code = _SodaNative.takePayload(scriptKey);
      var module = { exports: {} };
      var lxHandler = null;
      var lxSources = {};

      var lx = {
        EVENT_NAMES: {
          request: 'request',
          inited: 'inited',
          updateAlert: 'updateAlert'
        },
        env: 'mobile',
        version: '2.0.0',
        currentScriptInfo: { name: pluginId, version: '1.0.0', rawScript: code },
        on: function(ev, fn) {
          if (ev === 'request' && typeof fn === 'function') {
            lxHandler = fn;
          }
        },
        send: function(ev, data) {
          if (ev === 'inited' && data && data.sources) {
            lxSources = data.sources;
          }
          return Promise.resolve();
        },
        request: function(url, opts, cb) {
          if (typeof opts === 'function') {
            cb = opts;
            opts = {};
          }
          var options = opts || {};
          var headers = Object.assign({}, options.headers || {});
          var reqCfg = {
            url: url,
            method: (options.method || 'GET').toUpperCase(),
            headers: headers,
            timeout: options.timeout || 12000,
            responseType: options.responseType || 'text',
            validateStatus: function() { return true; }
          };
          if (options.body !== undefined) {
            reqCfg.data = options.body;
          } else if (options.form !== undefined) {
            headers['Content-Type'] = headers['Content-Type'] || 'application/x-www-form-urlencoded';
            reqCfg.data = options.form;
          } else if (options.formData !== undefined) {
            reqCfg.data = options.formData;
          }

          var p = axios(reqCfg).then(function(res) {
            var body = res.data;
            if (typeof body === 'string') {
              var tr = body.trim();
              if (tr.charAt(0) === '{' || tr.charAt(0) === '[') {
                try { body = JSON.parse(tr); } catch (_) {}
              }
            }
            var respObj = {
              statusCode: res.status,
              status: res.status,
              headers: res.headers,
              body: body
            };
            if (typeof cb === 'function') cb(null, respObj, body);
            return respObj;
          }, function(err) {
            if (typeof cb === 'function') cb(err, null, null);
            else throw err;
          });
          return p;
        },
        utils: {
          buffer: {
            from: SodaBuffer.from,
            bufToString: function(b, e) { return SodaBuffer.from(b).toString(e); }
          },
          crypto: {
            md5: function(s) { return CryptoJS.MD5(s).toString(); },
            randomBytes: function(n) {
              var arr = new Uint8Array(n || 0);
              if (window.crypto && window.crypto.getRandomValues) {
                window.crypto.getRandomValues(arr);
              } else {
                for (var i = 0; i < arr.length; i++) arr[i] = Math.floor(Math.random() * 256);
              }
              return new SodaBuffer(arr);
            }
          }
        }
      };

      window.lx = lx;
      if (typeof globalThis !== 'undefined') globalThis.lx = lx;

      var factory = new Function(
        'module', 'exports', 'require', 'lx', 'Buffer', 'console',
        code + '\n;return module.exports;'
      );
      var exported = factory(module, module.exports, makeRequire(), lx, SodaBuffer, console);
      if (exported && typeof exported === 'object') {
        module.exports = exported;
      }

      var pluginEntry = {
        type: type || (lxHandler ? 'lx' : 'musicfree'),
        exports: module.exports || {},
        lx: lx,
        lxHandler: lxHandler,
        lxSources: lxSources
      };
      window.__sodaPlugins[pluginId] = pluginEntry;

      _SodaNative.onRpcResult(callId, JSON.stringify({
        ok: true,
        capabilities: detectCapabilities(pluginEntry),
        lxSources: Object.keys(lxSources || {})
      }));
    } catch (e) {
      _SodaNative.onRpcResult(callId, JSON.stringify({
        ok: false,
        error: e && e.message ? e.message : String(e)
      }));
    }
  };

  window.__sodaTestPlugin = async function(callId, pluginId) {
    var started = Date.now();
    try {
      var p = window.__sodaPlugins[pluginId];
      if (!p) {
        _SodaNative.onRpcResult(callId, JSON.stringify({
          ok: false,
          latencyMs: Date.now() - started,
          capabilities: [],
          summary: 'Plugin not loaded',
          sampleCount: 0
        }));
        return;
      }

      var caps = detectCapabilities(p);
      if (p.exports && typeof p.exports.search === 'function') {
        var res = await withTimeout(p.exports.search('晴天', 1, 'music'), 8000, 'Search test timed out');
        var list = Array.isArray(res) ? res : (res && Array.isArray(res.data) ? res.data : []);
        _SodaNative.onRpcResult(callId, JSON.stringify({
          ok: true,
          latencyMs: Date.now() - started,
          capabilities: caps,
          summary: 'Search OK (' + list.length + ' items)',
          sampleCount: list.length
        }));
        return;
      }

      if (p.lxHandler) {
        var sources = Object.keys(p.lxSources || {});
        _SodaNative.onRpcResult(callId, JSON.stringify({
          ok: true,
          latencyMs: Date.now() - started,
          capabilities: caps,
          summary: 'LX handler ready (sources: ' + (sources.length ? sources.join(', ') : 'default') + ')',
          sampleCount: sources.length
        }));
        return;
      }

      _SodaNative.onRpcResult(callId, JSON.stringify({
        ok: false,
        latencyMs: Date.now() - started,
        capabilities: caps,
        summary: 'No supported entry point found',
        sampleCount: 0
      }));
    } catch (e) {
      _SodaNative.onRpcResult(callId, JSON.stringify({
        ok: false,
        latencyMs: Date.now() - started,
        capabilities: [],
        summary: e && e.message ? e.message : String(e),
        sampleCount: 0
      }));
    }
  };

  window.__sodaSearch = async function(callId, pluginId, queryB64, page) {
    try {
      var p = window.__sodaPlugins[pluginId];
      if (!p || !p.exports || typeof p.exports.search !== 'function') {
        _SodaNative.onRpcResult(callId, JSON.stringify({ ok: false, error: 'Search not supported', tracks: [] }));
        return;
      }
      var query = SodaBuffer.from(queryB64, 'base64').toString('utf8');
      var res = await p.exports.search(query, page || 1, 'music');
      var rawList = Array.isArray(res) ? res : (res && Array.isArray(res.data) ? res.data : []);
      var tracks = [];
      for (var i = 0; i < rawList.length; i++) {
        var t = normalizeTrack(rawList[i], pluginId);
        if (t) tracks.push(t);
      }
      _SodaNative.onRpcResult(callId, JSON.stringify({ ok: true, tracks: tracks }));
    } catch (e) {
      _SodaNative.onRpcResult(callId, JSON.stringify({
        ok: false,
        error: e && e.message ? e.message : String(e),
        tracks: []
      }));
    }
  };

  window.__sodaResolveUrl = async function(callId, pluginId, rawItemB64, quality, source) {
    try {
      var p = window.__sodaPlugins[pluginId];
      if (!p) {
        _SodaNative.onRpcResult(callId, JSON.stringify({ ok: false, error: 'Plugin not loaded' }));
        return;
      }
      var item = JSON.parse(SodaBuffer.from(rawItemB64, 'base64').toString('utf8'));
      var q = quality || 'standard';

      if (p.exports && typeof p.exports.getMediaSource === 'function') {
        var mfMap = { '128k': 'standard', '320k': 'high', 'flac': 'super', 'flac24bit': 'super', '24bit': 'super' };
        var mfQ = mfMap[q] || q;
        var res = await p.exports.getMediaSource(item, mfQ);
        if (typeof res === 'string') {
          _SodaNative.onRpcResult(callId, JSON.stringify({ ok: !!res, url: res, headers: {}, quality: q }));
          return;
        }
        var url = res && res.url ? res.url : '';
        var headers = (res && res.headers) ? Object.assign({}, res.headers) : {};
        if (res && res.userAgent && !headers['User-Agent'] && !headers['user-agent']) {
          headers['User-Agent'] = res.userAgent;
        }
        _SodaNative.onRpcResult(callId, JSON.stringify({
          ok: !!url,
          url: url,
          headers: headers,
          quality: q,
          error: url ? null : 'Empty media URL'
        }));
        return;
      }

      if (p.lxHandler) {
        if (p.lx) {
          window.lx = p.lx;
          if (typeof globalThis !== 'undefined') globalThis.lx = p.lx;
        }
        var src = source || item.source || (Object.keys(p.lxSources || {})[0]) || 'tx';
        var qMap = { standard: '320k', high: '320k', lossless: 'flac', super: 'flac', master: 'flac24bit', hires: 'flac24bit', low: '128k' };
        var mappedQ = qMap[q] || q;
        var srcMeta = p.lxSources && p.lxSources[src];
        if (srcMeta && Array.isArray(srcMeta.qualitys)) {
          if ((mappedQ === 'flac24bit' || mappedQ === '24bit') && srcMeta.qualitys.indexOf(mappedQ) === -1) {
            if (mappedQ === 'flac24bit' && srcMeta.qualitys.indexOf('24bit') !== -1) {
              mappedQ = '24bit';
            } else if (mappedQ === '24bit' && srcMeta.qualitys.indexOf('flac24bit') !== -1) {
              mappedQ = 'flac24bit';
            } else if (srcMeta.qualitys.indexOf('flac') !== -1) {
              mappedQ = 'flac';
            }
          }
        }
        var finalUrl = '';
        var finalHeaders = {};
        var lastErr = '';
        try {
          var lxUrl = await p.lxHandler({
            source: src,
            action: 'musicUrl',
            info: { type: mappedQ, musicInfo: item }
          });
          var u = typeof lxUrl === 'string' ? lxUrl : (lxUrl && lxUrl.url ? lxUrl.url : '');
          if (u && /^https?:\/\//i.test(u)) {
            finalUrl = u;
            finalHeaders = (lxUrl && lxUrl.headers) ? lxUrl.headers : {};
          }
        } catch (eTry) {
          lastErr = eTry && eTry.message ? eTry.message : String(eTry);
        }
        _SodaNative.onRpcResult(callId, JSON.stringify({
          ok: !!finalUrl,
          url: finalUrl,
          headers: finalHeaders,
          quality: mappedQ,
          error: finalUrl ? null : (lastErr || 'Empty LX media URL')
        }));
        return;
      }

      _SodaNative.onRpcResult(callId, JSON.stringify({ ok: false, error: 'URL resolution not supported' }));
    } catch (e) {
      _SodaNative.onRpcResult(callId, JSON.stringify({
        ok: false,
        error: e && e.message ? e.message : String(e)
      }));
    }
  };

  window.__sodaResolveLyric = async function(callId, pluginId, rawItemB64) {
    try {
      var p = window.__sodaPlugins[pluginId];
      if (!p) {
        _SodaNative.onRpcResult(callId, JSON.stringify({ ok: false, raw: '', translation: '' }));
        return;
      }
      var item = JSON.parse(SodaBuffer.from(rawItemB64, 'base64').toString('utf8'));

      if (p.exports && typeof p.exports.getLyric === 'function') {
        var res = await p.exports.getLyric(item);
        var raw = (res && (res.rawLrc || res.lyric || res.lrc)) || '';
        var trans = (res && (res.translation || res.tlyric)) || '';
        _SodaNative.onRpcResult(callId, JSON.stringify({ ok: true, raw: String(raw), translation: String(trans) }));
        return;
      }

      if (p.lxHandler) {
        if (p.lx) {
          window.lx = p.lx;
          if (typeof globalThis !== 'undefined') globalThis.lx = p.lx;
        }
        var src = item.source || (Object.keys(p.lxSources || {})[0]) || 'tx';
        var lxRes = await p.lxHandler({
          source: src,
          action: 'lyric',
          info: { musicInfo: item }
        });
        var lxRaw = (lxRes && (lxRes.lyric || lxRes.rawLrc || lxRes.lrc)) || (typeof lxRes === 'string' ? lxRes : '');
        var lxTrans = (lxRes && (lxRes.tlyric || lxRes.translation)) || '';
        _SodaNative.onRpcResult(callId, JSON.stringify({ ok: true, raw: String(lxRaw), translation: String(lxTrans) }));
        return;
      }

      _SodaNative.onRpcResult(callId, JSON.stringify({ ok: false, raw: '', translation: '' }));
    } catch (e) {
      _SodaNative.onRpcResult(callId, JSON.stringify({
        ok: false,
        raw: '',
        translation: '',
        error: e && e.message ? e.message : String(e)
      }));
    }
  };

  window.__sodaImportSheet = async function(callId, pluginId, urlOrIdB64) {
    try {
      var p = window.__sodaPlugins[pluginId];
      if (!p || !p.exports || typeof p.exports.importMusicSheet !== 'function') {
        _SodaNative.onRpcResult(callId, JSON.stringify({ ok: false, tracks: [] }));
        return;
      }
      var arg = SodaBuffer.from(urlOrIdB64, 'base64').toString('utf8');
      var res = await p.exports.importMusicSheet(arg);
      var rawList = Array.isArray(res) ? res : (res && Array.isArray(res.data) ? res.data : (res && Array.isArray(res.musicList) ? res.musicList : []));
      var tracks = [];
      for (var i = 0; i < rawList.length; i++) {
        var t = normalizeTrack(rawList[i], pluginId);
        if (t) tracks.push(t);
      }
      _SodaNative.onRpcResult(callId, JSON.stringify({ ok: true, tracks: tracks }));
    } catch (e) {
      _SodaNative.onRpcResult(callId, JSON.stringify({
        ok: false,
        error: e && e.message ? e.message : String(e),
        tracks: []
      }));
    }
  };
})();
""".trimIndent()
}
