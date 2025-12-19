package com.alpha0010.pdf

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.*
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import android.util.LruCache
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.ViewGroup
import android.view.animation.DecelerateInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.ReactContext
import com.facebook.react.uimanager.PixelUtil
import com.facebook.react.uimanager.events.RCTEventEmitter
import kotlinx.coroutines.*
import java.io.File
import java.io.FileNotFoundException
import java.util.concurrent.locks.Lock
import kotlin.concurrent.withLock

/**
 * Zoomable scrollable PDF viewer using RecyclerView for virtualization.
 */
@SuppressLint("ViewConstructor")
class ZoomablePdfScrollView(context: Context, private val pdfMutex: Lock) : FrameLayout(context) {

    // Props
    private var mSource = ""
    private var mMinScale = 1f
    private var mMaxScale = 3f
    private var mEdgeTapZone = 15f
    private var mPaddingTop = 0
    private var mPaddingBottom = 0
    private var mBackgroundColor = Color.DKGRAY

    // PDF state
    private var mPdfRenderer: PdfRenderer? = null
    private var mFileDescriptor: ParcelFileDescriptor? = null
    private var mPdfPageWidth = 0
    private var mPdfPageHeight = 0
    private var mActualPageCount = 0

    // Zoom state
    private var mScale = 1f
    private var mOffsetX = 0f
    private var mOffsetY = 0f

    // Views
    private val mRecyclerView: RecyclerView
    private val mAdapter: PdfPageAdapter

    // Image cache (LruCache with max 10MB or 10 pages)
    private val mImageCache: LruCache<Int, Bitmap>

    // Gesture detectors
    private val mScaleDetector: ScaleGestureDetector
    private val mGestureDetector: GestureDetector
    private val mPanGestureDetector: GestureDetector

    // Current page tracking
    private var mCurrentPage = 0

    // Track width for rotation handling
    private var mPreviousWidth = 0

    // Coroutine scope for rendering
    private val renderScope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    // Zoom animation
    private var zoomAnimator: ValueAnimator? = null

    init {
        // Initialize cache (10MB max)
        val maxMemory = (Runtime.getRuntime().maxMemory() / 1024).toInt()
        val cacheSize = maxMemory / 8 // Use 1/8th of available memory
        mImageCache = object : LruCache<Int, Bitmap>(cacheSize) {
            override fun sizeOf(key: Int, bitmap: Bitmap): Int {
                return bitmap.byteCount / 1024
            }
        }

        // Setup RecyclerView
        mRecyclerView = RecyclerView(context).apply {
            layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT)
            layoutManager = LinearLayoutManager(context, LinearLayoutManager.VERTICAL, false)
            setHasFixedSize(true)
        }

        mAdapter = PdfPageAdapter()
        mRecyclerView.adapter = mAdapter

        addView(mRecyclerView)

