package com.sodapulse.music

import android.Manifest
import android.animation.ValueAnimator
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ImageFormat
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.SurfaceTexture
import android.graphics.drawable.GradientDrawable
import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.media.Image
import android.media.ImageReader
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.util.Size
import android.util.TypedValue
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.Surface
import android.view.TextureView
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.WindowManager
import android.view.animation.LinearInterpolator
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import com.google.zxing.BarcodeFormat
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.MultiFormatReader
import com.google.zxing.NotFoundException
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.RGBLuminanceSource
import com.google.zxing.common.GlobalHistogramBinarizer
import com.google.zxing.common.HybridBinarizer
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.abs
import kotlin.math.max

class QrScannerActivity : Activity() {

    companion object {
        const val EXTRA_QR_TEXT = "extra_qr_text"
        private const val REQUEST_CAMERA_PERMISSION = 2001
        private const val REQUEST_PICK_IMAGE = 2002

        private const val EMERALD = 0xFF2FE08B.toInt()
        private const val BG_DARK = 0xFF0A0F0D.toInt()
        private const val MASK_COLOR = 0xA6000000.toInt()
        private const val FRAME_DECODE_INTERVAL_MS = 120L
        private const val GALLERY_MAX_DIMENSION = 1440
    }

    private lateinit var rootLayout: FrameLayout
    private lateinit var textureView: TextureView
    private lateinit var overlayView: QrScannerOverlayView
    private lateinit var topBar: LinearLayout
    private lateinit var bottomBar: LinearLayout
    private lateinit var permissionPromptContainer: LinearLayout
    private lateinit var torchButton: TextView

    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private var imageReader: ImageReader? = null
    private var previewRequestBuilder: CaptureRequest.Builder? = null

    private var backgroundThread: HandlerThread? = null
    private var backgroundHandler: Handler? = null
    private val galleryExecutor = Executors.newSingleThreadExecutor()

    private var cameraId: String? = null
    private var sensorOrientation: Int = 90
    private var hasFlash: Boolean = false
    private var previewSize: Size = Size(1280, 720)
    private var analysisSize: Size = Size(1280, 720)

    private var isTorchOn = false
    private var lastDecodeTimestamp = 0L
    private val isDecoded = AtomicBoolean(false)

    private val qrReader: MultiFormatReader by lazy {
        MultiFormatReader().apply {
            setHints(
                mapOf(
                    DecodeHintType.POSSIBLE_FORMATS to listOf(BarcodeFormat.QR_CODE),
                    DecodeHintType.TRY_HARDER to true,
                    DecodeHintType.CHARACTER_SET to "UTF-8"
                )
            )
        }
    }

    private val surfaceTextureListener = object : TextureView.SurfaceTextureListener {
        override fun onSurfaceTextureAvailable(surface: SurfaceTexture, width: Int, height: Int) {
            if (hasCameraPermission()) {
                openCamera(width, height)
            }
        }

        override fun onSurfaceTextureSizeChanged(surface: SurfaceTexture, width: Int, height: Int) {
            configureTransform(width, height)
        }

        override fun onSurfaceTextureDestroyed(surface: SurfaceTexture): Boolean = true

        override fun onSurfaceTextureUpdated(surface: SurfaceTexture) = Unit
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setupEdgeToEdge()
        buildUi()
        applyWindowInsets()

        if (!hasCameraPermission()) {
            showPermissionDeniedUi(true)
            requestPermissions(arrayOf(Manifest.permission.CAMERA), REQUEST_CAMERA_PERMISSION)
        } else {
            showPermissionDeniedUi(false)
        }
    }

    override fun onResume() {
        super.onResume()
        startBackgroundThread()
        if (hasCameraPermission()) {
            showPermissionDeniedUi(false)
            if (textureView.isAvailable) {
                openCamera(textureView.width, textureView.height)
            } else {
                textureView.surfaceTextureListener = surfaceTextureListener
            }
        } else {
            showPermissionDeniedUi(true)
        }
    }

    override fun onPause() {
        closeCamera()
        stopBackgroundThread()
        super.onPause()
    }

