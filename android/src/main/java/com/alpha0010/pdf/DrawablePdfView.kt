package com.alpha0010.pdf

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.*
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import android.util.TypedValue
import android.util.TypedValue.COMPLEX_UNIT_DIP
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.View
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.ReactContext
import com.facebook.react.bridge.WritableMap
import com.facebook.react.uimanager.events.RCTEventEmitter
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File
import java.io.FileNotFoundException
import java.util.UUID
import java.util.concurrent.locks.Lock
import kotlin.concurrent.withLock
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.hypot

/**
 * Drawing mode enum matching TypeScript DrawingMode
 */
enum class DrawingMode(val jsName: String) {
  VIEW("view"),
  DRAW("draw"),
  ERASE("erase"),
  HIGHLIGHT("highlight")
}

/**
 * A stroke being drawn or already drawn.
 */
data class DrawingStroke(
  val id: String,
  val color: String,
  val width: Float,
  val opacity: Float,
  val path: MutableList<PointF>
)

/**
 * PDF view with native drawing and zoom support.
 * Handles touch events for drawing, erasing, highlighting, and pinch-to-zoom.
 */
@SuppressLint("ViewConstructor")
class DrawablePdfView(context: Context, private val pdfMutex: Lock) : View(context) {
  // PDF rendering state
  private var mAnnotation = emptyList<AnnotationPage>()
  private val mBitmaps = MutableList(SLICES) { Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888) }
  private var mDirty = false
  private var mPage = 0
  private var mResizeMode = ResizeMode.CONTAIN
  private var mSource = ""
  private val mViewRects = List(SLICES) { Rect() }
  private var mRenderGeneration = 0 // Used to cancel outdated renders

  // PDF content area (where PDF is actually rendered, accounting for aspect ratio)
  private var mPdfContentRect = RectF()
  private var mPdfPageWidth = 0
  private var mPdfPageHeight = 0

  // Drawing state
  private var mDrawingMode = DrawingMode.VIEW
  private var mStrokeColor = "#000000"
  private var mStrokeWidth = 3f
  private var mStrokeOpacity = 1f

  // Current strokes for this page
  private val mStrokes = mutableListOf<DrawingStroke>()

  // Currently active stroke (while drawing)
  private var mActiveStroke: DrawingStroke? = null

  // Paint for drawing strokes overlay
  private val mStrokePaint = Paint().apply {
    isAntiAlias = true
    style = Paint.Style.STROKE
    strokeCap = Paint.Cap.ROUND
    strokeJoin = Paint.Join.ROUND
  }

  // Erase threshold (3% of view size)
  private val eraseThresholdPercent = 0.03f

  // --- Zoom state ---
  private var mScale = 1f
  private var mOffsetX = 0f
  private var mOffsetY = 0f
  private var mMinScale = 1f
  private var mMaxScale = 3f
  private var mZoomEnabled = true

  // Gesture detectors
  private val mScaleDetector: ScaleGestureDetector
  private val mGestureDetector: GestureDetector

  // Track if we're currently scaling
  private var mIsScaling = false

  // For double-tap to reset zoom
  private var mLastTapTime = 0L

  init {
    // Scale gesture detector for pinch-to-zoom
    mScaleDetector = ScaleGestureDetector(context, object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
      private var focusX = 0f
      private var focusY = 0f

      override fun onScaleBegin(detector: ScaleGestureDetector): Boolean {
        if (!mZoomEnabled || mDrawingMode != DrawingMode.VIEW) return false
        mIsScaling = true
        focusX = detector.focusX
        focusY = detector.focusY
        return true
      }

      override fun onScale(detector: ScaleGestureDetector): Boolean {
        if (!mZoomEnabled || mDrawingMode != DrawingMode.VIEW) return false

        val scaleFactor = detector.scaleFactor
        val newScale = (mScale * scaleFactor).coerceIn(mMinScale, mMaxScale)

        if (newScale != mScale) {
          // Adjust offset to zoom around focus point
          val focusRatioX = (focusX - mOffsetX) / (width * mScale)
          val focusRatioY = (focusY - mOffsetY) / (height * mScale)

          mScale = newScale

          mOffsetX = focusX - focusRatioX * width * mScale
          mOffsetY = focusY - focusRatioY * height * mScale

          constrainOffset()
          invalidate()
          onZoomChange()
        }
        return true
      }

      override fun onScaleEnd(detector: ScaleGestureDetector) {
        mIsScaling = false
      }
    })

    // Gesture detector for pan and double-tap
    mGestureDetector = GestureDetector(context, object : GestureDetector.SimpleOnGestureListener() {
      override fun onScroll(e1: MotionEvent?, e2: MotionEvent, distanceX: Float, distanceY: Float): Boolean {
        if (!mZoomEnabled || mDrawingMode != DrawingMode.VIEW || mScale <= 1f) return false

        mOffsetX -= distanceX
        mOffsetY -= distanceY
        constrainOffset()
        invalidate()
        return true
      }

      override fun onDoubleTap(e: MotionEvent): Boolean {
        if (!mZoomEnabled || mDrawingMode != DrawingMode.VIEW) return false

        if (mScale > mMinScale) {
          // Reset to min scale
          mScale = mMinScale
          mOffsetX = 0f
          mOffsetY = 0f
        } else {
          // Zoom in to 2x at tap location
          val tapX = e.x
          val tapY = e.y
          val newScale = 2f.coerceAtMost(mMaxScale)

          val focusRatioX = tapX / width
          val focusRatioY = tapY / height

          mScale = newScale
          mOffsetX = tapX - focusRatioX * width * mScale
          mOffsetY = tapY - focusRatioY * height * mScale
          constrainOffset()
        }

        invalidate()
        onZoomChange()
        return true
      }

      override fun onSingleTapConfirmed(e: MotionEvent): Boolean {
        // Fire single tap in view mode when not zoomed
        if (mDrawingMode == DrawingMode.VIEW && mScale <= 1.01f) {
          onSingleTap()
          return true
        }
        return false
      }
    })
  }

  private fun constrainOffset() {
    if (mScale <= 1f) {
      mOffsetX = 0f
      mOffsetY = 0f
      return
    }

    val maxOffsetX = 0f
    val minOffsetX = width - width * mScale
    val maxOffsetY = 0f
    val minOffsetY = height - height * mScale

    mOffsetX = mOffsetX.coerceIn(minOffsetX, maxOffsetX)
    mOffsetY = mOffsetY.coerceIn(minOffsetY, maxOffsetY)
  }

  // --- Setters ---

  fun setDrawingMode(mode: String) {
    mDrawingMode = when (mode) {
      DrawingMode.VIEW.jsName -> DrawingMode.VIEW
      DrawingMode.DRAW.jsName -> DrawingMode.DRAW
      DrawingMode.ERASE.jsName -> DrawingMode.ERASE
      DrawingMode.HIGHLIGHT.jsName -> DrawingMode.HIGHLIGHT
      else -> {
        onError("Unknown drawingMode '$mode'.")
        DrawingMode.VIEW
      }
    }
  }

  fun setStrokeColor(color: String) {
    mStrokeColor = color
  }

  fun setStrokeWidth(width: Float) {
    mStrokeWidth = width
  }

  fun setStrokeOpacity(opacity: Float) {
    mStrokeOpacity = opacity
  }

  fun setMinZoom(minZoom: Float) {
    mMinScale = minZoom.coerceAtLeast(0.5f)
    if (mScale < mMinScale) {
      mScale = mMinScale
      constrainOffset()
      invalidate()
    }
  }

  fun setMaxZoom(maxZoom: Float) {
    mMaxScale = maxZoom.coerceAtLeast(1f)
    if (mScale > mMaxScale) {
      mScale = mMaxScale
      constrainOffset()
      invalidate()
    }
  }

  fun setZoomEnabled(enabled: Boolean) {
    mZoomEnabled = enabled
  }

  /**
   * Set strokes from JSON string.
   */
  fun setStrokes(strokesJson: String) {
    if (strokesJson.isEmpty()) {
      if (mStrokes.isNotEmpty()) {
        mStrokes.clear()
        invalidate()
      }
      return
    }

    try {
      val parsed = Json.decodeFromString<List<StrokeData>>(strokesJson)
      mStrokes.clear()
      for (stroke in parsed) {
        val points = stroke.path.map { PointF(it[0], it[1]) }.toMutableList()
        mStrokes.add(DrawingStroke(stroke.id, stroke.color, stroke.width, stroke.opacity, points))
      }
      invalidate()
    } catch (e: Exception) {
      onError("Failed to parse strokes JSON: ${e.message}")
    }
  }

  // --- PDF methods ---

  fun setAnnotation(source: String, file: Boolean) {
    if (source.isEmpty()) {
      if (mAnnotation.isNotEmpty()) {
        mAnnotation = emptyList()
        mDirty = true
      }
      return
    }

    try {
      mAnnotation = if (file) {
        Json.decodeFromString(File(source).readText())
      } else {
        Json.decodeFromString(source)
      }
      mDirty = true
    } catch (e: Exception) {
      onError("Failed to load annotation from '$source'. ${e.message}")
    }
  }

  fun setPage(page: Int) {
    mPage = page
    mDirty = true
    // Reset zoom when changing pages
    mScale = 1f
    mOffsetX = 0f
    mOffsetY = 0f
  }

  fun setResizeMode(mode: String) {
    val resizeMode = when (mode) {
      ResizeMode.CONTAIN.jsName -> ResizeMode.CONTAIN
      ResizeMode.FIT_WIDTH.jsName -> ResizeMode.FIT_WIDTH
      else -> {
        onError("Unknown resizeMode '$mode'.")
        return
      }
    }
    mResizeMode = resizeMode
    mDirty = true
  }

  fun setSource(source: String) {
    mSource = source
    mDirty = true
  }

  private fun computeDestRect(srcWidth: Int, srcHeight: Int): RectF {
    return when (mResizeMode) {
      ResizeMode.CONTAIN -> RectF(0f, 0f, width.toFloat(), height.toFloat())
      ResizeMode.FIT_WIDTH -> {
        val targetHeight = width.toFloat() * srcHeight.toFloat() / srcWidth.toFloat()
        RectF(0f, 0f, width.toFloat(), targetHeight)
      }
    }
  }

  /**
   * Calculate the actual PDF content rectangle after applying Matrix.ScaleToFit.CENTER.
   * This is where the PDF is actually rendered on screen.
   */
  private fun calculatePdfContentRect(srcWidth: Int, srcHeight: Int): RectF {
    val destRect = computeDestRect(srcWidth, srcHeight)

    // Apply Matrix.ScaleToFit.CENTER logic
    val srcAspect = srcWidth.toFloat() / srcHeight.toFloat()
    val destAspect = destRect.width() / destRect.height()

    val contentWidth: Float
    val contentHeight: Float

    if (srcAspect > destAspect) {
      // Source is wider - fit to width
      contentWidth = destRect.width()
      contentHeight = contentWidth / srcAspect
    } else {
      // Source is taller - fit to height
      contentHeight = destRect.height()
      contentWidth = contentHeight * srcAspect
    }

    // Center within destRect
    val left = destRect.left + (destRect.width() - contentWidth) / 2
    val top = destRect.top + (destRect.height() - contentHeight) / 2

    return RectF(left, top, left + contentWidth, top + contentHeight)
  }

  private fun parseColor(hex: String): Int {
    var androidColor = hex
    if (hex.length == 9) {
      androidColor = "#" + hex.takeLast(2) + hex.drop(1).take(6)
    }
    return try {
      Color.parseColor(androidColor)
    } catch (e: Exception) {
      Color.BLACK
    }
  }

  private fun parseColorWithOpacity(hex: String, opacity: Float): Int {
    val baseColor = parseColor(hex)
    val alpha = (opacity * 255).toInt().coerceIn(0, 255)
    return Color.argb(alpha, Color.red(baseColor), Color.green(baseColor), Color.blue(baseColor))
  }

  private fun computeDist(a: List<Float>, b: List<Float>, scaleX: Int, scaleY: Int): Float {
    return hypot(scaleX * (a[0] - b[0]), scaleY * (a[1] - b[1]))
  }

  private fun computePath(coordinates: List<List<Float>>, scaleX: Int, scaleY: Int): Path {
    return Path().apply {
      var prevPoint = coordinates.first()
      moveTo(prevPoint[0] * scaleX, prevPoint[1] * scaleY)
      for (point in coordinates.drop(1)) {
        if (computeDist(prevPoint, point, scaleX, scaleY) < 8) {
          continue
        }
        val midX = (prevPoint[0] + point[0]) / 2
        val midY = (prevPoint[1] + point[1]) / 2
        quadTo(
          prevPoint[0] * scaleX, prevPoint[1] * scaleY,
          midX * scaleX, midY * scaleY
        )
        prevPoint = point
      }
      prevPoint = coordinates.last()
      lineTo(prevPoint[0] * scaleX, prevPoint[1] * scaleY)
    }
  }

  private fun computePathFromPoints(points: List<PointF>, scaleX: Float, scaleY: Float): Path {
    return Path().apply {
      if (points.isEmpty()) return@apply

      var prevPoint = points.first()
      moveTo(prevPoint.x * scaleX, prevPoint.y * scaleY)

      for (point in points.drop(1)) {
        val dist = hypot((prevPoint.x - point.x) * scaleX, (prevPoint.y - point.y) * scaleY)
        if (dist < 8) {
          continue
        }
        val midX = (prevPoint.x + point.x) / 2
        val midY = (prevPoint.y + point.y) / 2
        quadTo(
          prevPoint.x * scaleX, prevPoint.y * scaleY,
          midX * scaleX, midY * scaleY
        )
        prevPoint = point
      }

      val lastPoint = points.last()
      lineTo(lastPoint.x * scaleX, lastPoint.y * scaleY)
    }
  }

  private fun renderAnnotation(bitmap: Bitmap) {
    if (mAnnotation.size <= mPage) {
      return
    }
    val metrics = resources.displayMetrics
    val ctx = Canvas(bitmap)
    val paint = Paint()

    paint.isAntiAlias = true
    paint.style = Paint.Style.STROKE
    paint.strokeCap = Paint.Cap.ROUND
    paint.strokeJoin = Paint.Join.ROUND
    for (stroke in mAnnotation[mPage].strokes) {
      if (stroke.path.size < 2) {
        continue
      }
      paint.color = parseColor(stroke.color)
      paint.strokeWidth = TypedValue.applyDimension(COMPLEX_UNIT_DIP, stroke.width, metrics)
      ctx.drawPath(computePath(stroke.path, bitmap.width, bitmap.height), paint)
    }

    paint.reset()
    paint.isAntiAlias = true
    paint.textAlign = Paint.Align.LEFT
    val bounds = Rect()
    val factor = TypedValue.applyDimension(COMPLEX_UNIT_DIP, 1000f, metrics)
    for (msg in mAnnotation[mPage].text) {
      paint.color = parseColor(msg.color)
      val scaledFont = 9 + (msg.fontSize * bitmap.width) / factor
      paint.textSize = TypedValue.applyDimension(COMPLEX_UNIT_DIP, scaledFont, metrics)
      paint.getTextBounds(msg.str, 0, msg.str.length, bounds)
      ctx.drawText(
        msg.str,
        bitmap.width * msg.point[0],
        bitmap.height * msg.point[1] - bounds.top,
        paint
      )
    }
  }

  fun renderPdf() {
    if (height < 1 || width < 1 || mSource.isEmpty() || !mDirty) {
      return
    }
    mDirty = false
    val currentGeneration = ++mRenderGeneration

    CoroutineScope(Dispatchers.Main).launch(Dispatchers.IO) {
      val file = File(mSource)
      val fd = try {
        ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
      } catch (e: FileNotFoundException) {
        onError("File '$mSource' not found.")
        return@launch
      }

      val pdfPageWidth: Int
      val pdfPageHeight: Int
      val bitmap = pdfMutex.withLock {
        val renderer = try {
          PdfRenderer(fd)
        } catch (e: Exception) {
          fd.close()
          onError("Failed to open '$mSource' for reading.")
          return@launch
        }
        val pdfPage = try {
          renderer.openPage(mPage)
        } catch (e: Exception) {
          renderer.close()
          fd.close()
          onError("Failed to open page '$mPage' of '$mSource' for reading.")
          return@launch
        }

        pdfPageWidth = pdfPage.width
        pdfPageHeight = pdfPage.height

        val rendered = try {
          Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        } catch (e: OutOfMemoryError) {
          pdfPage.close()
          renderer.close()
          fd.close()
          onError("Insufficient memory to render '$mSource' at ${width}x${height}.")
          return@launch
        }
        rendered.eraseColor(Color.WHITE)

        val transform = if (shouldTransformRender(pdfPageWidth, pdfPageHeight, rendered)) {
          val mtr = Matrix()
          mtr.setRectToRect(
            RectF(0f, 0f, pdfPageWidth.toFloat(), pdfPageHeight.toFloat()),
            computeDestRect(pdfPageWidth, pdfPageHeight),
            Matrix.ScaleToFit.CENTER
          )
          mtr
        } else {
          null
        }

        pdfPage.render(rendered, null, transform, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)

        pdfPage.close()
        renderer.close()

        return@withLock rendered
      }
      fd.close()

      renderAnnotation(bitmap)

      withContext(Dispatchers.Main) {
        // Skip if a newer render was started
        if (currentGeneration != mRenderGeneration) {
          bitmap.recycle()
          return@withContext
        }

        // Store PDF page dimensions and calculate content rect
        mPdfPageWidth = pdfPageWidth
        mPdfPageHeight = pdfPageHeight
        mPdfContentRect = calculatePdfContentRect(pdfPageWidth, pdfPageHeight)

        val sliceHeight = floor(bitmap.height.toFloat() / SLICES).toInt()
        if (sliceHeight < 1) {
          return@withContext
        }
        for (i in mBitmaps.indices) {
          mBitmaps[i].recycle()
          val remainingHeight = bitmap.height - i * sliceHeight
          if (remainingHeight < 2 * sliceHeight) {
            mBitmaps[i] =
              Bitmap.createBitmap(bitmap, 0, i * sliceHeight, bitmap.width, remainingHeight)
          } else {
            mBitmaps[i] = Bitmap.createBitmap(bitmap, 0, i * sliceHeight, bitmap.width, sliceHeight)
          }
        }
        invalidate()

        onLoadComplete(pdfPageWidth, pdfPageHeight)
      }
    }
  }

  private fun shouldTransformRender(sourceWidth: Int, sourceHeight: Int, bmp: Bitmap): Boolean {
    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
      return true
    }
    val aspectRatio = sourceWidth.toFloat() / sourceHeight.toFloat()
    val targetWidth = bmp.height * aspectRatio
    val delta = abs(bmp.width - targetWidth)
    return delta > 4
  }

  // --- Touch handling ---

  /**
   * Convert screen coordinates to normalized (0-1) coordinates relative to PDF content area.
   * Coordinates are normalized to the PDF content rect, not the view.
   */
  private fun screenToNormalized(screenX: Float, screenY: Float): PointF {
    // First, transform screen coordinates accounting for zoom
    val contentX = (screenX - mOffsetX) / mScale
    val contentY = (screenY - mOffsetY) / mScale

    // Then normalize relative to PDF content rect
    if (mPdfContentRect.isEmpty) {
      // Fallback if PDF not yet rendered
      return PointF(contentX / width, contentY / height)
    }

    val normalizedX = (contentX - mPdfContentRect.left) / mPdfContentRect.width()
    val normalizedY = (contentY - mPdfContentRect.top) / mPdfContentRect.height()
    return PointF(normalizedX, normalizedY)
  }

  @SuppressLint("ClickableViewAccessibility")
  override fun onTouchEvent(event: MotionEvent): Boolean {
    // Let gesture detectors handle the event first for zoom/pan
    if (mDrawingMode == DrawingMode.VIEW) {
      when (event.actionMasked) {
        MotionEvent.ACTION_DOWN -> {
          // At scale > 1, we need to handle pan, so block parent
          if (mScale > 1f) {
            parent?.requestDisallowInterceptTouchEvent(true)
          }
          // At scale = 1, don't block yet - let parent handle horizontal swipes
        }
        MotionEvent.ACTION_POINTER_DOWN -> {
          // Second finger down - this is a pinch gesture, block parent
          parent?.requestDisallowInterceptTouchEvent(true)
        }
        MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
          parent?.requestDisallowInterceptTouchEvent(false)
        }
      }

      // Pass events to gesture detectors
      if (mZoomEnabled) {
        mScaleDetector.onTouchEvent(event)
      }
      mGestureDetector.onTouchEvent(event)

      // Always consume events to maintain event stream for gesture detection
      return true
    }

    // Drawing mode - handle drawing gestures
    val normalized = screenToNormalized(event.x, event.y)

    when (event.action) {
      MotionEvent.ACTION_DOWN -> {
        parent?.requestDisallowInterceptTouchEvent(true)
        handleTouchStart(normalized.x, normalized.y)
        return true
      }
      MotionEvent.ACTION_MOVE -> {
        handleTouchMove(normalized.x, normalized.y)
        return true
      }
      MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
        parent?.requestDisallowInterceptTouchEvent(false)
        handleTouchEnd()
        return true
      }
    }
    return super.onTouchEvent(event)
  }

  private fun handleTouchStart(x: Float, y: Float) {
    when (mDrawingMode) {
      DrawingMode.DRAW, DrawingMode.HIGHLIGHT -> {
        val color = mStrokeColor
        val strokeWidth = if (mDrawingMode == DrawingMode.HIGHLIGHT) 20f else mStrokeWidth
        val opacity = if (mDrawingMode == DrawingMode.HIGHLIGHT) 0.3f else mStrokeOpacity

        mActiveStroke = DrawingStroke(
          id = UUID.randomUUID().toString(),
          color = color,
          width = strokeWidth,
          opacity = opacity,
          path = mutableListOf(PointF(x, y))
        )

        onDrawingStart()
        invalidate()
      }
      DrawingMode.ERASE -> {
        eraseStrokesAt(x, y)
      }
      else -> {}
    }
  }

  private fun handleTouchMove(x: Float, y: Float) {
    when (mDrawingMode) {
      DrawingMode.DRAW, DrawingMode.HIGHLIGHT -> {
        mActiveStroke?.let { stroke ->
          stroke.path.add(PointF(x, y))
          invalidate()
        }
      }
      DrawingMode.ERASE -> {
        eraseStrokesAt(x, y)
      }
      else -> {}
    }
  }

  private fun handleTouchEnd() {
    when (mDrawingMode) {
      DrawingMode.DRAW, DrawingMode.HIGHLIGHT -> {
        mActiveStroke?.let { stroke ->
          if (stroke.path.size >= 2) {
            mStrokes.add(stroke)
            onStrokeEnd(stroke)
          }
          mActiveStroke = null
          invalidate()
        }
        onDrawingEnd()
      }
      DrawingMode.ERASE -> {
        onDrawingEnd()
      }
      else -> {}
    }
  }

  private fun eraseStrokesAt(x: Float, y: Float) {
    val threshold = eraseThresholdPercent / mScale // Adjust threshold for zoom
    val toRemove = mutableListOf<DrawingStroke>()

    for (stroke in mStrokes) {
      for (point in stroke.path) {
        val dist = hypot(point.x - x, point.y - y)
        if (dist < threshold) {
          toRemove.add(stroke)
          break
        }
      }
    }

    if (toRemove.isNotEmpty()) {
      for (stroke in toRemove) {
        mStrokes.remove(stroke)
        onStrokeRemoved(stroke)
      }
      invalidate()
    }
  }

  // --- Drawing ---

  /**
   * Compute a Path from normalized points (0-1) relative to PDF content area.
   */
  private fun computePathFromNormalizedPoints(points: List<PointF>, contentRect: RectF): Path {
    return Path().apply {
      if (points.isEmpty() || contentRect.isEmpty) return@apply

      var prevPoint = points.first()
      var prevX = contentRect.left + prevPoint.x * contentRect.width()
      var prevY = contentRect.top + prevPoint.y * contentRect.height()
      moveTo(prevX, prevY)

      for (point in points.drop(1)) {
        val x = contentRect.left + point.x * contentRect.width()
        val y = contentRect.top + point.y * contentRect.height()
        val dist = hypot(prevX - x, prevY - y)
        if (dist < 8) {
          continue
        }
        val midX = (prevX + x) / 2
        val midY = (prevY + y) / 2
        quadTo(prevX, prevY, midX, midY)
        prevX = x
        prevY = y
      }

      val lastPoint = points.last()
      val lastX = contentRect.left + lastPoint.x * contentRect.width()
      val lastY = contentRect.top + lastPoint.y * contentRect.height()
      lineTo(lastX, lastY)
    }
  }

  override fun onDraw(canvas: Canvas) {
    canvas.save()

    // Apply zoom transformation
    canvas.translate(mOffsetX, mOffsetY)
    canvas.scale(mScale, mScale)

    // Draw PDF bitmap slices
    mBitmaps.zip(mViewRects) { bitmap, viewRect ->
      if (!viewRect.isEmpty) {
        canvas.drawBitmap(bitmap, null, viewRect, null)
      }
    }

    val metrics = resources.displayMetrics

    // Draw completed strokes relative to PDF content area
    for (stroke in mStrokes) {
      if (stroke.path.size < 2) continue

      mStrokePaint.color = parseColorWithOpacity(stroke.color, stroke.opacity)
      mStrokePaint.strokeWidth = TypedValue.applyDimension(COMPLEX_UNIT_DIP, stroke.width, metrics)

      val path = computePathFromNormalizedPoints(stroke.path, mPdfContentRect)
      canvas.drawPath(path, mStrokePaint)
    }

    // Draw active stroke
    mActiveStroke?.let { stroke ->
      if (stroke.path.size >= 2) {
        mStrokePaint.color = parseColorWithOpacity(stroke.color, stroke.opacity)
        mStrokePaint.strokeWidth = TypedValue.applyDimension(COMPLEX_UNIT_DIP, stroke.width, metrics)

        val path = computePathFromNormalizedPoints(stroke.path, mPdfContentRect)
        canvas.drawPath(path, mStrokePaint)
      }
    }

    canvas.restore()
  }

  override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
    val sliceHeight = floor(h.toFloat() / SLICES).toInt()
    if (sliceHeight < 1) {
      return
    }
    for (i in mViewRects.indices) {
      val remainingHeight = h - i * sliceHeight
      if (remainingHeight < 2 * sliceHeight) {
        mViewRects[i].set(0, i * sliceHeight, w, i * sliceHeight + remainingHeight)
      } else {
        mViewRects[i].set(0, i * sliceHeight, w, (i + 1) * sliceHeight)
      }
    }
    mDirty = true
    // Use post() to allow props to be set first, then render
    // Generation counter handles cancellation of outdated renders
    post { renderPdf() }
  }

  // --- React Native events ---

  private fun onError(message: String) {
    val event = Arguments.createMap()
    event.putString("message", message)
    val reactContext = context as ReactContext
    reactContext.getJSModule(RCTEventEmitter::class.java).receiveEvent(
      id, "onPdfError", event
    )
  }

  private fun onLoadComplete(pageWidth: Int, pageHeight: Int) {
    val event = Arguments.createMap()
    event.putInt("width", pageWidth)
    event.putInt("height", pageHeight)
    val reactContext = context as ReactContext
    reactContext.getJSModule(RCTEventEmitter::class.java).receiveEvent(
      id, "onPdfLoadComplete", event
    )
  }

  private fun onDrawingStart() {
    val event = Arguments.createMap()
    val reactContext = context as ReactContext
    reactContext.getJSModule(RCTEventEmitter::class.java).receiveEvent(
      id, "onDrawingStart", event
    )
  }

  private fun onDrawingEnd() {
    val event = Arguments.createMap()
    val reactContext = context as ReactContext
    reactContext.getJSModule(RCTEventEmitter::class.java).receiveEvent(
      id, "onDrawingEnd", event
    )
  }

  private fun onZoomChange() {
    val event = Arguments.createMap()
    event.putDouble("scale", mScale.toDouble())
    event.putDouble("offsetX", mOffsetX.toDouble())
    event.putDouble("offsetY", mOffsetY.toDouble())
    val reactContext = context as ReactContext
    reactContext.getJSModule(RCTEventEmitter::class.java).receiveEvent(
      id, "onZoomChange", event
    )
  }

  private fun onSingleTap() {
    val event = Arguments.createMap()
    val reactContext = context as ReactContext
    reactContext.getJSModule(RCTEventEmitter::class.java).receiveEvent(
      id, "onSingleTap", event
    )
  }

  private fun strokeToWritableMap(stroke: DrawingStroke): WritableMap {
    val map = Arguments.createMap()
    map.putString("id", stroke.id)
    map.putString("color", stroke.color)
    map.putDouble("width", stroke.width.toDouble())
    map.putDouble("opacity", stroke.opacity.toDouble())

    val pathArray = Arguments.createArray()
    for (point in stroke.path) {
      val pointArray = Arguments.createArray()
      pointArray.pushDouble(point.x.toDouble())
      pointArray.pushDouble(point.y.toDouble())
      pathArray.pushArray(pointArray)
    }
    map.putArray("path", pathArray)

    return map
  }

  private fun onStrokeEnd(stroke: DrawingStroke) {
    val event = strokeToWritableMap(stroke)
    val reactContext = context as ReactContext
    reactContext.getJSModule(RCTEventEmitter::class.java).receiveEvent(
      id, "onStrokeEnd", event
    )
  }

  private fun onStrokeRemoved(stroke: DrawingStroke) {
    val event = Arguments.createMap()
    event.putString("id", stroke.id)
    val reactContext = context as ReactContext
    reactContext.getJSModule(RCTEventEmitter::class.java).receiveEvent(
      id, "onStrokeRemoved", event
    )
  }

  /**
   * Clear all strokes from this page.
   */
  fun clearStrokes() {
    mStrokes.clear()
    invalidate()
    onStrokesCleared()
  }

  private fun onStrokesCleared() {
    val event = Arguments.createMap()
    val reactContext = context as ReactContext
    reactContext.getJSModule(RCTEventEmitter::class.java).receiveEvent(
      id, "onStrokesCleared", event
    )
  }

  /**
   * Reset zoom to default.
   */
  fun resetZoom() {
    mScale = mMinScale
    mOffsetX = 0f
    mOffsetY = 0f
    invalidate()
    onZoomChange()
  }

  /**
   * Get all strokes as JSON string for serialization.
   */
  fun getStrokesJson(): String {
    val strokeDataList = mStrokes.map { stroke ->
      StrokeData(
        id = stroke.id,
        color = stroke.color,
        width = stroke.width,
        opacity = stroke.opacity,
        path = stroke.path.map { listOf(it.x, it.y) }
      )
    }
    return Json.encodeToString(strokeDataList)
  }
}

/**
 * Data class for JSON serialization of strokes.
 */
@kotlinx.serialization.Serializable
data class StrokeData(
  val id: String,
  val color: String,
  val width: Float,
  val opacity: Float,
  val path: List<List<Float>>
)