        // Setup scale gesture detector
        mScaleDetector = ScaleGestureDetector(context, object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
            private var focusX = 0f
            private var focusY = 0f

            override fun onScaleBegin(detector: ScaleGestureDetector): Boolean {
                zoomAnimator?.cancel() // Cancel any running animation
                focusX = detector.focusX
                focusY = detector.focusY
                return true
            }

            override fun onScale(detector: ScaleGestureDetector): Boolean {
                val scaleFactor = detector.scaleFactor
                val newScale = (mScale * scaleFactor).coerceIn(mMinScale, mMaxScale)

                if (newScale != mScale) {
                    // Calculate new offsets to zoom toward focus point
                    val focusRatioX = (focusX - mOffsetX) / (width * mScale)
                    val focusRatioY = (focusY - mOffsetY) / (height * mScale)

                    mScale = newScale

                    mOffsetX = focusX - focusRatioX * width * mScale
                    mOffsetY = focusY - focusRatioY * height * mScale

                    constrainOffset()
                    applyTransform()
                    onZoomChange()
                }
                return true
            }
        })

        // Setup gesture detector for double-tap and single tap
        mGestureDetector = GestureDetector(context, object : GestureDetector.SimpleOnGestureListener() {
            override fun onSingleTapConfirmed(e: MotionEvent): Boolean {
                handleSingleTap(e)
                return true
            }

            override fun onDoubleTap(e: MotionEvent): Boolean {
                // Only handle double tap in middle zone
                val tapX = e.x
                val tapY = e.y
                val edgeRatio = mEdgeTapZone / 100f
                val leftEdge = width * edgeRatio
                val rightEdge = width * (1f - edgeRatio)

                if (tapX < leftEdge || tapX > rightEdge) {
                    return false
                }

                if (mScale > mMinScale) {
                    // Reset zoom with animation
                    animateZoomTo(mMinScale, 0f, 0)
                } else {
                    // Zoom to maxZoom at tap location with animation
                    val targetScale = mMaxScale

                    // Calculate content point under tap (horizontal)
                    val contentX = (tapX - mOffsetX) / mScale

                    // Calculate new horizontal offset to keep tap point stationary
                    var targetOffsetX = tapX - contentX * targetScale

                    // Constrain target offset
                    val scaledWidth = width * targetScale
                    val minOffsetX = width - scaledWidth
                    targetOffsetX = targetOffsetX.coerceIn(minOffsetX.coerceAtMost(0f), 0f)

                    // Calculate vertical scroll adjustment
                    // tapY is screen coordinate, need to convert to content coordinate
                    val currentScrollY = mRecyclerView.computeVerticalScrollOffset()
                    val contentY = tapY / mScale + currentScrollY

                    // Calculate target scroll to keep tap point at same screen position
                    // After zoom: screenY = (contentY - scrollY) * scale, we want screenY = tapY
                    // targetScrollY = contentY - tapY / targetScale
                    val targetScrollY = (contentY - tapY / targetScale).toInt().coerceAtLeast(0)
                    val scrollDelta = targetScrollY - currentScrollY

                    animateZoomTo(targetScale, targetOffsetX, scrollDelta)
                }

                return true
            }
        })

        // Setup pan gesture detector for horizontal panning when zoomed
        mPanGestureDetector = GestureDetector(context, object : GestureDetector.SimpleOnGestureListener() {
            override fun onScroll(e1: MotionEvent?, e2: MotionEvent, distanceX: Float, distanceY: Float): Boolean {
                if (mScale <= 1f) return false

                // Only handle horizontal pan, let RecyclerView handle vertical
                mOffsetX -= distanceX
                constrainOffset()
                applyTransform()
                return true
            }
        })

        // Scroll listener for page change tracking
        mRecyclerView.addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                updateCurrentPage()
            }
        })
    }

    private fun constrainOffset() {
        if (mScale <= 1f) {
            mOffsetX = 0f
            return
        }

        val scaledWidth = width * mScale
        val maxOffsetX = 0f
        val minOffsetX = width - scaledWidth

        mOffsetX = mOffsetX.coerceIn(minOffsetX.coerceAtMost(0f), maxOffsetX)
    }

    private fun applyTransform() {
        mRecyclerView.translationX = mOffsetX
        mRecyclerView.scaleX = mScale
        mRecyclerView.scaleY = mScale
        mRecyclerView.pivotX = 0f
        mRecyclerView.pivotY = 0f
        // Update padding to allow scrolling to see all zoomed content
        updateRecyclerViewPadding()
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onInterceptTouchEvent(ev: MotionEvent): Boolean {
        // Always intercept to handle taps and gestures
        return true
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(event: MotionEvent): Boolean {
        // Always process scale gestures
        mScaleDetector.onTouchEvent(event)

        // Process taps and double-taps (this handles single tap for landscape scroll)
        mGestureDetector.onTouchEvent(event)

        // Handle pan when zoomed
        if (mScale > 1f) {
            mPanGestureDetector.onTouchEvent(event)
        }

        // Forward scroll events to RecyclerView
        if (event.pointerCount == 1 && !mScaleDetector.isInProgress) {
            mRecyclerView.onTouchEvent(event)
        }

        return true
    }

    // --- Setters ---

    fun setSource(source: String) {
        if (mSource != source) {
            mSource = source
            reloadPdf()
        }
    }

    fun setMinZoom(minZoom: Float) {
        mMinScale = minZoom.coerceAtLeast(0.5f)
        if (mScale < mMinScale) {
            mScale = mMinScale
            constrainOffset()
            applyTransform()
        }
    }

    fun setMaxZoom(maxZoom: Float) {
        mMaxScale = maxZoom.coerceAtLeast(1f)
        if (mScale > mMaxScale) {
            mScale = mMaxScale
            constrainOffset()
            applyTransform()
        }
    }

    fun setEdgeTapZone(zone: Float) {
        mEdgeTapZone = zone.coerceIn(0f, 50f)
    }

    fun setPdfBackgroundColor(color: Int) {
        mBackgroundColor = color
        setBackgroundColor(color)
    }

    fun setPdfPaddingTop(padding: Float) {
        mPaddingTop = PixelUtil.toPixelFromDIP(padding).toInt().coerceAtLeast(0)
        updateRecyclerViewPadding()
    }

    fun setPdfPaddingBottom(padding: Float) {
        mPaddingBottom = PixelUtil.toPixelFromDIP(padding).toInt().coerceAtLeast(0)
        updateRecyclerViewPadding()
    }

    private fun updateRecyclerViewPadding() {
        // When zoomed, we need extra padding to allow scrolling to see all content
        // Use different multipliers: smaller for top, larger for bottom
        val zoomExtraTop = if (mScale > 1.01f && height > 0) {
            (height * (mScale - 1) * 0.05f).toInt()
        } else 0
        val zoomExtraBottom = if (mScale > 1.01f && height > 0) {
            (height * (mScale - 1) * 0.25f).toInt()
        } else 0

        val newTopPadding = mPaddingTop + zoomExtraTop
        val newBottomPadding = mPaddingBottom + zoomExtraBottom

        // Only update if padding actually changed
        if (mRecyclerView.paddingTop != newTopPadding || mRecyclerView.paddingBottom != newBottomPadding) {
            mRecyclerView.setPadding(0, newTopPadding, 0, newBottomPadding)
            mRecyclerView.clipToPadding = false
            // Force layout update
            mRecyclerView.requestLayout()
        }
    }

    private fun reloadPdf() {
        if (mSource.isEmpty()) return

        // Close previous renderer
        closePdf()

        // Clear cache
        mImageCache.evictAll()

        // Open PDF
        val file = File(mSource)
        try {
            mFileDescriptor = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
            mPdfRenderer = PdfRenderer(mFileDescriptor!!)

            // Get dimensions from first page
            mPdfRenderer?.let { renderer ->
                if (renderer.pageCount > 0) {
                    val page = renderer.openPage(0)
                    mPdfPageWidth = page.width
                    mPdfPageHeight = page.height
                    page.close()
                }

                mActualPageCount = renderer.pageCount
            }

            mAdapter.notifyDataSetChanged()

            // Notify load complete
            onLoadComplete()

        } catch (e: FileNotFoundException) {
            onError("File '$mSource' not found.")
        } catch (e: Exception) {
            onError("Failed to open PDF: ${e.message}")
        }
    }

    private fun closePdf() {
        mPdfRenderer?.close()
        mPdfRenderer = null
        mFileDescriptor?.close()
        mFileDescriptor = null
    }

    private fun updateCurrentPage() {
        val layoutManager = mRecyclerView.layoutManager as? LinearLayoutManager ?: return
        val firstVisible = layoutManager.findFirstVisibleItemPosition()
        val lastVisible = layoutManager.findLastVisibleItemPosition()

        if (firstVisible == RecyclerView.NO_POSITION) return

        // Use the page that's most visible
        val centerPosition = (firstVisible + lastVisible) / 2
        val newPage = centerPosition.coerceIn(0, mActualPageCount - 1)

        if (newPage != mCurrentPage) {
            mCurrentPage = newPage
            onPageChange()
        }
    }

    private fun getPageHeight(): Int {
        if (mPdfPageWidth <= 0 || mPdfPageHeight <= 0) return height
        return (width.toFloat() * mPdfPageHeight / mPdfPageWidth).toInt()
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)

        // Handle rotation - clear cache and re-render when width changes
        if (w != mPreviousWidth && mPreviousWidth > 0 && mActualPageCount > 0) {
            // Clear cache since bitmaps have old dimensions
            mImageCache.evictAll()

            // Reset zoom
            mScale = mMinScale
            mOffsetX = 0f
            mOffsetY = 0f
            applyTransform()

            // Force re-bind all visible items
            mAdapter.notifyDataSetChanged()
        }
        mPreviousWidth = w
    }

    // --- Zoom animation ---

    private fun animateZoomTo(targetScale: Float, targetOffsetX: Float, scrollDelta: Int = 0, duration: Long = 300L) {
        zoomAnimator?.cancel()

        val startScale = mScale
        val startOffsetX = mOffsetX
        var accumulatedScroll = 0

        zoomAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            this.duration = duration
            interpolator = DecelerateInterpolator()
            addUpdateListener { animator ->
                val fraction = animator.animatedValue as Float
                mScale = startScale + (targetScale - startScale) * fraction
                mOffsetX = startOffsetX + (targetOffsetX - startOffsetX) * fraction

                // Animate scroll
                if (scrollDelta != 0) {
                    val targetScrollSoFar = (scrollDelta * fraction).toInt()
                    val scrollThisFrame = targetScrollSoFar - accumulatedScroll
                    if (scrollThisFrame != 0) {
                        mRecyclerView.scrollBy(0, scrollThisFrame)
                        accumulatedScroll = targetScrollSoFar
                    }
                }

                applyTransform()
                onZoomChange()
            }
            start()
        }
    }

    // --- Public commands ---

    fun resetZoom() {
        animateZoomTo(mMinScale, 0f)
    }

    fun scrollToPage(page: Int, animated: Boolean) {
        if (page < 0 || page >= mActualPageCount) return

        val layoutManager = mRecyclerView.layoutManager as? LinearLayoutManager ?: return
        if (animated) {
            mRecyclerView.smoothScrollToPosition(page)
        } else {
            layoutManager.scrollToPositionWithOffset(page, 0)
        }
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

    private fun onLoadComplete() {
        val event = Arguments.createMap()
        event.putInt("width", mPdfPageWidth)
        event.putInt("height", mPdfPageHeight)
        event.putInt("pageCount", mActualPageCount)
        val reactContext = context as ReactContext
        reactContext.getJSModule(RCTEventEmitter::class.java).receiveEvent(
            id, "onPdfLoadComplete", event
        )
    }

    private fun onPageChange() {
        val event = Arguments.createMap()
        event.putInt("page", mCurrentPage)
        val reactContext = context as ReactContext
        reactContext.getJSModule(RCTEventEmitter::class.java).receiveEvent(
            id, "onPageChange", event
        )
    }

    private fun onZoomChange() {
        val event = Arguments.createMap()
        event.putDouble("scale", mScale.toDouble())
        val reactContext = context as ReactContext
        reactContext.getJSModule(RCTEventEmitter::class.java).receiveEvent(
            id, "onZoomChange", event
        )
    }

    private fun onTap(position: String) {
        val event = Arguments.createMap()
        event.putString("position", position)
        val reactContext = context as ReactContext
        reactContext.getJSModule(RCTEventEmitter::class.java).receiveEvent(
            id, "onTap", event
        )
    }

    private fun onMiddleClick() {
        val event = Arguments.createMap()
        val reactContext = context as ReactContext
        reactContext.getJSModule(RCTEventEmitter::class.java).receiveEvent(
            id, "onMiddleClick", event
        )
    }

    // MARK: - Single tap handling

    private fun handleSingleTap(e: MotionEvent) {
        val tapX = e.x
        val edgeRatio = mEdgeTapZone / 100f
        val leftEdge = width * edgeRatio
        val rightEdge = width * (1f - edgeRatio)

        val viewportHeight = height
        val layoutManager = mRecyclerView.layoutManager as? LinearLayoutManager ?: return

        // Get actual padding (includes zoom extra padding)
        val actualTopPadding = mRecyclerView.paddingTop
        val actualBottomPadding = mRecyclerView.paddingBottom

        // Check device orientation: portrait (height > width) or landscape (width >= height)
        val isPortraitMode = height > width

        when {
            tapX < leftEdge -> {
                if (isPortraitMode) {
                    // Portrait mode: scroll to center previous page
                    scrollToCenteredPage(getCurrentCenteredPage() - 1)
                } else {
                    // Landscape mode: scroll up by one viewport
                    val firstVisible = layoutManager.findFirstVisibleItemPosition()
                    val firstView = layoutManager.findViewByPosition(firstVisible)

                    if (firstVisible == 0 && firstView != null) {
                        val currentTop = firstView.top
                        if (currentTop >= actualTopPadding) {
                            // Already showing full top padding, nothing to do
                        } else {
                            val scrollAmount = currentTop - actualTopPadding
                            mRecyclerView.smoothScrollBy(0, scrollAmount)
                        }
                    } else {
                        mRecyclerView.smoothScrollBy(0, -viewportHeight)
                    }
                }
                onTap("left")
            }
            tapX > rightEdge -> {
                if (isPortraitMode) {
                    // Portrait mode: scroll to center next page
                    scrollToCenteredPage(getCurrentCenteredPage() + 1)
                } else {
                    // Landscape mode: scroll down by one viewport
                    val lastVisible = layoutManager.findLastVisibleItemPosition()
                    val lastView = layoutManager.findViewByPosition(lastVisible)

                    if (lastVisible == mActualPageCount - 1 && lastView != null) {
                        val currentBottom = lastView.bottom
                        val targetBottom = viewportHeight - actualBottomPadding
                        if (currentBottom <= targetBottom) {
                            // Already showing full bottom padding, nothing to do
                        } else {
                            val scrollAmount = currentBottom - targetBottom
                            mRecyclerView.smoothScrollBy(0, scrollAmount)
                        }
                    } else {
                        mRecyclerView.smoothScrollBy(0, viewportHeight)
                    }
                }
                onTap("right")
            }
            else -> {
                // Middle zone - call onMiddleClick
                onMiddleClick()
            }
        }
    }

    private fun getCurrentCenteredPage(): Int {
        val layoutManager = mRecyclerView.layoutManager as? LinearLayoutManager ?: return 0
        val pageHeight = getPageHeight()
        if (pageHeight <= 0) return 0

        // Calculate which page is centered in the viewport
        val viewportCenterY = mRecyclerView.computeVerticalScrollOffset() + height / 2
        return (viewportCenterY / pageHeight).coerceIn(0, mActualPageCount - 1)
    }

    private fun scrollToCenteredPage(targetPage: Int) {
        val page = targetPage.coerceIn(0, mActualPageCount - 1)
        val pageHeight = getPageHeight()
        if (pageHeight <= 0) return

        // Calculate offset to center the target page in viewport
        val pageCenterY = page * pageHeight + pageHeight / 2
        val targetOffset = pageCenterY - height / 2

        // Clamp to valid scroll range
        val maxScroll = mActualPageCount * pageHeight - height + mRecyclerView.paddingTop + mRecyclerView.paddingBottom
        val clampedOffset = targetOffset.coerceIn(-mRecyclerView.paddingTop, maxScroll.coerceAtLeast(0))

        mRecyclerView.smoothScrollBy(0, clampedOffset - mRecyclerView.computeVerticalScrollOffset())
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        zoomAnimator?.cancel()
        renderScope.cancel()
        closePdf()
        mImageCache.evictAll()
    }

    // --- Adapter ---

    private inner class PdfPageAdapter : RecyclerView.Adapter<PdfPageViewHolder>() {

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): PdfPageViewHolder {
            val imageView = ImageView(parent.context).apply {
                layoutParams = RecyclerView.LayoutParams(
                    RecyclerView.LayoutParams.MATCH_PARENT,
                    RecyclerView.LayoutParams.WRAP_CONTENT
                )
                scaleType = ImageView.ScaleType.FIT_XY
                setBackgroundColor(Color.WHITE)
            }
            return PdfPageViewHolder(imageView)
        }

        override fun onBindViewHolder(holder: PdfPageViewHolder, position: Int) {
            val pageHeight = getPageHeight()
            holder.imageView.layoutParams.height = pageHeight

            // Add spacing
            val params = holder.imageView.layoutParams as RecyclerView.LayoutParams
            params.bottomMargin = 0

            // Check cache
            val cached = mImageCache.get(position)
            if (cached != null) {
                holder.imageView.setImageBitmap(cached)
            } else {
                holder.imageView.setImageBitmap(null)
                renderPage(position, holder)
            }
        }

        override fun getItemCount(): Int = mActualPageCount

        private fun renderPage(pageIndex: Int, holder: PdfPageViewHolder) {
            val renderer = mPdfRenderer ?: return
            val viewWidth = width
            val pageHeight = getPageHeight()

            if (viewWidth <= 0 || pageHeight <= 0) return

            renderScope.launch(Dispatchers.IO) {
                val bitmap = pdfMutex.withLock {
                    try {
                        val page = renderer.openPage(pageIndex)
                        val bmp = Bitmap.createBitmap(viewWidth, pageHeight, Bitmap.Config.ARGB_8888)
                        bmp.eraseColor(Color.WHITE)

                        val matrix = Matrix()
                        matrix.setScale(
                            viewWidth.toFloat() / page.width,
                            pageHeight.toFloat() / page.height
                        )

                        page.render(bmp, null, matrix, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                        page.close()
                        bmp
                    } catch (e: Exception) {
                        null
                    }
                }

                bitmap?.let {
                    mImageCache.put(pageIndex, it)
                    withContext(Dispatchers.Main) {
                        // Only update if this holder is still bound to the same position
                        if (holder.bindingAdapterPosition == pageIndex) {
                            holder.imageView.setImageBitmap(it)
                        }
                    }
                }
            }
        }
    }

    private class PdfPageViewHolder(val imageView: ImageView) : RecyclerView.ViewHolder(imageView)
}