    override fun onDestroy() {
        closeCamera()
        stopBackgroundThread()
        galleryExecutor.shutdownNow()
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_CAMERA_PERMISSION) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            if (granted) {
                showPermissionDeniedUi(false)
                if (textureView.isAvailable) {
                    openCamera(textureView.width, textureView.height)
                } else {
                    textureView.surfaceTextureListener = surfaceTextureListener
                }
            } else {
                showPermissionDeniedUi(true)
            }
        }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_PICK_IMAGE && resultCode == RESULT_OK) {
            val uri = data?.data ?: return
            decodeQrFromUri(uri)
        }
    }

    private fun setupEdgeToEdge() {
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        @Suppress("DEPRECATION")
        window.statusBarColor = Color.TRANSPARENT
        @Suppress("DEPRECATION")
        window.navigationBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                )
        }
    }

    private fun buildUi() {
        rootLayout = FrameLayout(this).apply {
            setBackgroundColor(BG_DARK)
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }

        textureView = TextureView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
            surfaceTextureListener = this@QrScannerActivity.surfaceTextureListener
        }
        rootLayout.addView(textureView)

        overlayView = QrScannerOverlayView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        }
        rootLayout.addView(overlayView)

        permissionPromptContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            visibility = View.GONE
            setBackgroundColor(0xE60A0F0D.toInt())
            setPadding(dp(32), dp(24), dp(32), dp(24))
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        }

        val promptText = TextView(this).apply {
            text = "需要相机权限以扫码，也可点击“相册”识图"
            setTextColor(0xFFEAF7F0.toInt())
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            gravity = Gravity.CENTER
            setLineSpacing(dp(4).toFloat(), 1f)
        }
        permissionPromptContainer.addView(promptText)

        val retryPermBtn = TextView(this).apply {
            text = "授予相机权限"
            setTextColor(0xFF07140D.toInt())
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            gravity = Gravity.CENTER
            setPadding(dp(20), dp(10), dp(20), dp(10))
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dp(22).toFloat()
                setColor(EMERALD)
            }
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                topMargin = dp(18)
            }
            setOnClickListener {
                requestPermissions(arrayOf(Manifest.permission.CAMERA), REQUEST_CAMERA_PERMISSION)
            }
        }
        permissionPromptContainer.addView(retryPermBtn)
        rootLayout.addView(permissionPromptContainer)

        topBar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(16), dp(12), dp(16), dp(12))
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.TOP
            )
        }

        val backButton = TextView(this).apply {
            text = "←"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 20f)
            gravity = Gravity.CENTER
            background = createCircleDrawable(0x4D000000, 0x33FFFFFF, dp(1))
            layoutParams = LinearLayout.LayoutParams(dp(42), dp(42))
            setOnClickListener {
                setResult(RESULT_CANCELED)
                finish()
            }
        }
        topBar.addView(backButton)

        val titleView = TextView(this).apply {
            text = "扫码添加音源"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
            gravity = Gravity.CENTER
            paint.isFakeBoldText = true
            layoutParams = LinearLayout.LayoutParams(
                0,
                LinearLayout.LayoutParams.WRAP_CONTENT,
                1f
            ).apply {
                marginStart = dp(12)
                marginEnd = dp(12)
            }
        }
        topBar.addView(titleView)

        val topGalleryPill = TextView(this).apply {
            text = "相册"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            gravity = Gravity.CENTER
            setPadding(dp(16), dp(8), dp(16), dp(8))
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dp(20).toFloat()
                setColor(0x4D000000)
                setStroke(dp(1), 0x33FFFFFF)
            }
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                dp(38)
            )
            setOnClickListener { openGalleryPicker() }
        }
        topBar.addView(topGalleryPill)
        rootLayout.addView(topBar)

        bottomBar = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(24), dp(12), dp(24), dp(24))
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM
            )
        }

        val hintText = TextView(this).apply {
            text = "将音源插件链接 / 订阅二维码放入框内自动识别"
            setTextColor(0xCCFFFFFF.toInt())
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                bottomMargin = dp(24)
            }
        }
        bottomBar.addView(hintText)

        val actionRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        }

        torchButton = createBottomActionButton("手电筒") {
            toggleTorch()
        }
        actionRow.addView(
            torchButton,
            LinearLayout.LayoutParams(dp(72), dp(72)).apply {
                marginEnd = dp(48)
            }
        )

        val bottomGalleryButton = createBottomActionButton("相册识图") {
            openGalleryPicker()
        }
        actionRow.addView(
            bottomGalleryButton,
            LinearLayout.LayoutParams(dp(72), dp(72))
        )

        bottomBar.addView(actionRow)
        rootLayout.addView(bottomBar)

        setContentView(rootLayout)
    }

    private fun createBottomActionButton(label: String, onClick: () -> Unit): TextView {
        return TextView(this).apply {
            text = label
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            gravity = Gravity.CENTER
            setPadding(dp(6), dp(6), dp(6), dp(6))
            background = createCircleDrawable(0x660F1714, 0x33FFFFFF, dp(1))
            setOnClickListener { onClick() }
        }
    }

    private fun updateTorchUi() {
        torchButton.background = if (isTorchOn) {
            createCircleDrawable(0x332FE08B, EMERALD, dp(2))
        } else {
            createCircleDrawable(0x660F1714, 0x33FFFFFF, dp(1))
        }
        torchButton.setTextColor(if (isTorchOn) EMERALD else Color.WHITE)
    }

    private fun createCircleDrawable(fillColor: Int, strokeColor: Int, strokeWidth: Int): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(fillColor)
            setStroke(strokeWidth, strokeColor)
        }
    }

    private fun applyWindowInsets() {
        val statusFallback = getStatusBarHeightFallback()
        topBar.setPadding(dp(16), statusFallback + dp(10), dp(16), dp(10))

        rootLayout.setOnApplyWindowInsetsListener { _, insets ->
            val topInset: Int
            val bottomInset: Int
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val sysBars = insets.getInsets(WindowInsets.Type.systemBars())
                topInset = sysBars.top
                bottomInset = sysBars.bottom
            } else {
                @Suppress("DEPRECATION")
                topInset = insets.systemWindowInsetTop
                @Suppress("DEPRECATION")
                bottomInset = insets.systemWindowInsetBottom
            }
            topBar.setPadding(dp(16), topInset + dp(10), dp(16), dp(10))
            bottomBar.setPadding(dp(24), dp(12), dp(24), bottomInset + dp(24))
            insets
        }
        rootLayout.requestApplyInsets()
    }

    private fun getStatusBarHeightFallback(): Int {
        val resId = resources.getIdentifier("status_bar_height", "dimen", "android")
        return if (resId > 0) resources.getDimensionPixelSize(resId) else dp(24)
    }

    private fun showPermissionDeniedUi(show: Boolean) {
        permissionPromptContainer.visibility = if (show) View.VISIBLE else View.GONE
        overlayView.visibility = if (show) View.GONE else View.VISIBLE
    }

    private fun hasCameraPermission(): Boolean {
        return checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
    }

    private fun startBackgroundThread() {
        if (backgroundThread == null) {
            backgroundThread = HandlerThread("QrCameraThread").apply { start() }
            backgroundHandler = Handler(backgroundThread!!.looper)
        }
    }

    private fun stopBackgroundThread() {
        backgroundThread?.quitSafely()
        try {
            backgroundThread?.join(500)
        } catch (_: InterruptedException) {
        }
        backgroundThread = null
        backgroundHandler = null
    }

    private fun openCamera(viewWidth: Int, viewHeight: Int) {
        if (!hasCameraPermission() || cameraDevice != null) return
        val manager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
        try {
            val selectedId = selectBackCameraId(manager) ?: return
            cameraId = selectedId
            val characteristics = manager.getCameraCharacteristics(selectedId)
            sensorOrientation = characteristics.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 90
            hasFlash = characteristics.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
            val map = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            if (map != null) {
                previewSize = chooseOptimalSize(
                    map.getOutputSizes(SurfaceTexture::class.java),
                    1920,
                    1080
                )
                analysisSize = chooseOptimalSize(
                    map.getOutputSizes(ImageFormat.YUV_420_888),
                    1280,
                    960
                )
            }

            configureTransform(viewWidth, viewHeight)

            imageReader?.close()
            imageReader = ImageReader.newInstance(
                analysisSize.width,
                analysisSize.height,
                ImageFormat.YUV_420_888,
                2
            ).apply {
                setOnImageAvailableListener({ reader ->
                    val image = reader.acquireLatestImage() ?: return@setOnImageAvailableListener
                    processImage(image)
                }, backgroundHandler)
            }

            manager.openCamera(selectedId, object : CameraDevice.StateCallback() {
                override fun onOpened(camera: CameraDevice) {
                    cameraDevice = camera
                    createCameraPreviewSession()
                }

                override fun onDisconnected(camera: CameraDevice) {
                    camera.close()
                    if (cameraDevice === camera) cameraDevice = null
                }

                override fun onError(camera: CameraDevice, error: Int) {
                    camera.close()
                    if (cameraDevice === camera) cameraDevice = null
                }
            }, backgroundHandler)
        } catch (_: SecurityException) {
            showPermissionDeniedUi(true)
        } catch (_: CameraAccessException) {
        }
    }

    private fun selectBackCameraId(manager: CameraManager): String? {
        for (id in manager.cameraIdList) {
            val chars = manager.getCameraCharacteristics(id)
            if (chars.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK) {
                return id
            }
        }
        return manager.cameraIdList.firstOrNull()
    }

    private fun chooseOptimalSize(choices: Array<Size>?, maxW: Int, maxH: Int): Size {
        if (choices.isNullOrEmpty()) return Size(1280, 720)
        val candidates = choices.filter { it.width <= maxW && it.height <= maxH }
        val pool = if (candidates.isNotEmpty()) candidates else choices.toList()
        val targetRatio = 16f / 9f
        return pool.minByOrNull { size ->
            val ratio = size.width.toFloat() / size.height.toFloat()
            val ratioDiff = abs(ratio - targetRatio)
            ratioDiff * 1000f - (size.width * size.height) / 100000f
        } ?: pool.first()
    }

    private fun createCameraPreviewSession() {
        val camera = cameraDevice ?: return
        val texture = textureView.surfaceTexture ?: return
        val readerSurface = imageReader?.surface ?: return

        texture.setDefaultBufferSize(previewSize.width, previewSize.height)
        val previewSurface = Surface(texture)

        try {
            val builder = camera.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW).apply {
                addTarget(previewSurface)
                addTarget(readerSurface)
                set(
                    CaptureRequest.CONTROL_AF_MODE,
                    CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE
                )
                set(
                    CaptureRequest.CONTROL_AE_MODE,
                    CaptureRequest.CONTROL_AE_MODE_ON
                )
                set(
                    CaptureRequest.FLASH_MODE,
                    if (isTorchOn) CaptureRequest.FLASH_MODE_TORCH else CaptureRequest.FLASH_MODE_OFF
                )
            }
            previewRequestBuilder = builder

            @Suppress("DEPRECATION")
            camera.createCaptureSession(
                listOf(previewSurface, readerSurface),
                object : CameraCaptureSession.StateCallback() {
                    override fun onConfigured(session: CameraCaptureSession) {
                        if (cameraDevice == null) return
                        captureSession = session
                        try {
                            session.setRepeatingRequest(builder.build(), null, backgroundHandler)
                        } catch (_: CameraAccessException) {
                        }
                    }

                    override fun onConfigureFailed(session: CameraCaptureSession) = Unit
                },
                backgroundHandler
            )
        } catch (_: CameraAccessException) {
        }
    }

    private fun configureTransform(viewWidth: Int, viewHeight: Int) {
        if (viewWidth <= 0 || viewHeight <= 0) return

        val displayRotation = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display?.rotation ?: Surface.ROTATION_0
        } else {
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay.rotation
        }

        val isLandscapeDisplay =
            displayRotation == Surface.ROTATION_90 || displayRotation == Surface.ROTATION_270
        val isSensorSwapped = sensorOrientation == 90 || sensorOrientation == 270
        val swapDimensions = isSensorSwapped xor isLandscapeDisplay

        val bufferWidth = if (swapDimensions) previewSize.height else previewSize.width
        val bufferHeight = if (swapDimensions) previewSize.width else previewSize.height

        val scale = max(
            viewWidth.toFloat() / bufferWidth.toFloat(),
            viewHeight.toFloat() / bufferHeight.toFloat()
        )

        val sx = (bufferWidth * scale) / viewWidth.toFloat()
        val sy = (bufferHeight * scale) / viewHeight.toFloat()

        val matrix = Matrix()
        val centerX = viewWidth / 2f
        val centerY = viewHeight / 2f
        matrix.setScale(sx, sy, centerX, centerY)

        if (displayRotation == Surface.ROTATION_90 || displayRotation == Surface.ROTATION_270) {
            val rotationDegrees = 90f * (displayRotation - 2)
            matrix.postRotate(rotationDegrees, centerX, centerY)
        } else if (displayRotation == Surface.ROTATION_180) {
            matrix.postRotate(180f, centerX, centerY)
        }

        textureView.setTransform(matrix)
    }

    private fun toggleTorch() {
        if (!hasFlash) {
            Toast.makeText(this, "当前设备不支持闪光灯", Toast.LENGTH_SHORT).show()
            return
        }
        val session = captureSession ?: return
        val builder = previewRequestBuilder ?: return
        isTorchOn = !isTorchOn
        try {
            builder.set(
                CaptureRequest.FLASH_MODE,
                if (isTorchOn) CaptureRequest.FLASH_MODE_TORCH else CaptureRequest.FLASH_MODE_OFF
            )
            session.setRepeatingRequest(builder.build(), null, backgroundHandler)
            updateTorchUi()
        } catch (_: CameraAccessException) {
            isTorchOn = !isTorchOn
        }
    }

    private fun closeCamera() {
        isTorchOn = false
        if (::torchButton.isInitialized) {
            runOnUiThread { updateTorchUi() }
        }
        try {
            captureSession?.close()
        } catch (_: Exception) {
        }
        captureSession = null

        try {
            cameraDevice?.close()
        } catch (_: Exception) {
        }
        cameraDevice = null

        try {
            imageReader?.close()
        } catch (_: Exception) {
        }
        imageReader = null
        previewRequestBuilder = null
    }

    private fun processImage(image: Image) {
        try {
            if (isDecoded.get()) return
            val now = System.currentTimeMillis()
            if (now - lastDecodeTimestamp < FRAME_DECODE_INTERVAL_MS) return
            lastDecodeTimestamp = now

            val width = image.width
            val height = image.height
            val yPlane = image.planes[0]
            val yBuffer = yPlane.buffer
            val rowStride = yPlane.rowStride

            val yData = ByteArray(width * height)
            if (rowStride == width) {
                yBuffer.get(yData, 0, width * height)
            } else {
                for (row in 0 until height) {
                    yBuffer.position(row * rowStride)
                    yBuffer.get(yData, row * width, width)
                }
            }

            val source = PlanarYUVLuminanceSource(
                yData,
                width,
                height,
                0,
                0,
                width,
                height,
                false
            )
            val bitmap = BinaryBitmap(HybridBinarizer(source))
            val result = try {
                qrReader.decodeWithState(bitmap)
            } catch (_: NotFoundException) {
                null
            } finally {
                qrReader.reset()
            }

            val text = result?.text
            if (!text.isNullOrBlank()) {
                onQrDecoded(text)
            }
        } catch (_: Exception) {
        } finally {
            image.close()
        }
    }

    @Suppress("DEPRECATION")
    private fun openGalleryPicker() {
        val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
            type = "image/*"
        }
        startActivityForResult(Intent.createChooser(intent, "选择二维码图片"), REQUEST_PICK_IMAGE)
    }

    private fun decodeQrFromUri(uri: Uri) {
        galleryExecutor.execute {
            val decodedText = QrCodecHelper.decodeQrFromUri(this, uri)
            runOnUiThread {
                if (!decodedText.isNullOrBlank()) {
                    onQrDecoded(decodedText)
                } else {
                    Toast.makeText(this, "未在图片中识别到有效二维码", Toast.LENGTH_SHORT).show()
                }
            }
        }
    }

    private fun onQrDecoded(text: String) {
        if (!isDecoded.compareAndSet(false, true)) return
        runOnUiThread {
            val feedbackFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                HapticFeedbackConstants.CONFIRM
            } else {
                HapticFeedbackConstants.VIRTUAL_KEY
            }
            rootLayout.performHapticFeedback(feedbackFlag)
            setResult(RESULT_OK, Intent().putExtra(EXTRA_QR_TEXT, text))
            finish()
        }
    }

    private fun dp(value: Int): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            value.toFloat(),
            resources.displayMetrics
        ).toInt()
    }

    private class QrScannerOverlayView(context: Context) : View(context) {

        private val boxSizePx = dp(256f)
        private val boxCornerRadius = dp(18f)
        private val cornerLength = dp(26f)
        private val cornerStroke = dp(4f)

        private val maskPath = Path().apply {
            fillType = Path.FillType.EVEN_ODD
        }
        private val boxRect = RectF()

        private val maskPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = MASK_COLOR
            style = Paint.Style.FILL
        }

        private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0x33FFFFFF
            style = Paint.Style.STROKE
            strokeWidth = dp(1f)
        }

        private val cornerPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = EMERALD
            style = Paint.Style.STROKE
            strokeWidth = cornerStroke
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }

        private val laserPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
        }

        private val cornerPath = Path()
        private var scanProgress = 0f

        private val scanAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 2200L
            repeatCount = ValueAnimator.INFINITE
            repeatMode = ValueAnimator.RESTART
            interpolator = LinearInterpolator()
            addUpdateListener { anim ->
                scanProgress = anim.animatedValue as Float
                invalidate()
            }
        }

        override fun onAttachedToWindow() {
            super.onAttachedToWindow()
            if (!scanAnimator.isStarted) {
                scanAnimator.start()
            }
        }

        override fun onDetachedFromWindow() {
            scanAnimator.cancel()
            super.onDetachedFromWindow()
        }

        override fun onVisibilityChanged(changedView: View, visibility: Int) {
            super.onVisibilityChanged(changedView, visibility)
            if (visibility == VISIBLE && isAttachedToWindow) {
                if (!scanAnimator.isRunning) scanAnimator.start()
            } else {
                scanAnimator.pause()
            }
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val w = width.toFloat()
            val h = height.toFloat()
            if (w <= 0f || h <= 0f) return

            val left = (w - boxSizePx) / 2f
            val top = (h - boxSizePx) / 2f - dp(24f)
            val right = left + boxSizePx
            val bottom = top + boxSizePx
            boxRect.set(left, top, right, bottom)

            maskPath.reset()
            maskPath.addRect(0f, 0f, w, h, Path.Direction.CW)
            maskPath.addRoundRect(boxRect, boxCornerRadius, boxCornerRadius, Path.Direction.CCW)
            canvas.drawPath(maskPath, maskPaint)

            canvas.drawRoundRect(boxRect, boxCornerRadius, boxCornerRadius, borderPaint)
            drawCorners(canvas, left, top, right, bottom)

            val inset = dp(12f)
            val laserY = top + inset + (boxSizePx - inset * 2f) * scanProgress
            val laserLeft = left + inset
            val laserRight = right - inset
            val laserHeight = dp(2.5f)
            laserPaint.shader = LinearGradient(
                laserLeft,
                laserY,
                laserRight,
                laserY,
                intArrayOf(0x002FE08B, EMERALD, 0x002FE08B),
                floatArrayOf(0f, 0.5f, 1f),
                Shader.TileMode.CLAMP
            )
            canvas.drawRoundRect(
                laserLeft,
                laserY - laserHeight / 2f,
                laserRight,
                laserY + laserHeight / 2f,
                laserHeight / 2f,
                laserHeight / 2f,
                laserPaint
            )
        }

        private fun drawCorners(canvas: Canvas, l: Float, t: Float, r: Float, b: Float) {
            val rad = boxCornerRadius
            val len = cornerLength

            cornerPath.reset()
            cornerPath.moveTo(l, t + len)
            cornerPath.lineTo(l, t + rad)
            cornerPath.arcTo(l, t, l + rad * 2f, t + rad * 2f, 180f, 90f, false)
            cornerPath.lineTo(l + len, t)
            canvas.drawPath(cornerPath, cornerPaint)

            cornerPath.reset()
            cornerPath.moveTo(r - len, t)
            cornerPath.lineTo(r - rad, t)
            cornerPath.arcTo(r - rad * 2f, t, r, t + rad * 2f, 270f, 90f, false)
            cornerPath.lineTo(r, t + len)
            canvas.drawPath(cornerPath, cornerPaint)

            cornerPath.reset()
            cornerPath.moveTo(r, b - len)
            cornerPath.lineTo(r, b - rad)
            cornerPath.arcTo(r - rad * 2f, b - rad * 2f, r, b, 0f, 90f, false)
            cornerPath.lineTo(r - len, b)
            canvas.drawPath(cornerPath, cornerPaint)

            cornerPath.reset()
            cornerPath.moveTo(l + len, b)
            cornerPath.lineTo(l + rad, b)
            cornerPath.arcTo(l, b - rad * 2f, l + rad * 2f, b, 90f, 90f, false)
            cornerPath.lineTo(l, b - len)
            canvas.drawPath(cornerPath, cornerPaint)
        }

        private fun dp(value: Float): Float {
            return TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP,
                value,
                resources.displayMetrics
            )
        }
    }
}
