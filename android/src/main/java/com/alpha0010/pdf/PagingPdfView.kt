package com.alpha0010.pdf

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.*
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import android.util.Log
import android.util.LruCache
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.View
import android.view.ViewGroup
import android.view.animation.DecelerateInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import androidx.viewpager2.widget.ViewPager2
import androidx.recyclerview.widget.RecyclerView
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.ReactContext
import com.facebook.react.uimanager.events.RCTEventEmitter
import kotlinx.coroutines.*
import java.io.File
import java.io.FileNotFoundException
import java.util.concurrent.locks.Lock
import kotlin.concurrent.withLock

/**
 * Paged PDF viewer using ViewPager2 with per-page zoom and vertical scroll.
 * Each page is rendered to fit width with vertical scrolling (like iOS).
 */
@SuppressLint("ViewConstructor")
class PagingPdfView(context: Context, private val pdfMutex: Lock) : FrameLayout(context) {

    // Props
    private var mSource = ""
    private var mMinScale = 1f
    private var mMaxScale = 3f
    private var mEdgeTapZone = 15f
    private var mBackgroundColor = Color.WHITE

    // PDF state
    private var mPdfRenderer: PdfRenderer? = null
    private var mFileDescriptor: ParcelFileDescriptor? = null
    private var mPdfPageWidth = 0
    private var mPdfPageHeight = 0
    private var mActualPageCount = 0

    // Views
    private val mViewPager: ViewPager2
    private val mAdapter: PdfPageAdapter

    // Image cache
    private val mImageCache: LruCache<Int, Bitmap>

    // Current page tracking
    private var mCurrentPage = 0
    private var mPreviousWidth = 0

    // Deferred loading flag
    private var mNeedsInitialRender = false
    private var mPendingSource: String? = null

    // Scroll to bottom on next page load (for landscape back navigation)
    private var mPendingScrollToBottom = false
    private var mPendingScrollToBottomPage = -1

    // Coroutine scope for rendering
    private val renderScope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    init {
        setBackgroundColor(mBackgroundColor)

        // Initialize cache
        val maxMemory = (Runtime.getRuntime().maxMemory() / 1024).toInt()
        val cacheSize = maxMemory / 8
        mImageCache = object : LruCache<Int, Bitmap>(cacheSize) {
            override fun sizeOf(key: Int, bitmap: Bitmap): Int {
                return bitmap.byteCount / 1024
            }
        }

        // Setup ViewPager2 for horizontal paging
        mViewPager = ViewPager2(context).apply {
            layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT)
            orientation = ViewPager2.ORIENTATION_HORIZONTAL
            setBackgroundColor(Color.TRANSPARENT)
        }

        mAdapter = PdfPageAdapter()
        mViewPager.adapter = mAdapter

        // Set background on internal RecyclerView after it's created
        mViewPager.post {
            (mViewPager.getChildAt(0) as? RecyclerView)?.setBackgroundColor(Color.TRANSPARENT)
        }

        // Track page changes
        mViewPager.registerOnPageChangeCallback(object : ViewPager2.OnPageChangeCallback() {
            override fun onPageSelected(position: Int) {
                if (position != mCurrentPage && position >= 0 && position < mActualPageCount) {
                    mCurrentPage = position
                    onPageChange()
                }
            }

            override fun onPageScrollStateChanged(state: Int) {
                Log.d("PagingPdfView", "onPageScrollStateChanged: state=$state, pending=$mPendingScrollToBottom, pendingPage=$mPendingScrollToBottomPage, currentPage=$mCurrentPage")
                // Wait for scroll to complete before scrolling to bottom
                if (state == ViewPager2.SCROLL_STATE_IDLE && mPendingScrollToBottom) {
                    val targetPage = mPendingScrollToBottomPage
                    Log.d("PagingPdfView", "SCROLL_STATE_IDLE with pending, targetPage=$targetPage, currentPage=$mCurrentPage")
                    if (targetPage == mCurrentPage) {
                        mPendingScrollToBottom = false
                        mPendingScrollToBottomPage = -1
                        Log.d("PagingPdfView", "Scheduling scrollToBottom for page $targetPage")
                        // Find the ViewHolder and scroll to bottom after a short delay
                        mViewPager.postDelayed({
                            val recyclerView = mViewPager.getChildAt(0) as? RecyclerView
                            val viewHolder = recyclerView?.findViewHolderForAdapterPosition(targetPage) as? PdfPageViewHolder
                            Log.d("PagingPdfView", "Found viewHolder: ${viewHolder != null}")
                            viewHolder?.pageView?.scrollToBottomWithFade()
                        }, 100)
                    }
                }
            }
        })

        addView(mViewPager)
    }

    // --- Setters ---

    fun setSource(source: String) {
        if (mSource != source) {
            mSource = source
            // Defer loading if we don't have valid dimensions yet
            if (width > 0 && height > 0) {
                reloadPdf()
            } else {
                mNeedsInitialRender = true
            }
        }
    }

    fun setMinZoom(minZoom: Float) {
        mMinScale = minZoom.coerceAtLeast(0.5f)
    }

    fun setMaxZoom(maxZoom: Float) {
        mMaxScale = maxZoom.coerceAtLeast(1f)
    }

    fun setEdgeTapZone(zone: Float) {
        mEdgeTapZone = zone.coerceIn(0f, 50f)
    }

    fun setPdfBackgroundColor(color: Int) {
        mBackgroundColor = color
        applyBackgroundColor()
    }

    private fun applyBackgroundColor() {
        // Set on root container - ViewPager2 and RecyclerView are transparent
        setBackgroundColor(mBackgroundColor)
        // Also update all existing page views
        mAdapter.notifyDataSetChanged()
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

            // Required so ViewPager actually displays first dynamically added child
            // (otherwise a white screen is shown until the next user interaction).
            // https://github.com/facebook/react-native/issues/17968#issuecomment-697136929
            refreshViewChildrenLayout(mViewPager)

            // Notify load complete
            onLoadComplete()

        } catch (e: FileNotFoundException) {
            onError("File '$mSource' not found.")
        } catch (e: Exception) {
            onError("Failed to open PDF: ${e.message}")
        }
    }

    private fun closePdf() {
        pdfMutex.withLock {
            try {
                mPdfRenderer?.close()
            } catch (e: Exception) {
                // Ignore errors during cleanup (e.g., page still open from cancelled render)
            }
            mPdfRenderer = null
        }
        try {
            mFileDescriptor?.close()
        } catch (e: Exception) {
            // Ignore errors during cleanup
        }
        mFileDescriptor = null
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)

        if (w <= 0 || h <= 0) return

        // Handle deferred initial render
        if (mNeedsInitialRender && mSource.isNotEmpty()) {
            mNeedsInitialRender = false
            reloadPdf()
            mPreviousWidth = w
            return
        }

        // Handle orientation change
        if (w != mPreviousWidth && mPreviousWidth > 0 && mActualPageCount > 0) {
            val savedPage = mCurrentPage
            mImageCache.evictAll()
            mAdapter.notifyDataSetChanged()
            // Restore current page after orientation change
            post {
                if (savedPage >= 0 && savedPage < mActualPageCount) {
                    mViewPager.setCurrentItem(savedPage, false)
                }
            }
        }
        mPreviousWidth = w
    }

    // --- Public commands ---

    fun resetZoom() {
        // Reset zoom on current page
        val recyclerView = mViewPager.getChildAt(0) as? RecyclerView ?: return
        val viewHolder = recyclerView.findViewHolderForAdapterPosition(mCurrentPage) as? PdfPageViewHolder
        viewHolder?.resetZoom()
        onZoomChange()
    }

    fun scrollToPage(page: Int, animated: Boolean) {
        if (page < 0 || page >= mActualPageCount) return
        mViewPager.setCurrentItem(page, animated)
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
        event.putDouble("scale", 1.0) // Report current scale
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

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        renderScope.cancel()
        closePdf()
        mImageCache.evictAll()
    }

    /**
     * Force layout refresh - required so ViewPager2 actually displays content
     * (otherwise a white screen is shown until the next user interaction).
     * https://github.com/facebook/react-native/issues/17968#issuecomment-697136929
     */
    private fun refreshViewChildrenLayout(view: View) {
        view.post {
            view.measure(
                View.MeasureSpec.makeMeasureSpec(view.width, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(view.height, View.MeasureSpec.EXACTLY)
            )
            view.layout(view.left, view.top, view.right, view.bottom)
        }
    }

    // --- Adapter ---

    private inner class PdfPageAdapter : RecyclerView.Adapter<PdfPageViewHolder>() {

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): PdfPageViewHolder {
            val pageView = ZoomablePageView(parent.context)
            pageView.layoutParams = RecyclerView.LayoutParams(
                RecyclerView.LayoutParams.MATCH_PARENT,
                RecyclerView.LayoutParams.MATCH_PARENT
            )
            pageView.setPageBackgroundColor(mBackgroundColor)
            pageView.onZoomChange = { scale ->
                val event = Arguments.createMap()
                event.putDouble("scale", scale.toDouble())
                val reactContext = context as ReactContext
                reactContext.getJSModule(RCTEventEmitter::class.java).receiveEvent(
                    id, "onZoomChange", event
                )
            }
            pageView.onTap = { position ->
                onTap(position)
            }
            pageView.onMiddleClick = {
                onMiddleClick()
            }
            pageView.onZoomStateChange = { isZoomed ->
                // Disable ViewPager2 swipe when zoomed
                mViewPager.isUserInputEnabled = !isZoomed
            }
            return PdfPageViewHolder(pageView)
        }

        override fun onBindViewHolder(holder: PdfPageViewHolder, position: Int) {
            val viewWidth = this@PagingPdfView.width

            if (viewWidth <= 0 || mPdfPageWidth <= 0 || mPdfPageHeight <= 0) return

            // Reset state for recycled views
            holder.pageView.resetState()

            holder.pageView.minZoom = mMinScale
            holder.pageView.maxZoom = mMaxScale
            holder.pageView.edgeTapZone = mEdgeTapZone
            holder.pageView.onPreviousPage = { scrollToBottom ->
                Log.d("PagingPdfView", "onPreviousPage called, scrollToBottom=$scrollToBottom, position=$position")
                if (position > 0) {
                    if (scrollToBottom) {
                        mPendingScrollToBottom = true
                        mPendingScrollToBottomPage = position - 1
                        Log.d("PagingPdfView", "Set pending scroll to bottom for page ${position - 1}")
                    }
                    scrollToPage(position - 1, true)
                }
            }
            holder.pageView.onNextPage = {
                if (position < mActualPageCount - 1) {
                    scrollToPage(position + 1, true)
                }
            }

            // Check if we should scroll to bottom on this page
            if (mPendingScrollToBottom && mPendingScrollToBottomPage == position) {
                Log.d("PagingPdfView", "onBindViewHolder: setting shouldScrollToBottomOnLoad=true for position=$position")
                holder.pageView.shouldScrollToBottomOnLoad = true
                mPendingScrollToBottom = false
                mPendingScrollToBottomPage = -1
            }

            // Check cache
            val cached = mImageCache.get(position)
            Log.d("PagingPdfView", "onBindViewHolder: position=$position, cached=${cached != null}, shouldScrollToBottom=${holder.pageView.shouldScrollToBottomOnLoad}")
            if (cached != null) {
                holder.pageView.setImage(cached, viewWidth)
                // Force refresh after setting cached image
                refreshViewChildrenLayout(holder.pageView)
            } else {
                holder.pageView.setImage(null, viewWidth)
                renderPage(position, holder, viewWidth)
            }
        }

        override fun getItemCount(): Int = mActualPageCount

        private fun renderPage(pageIndex: Int, holder: PdfPageViewHolder, viewWidth: Int) {
            val renderer = mPdfRenderer ?: return

            if (viewWidth <= 0 || mPdfPageWidth <= 0 || mPdfPageHeight <= 0) return

            val pageHeight = (viewWidth.toFloat() * mPdfPageHeight / mPdfPageWidth).toInt()
            if (pageHeight <= 0) return

            renderScope.launch(Dispatchers.IO) {
                val bitmap = PdfPageRenderer.renderPage(
                    renderer = renderer,
                    pdfMutex = pdfMutex,
                    pageIndex = pageIndex,
                    viewWidth = viewWidth,
                    pageHeight = pageHeight
                )

                bitmap?.let {
                    mImageCache.put(pageIndex, it)
                    withContext(Dispatchers.Main) {
                        if (holder.bindingAdapterPosition == pageIndex) {
                            holder.pageView.setImage(it, viewWidth)
                            // Force refresh after async render
                            refreshViewChildrenLayout(holder.pageView)
                        }
                    }
                }
            }
        }
    }

    private class PdfPageViewHolder(val pageView: ZoomablePageView) : RecyclerView.ViewHolder(pageView) {
        fun resetZoom() {
            pageView.resetZoom()
        }
    }
}

/**
 * Zoomable page view with vertical scroll using NestedScrollView.
 * Supports pinch-to-zoom and double-tap zoom.
 * When zoomed, supports both vertical scrolling and horizontal panning.
 */
@SuppressLint("ClickableViewAccessibility")
private class ZoomablePageView(context: Context) : FrameLayout(context) {

    var minZoom = 1f
    var maxZoom = 3f
    var edgeTapZone = 15f
    var onZoomChange: ((Float) -> Unit)? = null
    var onTap: ((String) -> Unit)? = null
    var onMiddleClick: (() -> Unit)? = null
    var onPreviousPage: ((scrollToBottom: Boolean) -> Unit)? = null
    var onNextPage: (() -> Unit)? = null
    var onZoomStateChange: ((Boolean) -> Unit)? = null

    var shouldScrollToBottomOnLoad = false

    private val scrollView: androidx.core.widget.NestedScrollView
    private val imageView: ImageView

    private var scale = 1f
    private var offsetX = 0f  // Horizontal pan offset when zoomed
    private var pivotY = 0f   // Vertical pivot point for zoom
    private var bgColor = Color.WHITE

    private val scaleDetector: ScaleGestureDetector
    private val gestureDetector: GestureDetector
    private val panDetector: GestureDetector
    private var zoomAnimator: ValueAnimator? = null

    private var isZoomed: Boolean
        get() = scale > minZoom + 0.01f
        set(_) {}

    init {
        // NestedScrollView for vertical scrolling (works with ViewPager2)
        scrollView = androidx.core.widget.NestedScrollView(context).apply {
            layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT)
            isNestedScrollingEnabled = true
            isFillViewport = true
        }

        // ImageView
        imageView = ImageView(context).apply {
            layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT)
            scaleType = ImageView.ScaleType.FIT_START
            adjustViewBounds = true
        }

        scrollView.addView(imageView)
        addView(scrollView)

        // Scale gesture detector for pinch-to-zoom
        scaleDetector = ScaleGestureDetector(context, object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
            override fun onScaleBegin(detector: ScaleGestureDetector): Boolean {
                return true
            }

            override fun onScale(detector: ScaleGestureDetector): Boolean {
                val newScale = (scale * detector.scaleFactor).coerceIn(minZoom, maxZoom)
                if (newScale != scale) {
                    // Get focus point (between fingers) in screen coordinates
                    val focusX = detector.focusX
                    val focusY = detector.focusY

                    // Calculate the point in content coordinates before scale (horizontal only)
                    val contentX = (focusX - offsetX) / scale

                    // Update scale and pivot
                    scale = newScale
                    pivotY = focusY

                    // Calculate new horizontal offset to keep focus point stationary
                    offsetX = focusX - contentX * scale

                    constrainOffset()
                    applyTransform()
                    updateScrollViewPadding()

                    onZoomChange?.invoke(scale)
                    onZoomStateChange?.invoke(isZoomed)
                }
                return true
            }

            override fun onScaleEnd(detector: ScaleGestureDetector) {
                constrainOffset()
                applyTransform()
            }
        })

        // Pan detector for horizontal panning when zoomed
        panDetector = GestureDetector(context, object : GestureDetector.SimpleOnGestureListener() {
            override fun onScroll(e1: MotionEvent?, e2: MotionEvent, distanceX: Float, distanceY: Float): Boolean {
                if (!isZoomed) return false

                // Handle horizontal panning
                offsetX -= distanceX
                constrainOffset()
                applyTransform()
                return true
            }
        })

        // Gesture detector for double-tap and single tap
        gestureDetector = GestureDetector(context, object : GestureDetector.SimpleOnGestureListener() {
            override fun onDown(e: MotionEvent): Boolean {
                return true // Must return true to receive other events
            }

            // onSingleTapUp fires immediately - used for edge taps (instant response)
            override fun onSingleTapUp(e: MotionEvent): Boolean {
                val tapX = e.x
                val edgeRatio = edgeTapZone / 100f
                val leftEdge = width * edgeRatio
                val rightEdge = width * (1f - edgeRatio)

                // Only handle edge taps here (instant response)
                if (tapX < leftEdge || tapX > rightEdge) {
                    handleEdgeTap(tapX)
                    return true
                }
                return false
            }

            // onSingleTapConfirmed fires after double-tap timeout - used for middle zone only
            override fun onSingleTapConfirmed(e: MotionEvent): Boolean {
                val tapX = e.x
                val edgeRatio = edgeTapZone / 100f
                val leftEdge = width * edgeRatio
                val rightEdge = width * (1f - edgeRatio)

                // Only handle middle zone here
                if (tapX >= leftEdge && tapX <= rightEdge) {
                    onMiddleClick?.invoke()
                    return true
                }
                return false
            }

            override fun onDoubleTap(e: MotionEvent): Boolean {
                // Only handle double tap in middle zone
                val tapX = e.x
                val tapY = e.y
                val edgeRatio = edgeTapZone / 100f
                val leftEdge = width * edgeRatio
                val rightEdge = width * (1f - edgeRatio)

                if (tapX < leftEdge || tapX > rightEdge) {
                    return false
                }

                if (isZoomed) {
                    // Zoom out with animation - set pivot to tap point first
                    pivotY = tapY
                    animateZoomTo(minZoom, 0f, tapY)
                } else {
                    // Zoom in with animation to tap point - use maxZoom for full zoom
                    val targetScale = maxZoom

                    // Calculate content point under tap in content coordinates (horizontal only)
                    val contentX = (tapX - offsetX) / scale

                    // Calculate new horizontal offset to keep tap point stationary
                    var targetOffsetX = tapX - contentX * targetScale

                    // Constrain targetOffsetX to valid bounds
                    val scaledWidth = width * targetScale
                    val maxOffsetX = 0f
                    val minOffsetX = width - scaledWidth
                    targetOffsetX = targetOffsetX.coerceIn(minOffsetX.coerceAtMost(0f), maxOffsetX)

                    // Set pivot to tap point and animate zoom
                    pivotY = tapY
                    animateZoomTo(targetScale, targetOffsetX, tapY)
                }
                return true
            }
        })

        // Forward touch events to gesture detectors
        scrollView.setOnTouchListener { _, event ->
            scaleDetector.onTouchEvent(event)
            gestureDetector.onTouchEvent(event)
            if (isZoomed) {
                panDetector.onTouchEvent(event)
            }
            false // Let scrollView also handle vertical scrolling
        }
    }

    private fun constrainOffset() {
        if (!isZoomed) {
            offsetX = 0f
            return
        }

        val scaledWidth = width * scale
        val maxOffsetX = 0f
        val minOffsetX = width - scaledWidth

        offsetX = offsetX.coerceIn(minOffsetX.coerceAtMost(0f), maxOffsetX)
    }

    private fun updateScrollViewPadding() {
        // Add extra vertical padding when zoomed to allow full scroll
        val zoomExtraPadding = if (isZoomed && height > 0) {
            (height * (scale - 1) * 0.25f).toInt()
        } else 0

        if (scrollView.paddingBottom != zoomExtraPadding) {
            scrollView.setPadding(0, 0, 0, zoomExtraPadding)
            scrollView.clipToPadding = false
        }
    }

    override fun onInterceptTouchEvent(ev: MotionEvent): Boolean {
        // Intercept when zoomed or multi-touch
        return isZoomed || ev.pointerCount > 1
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        scaleDetector.onTouchEvent(event)
        gestureDetector.onTouchEvent(event)

        if (isZoomed) {
            panDetector.onTouchEvent(event)
        }

        // Only forward single-pointer events to scrollView (it crashes on multi-touch)
        if (!scaleDetector.isInProgress && event.pointerCount == 1) {
            try {
                scrollView.onTouchEvent(event)
            } catch (e: IllegalArgumentException) {
                // Ignore pointer index errors during multi-touch transitions
            }
        }

        return true
    }

    fun setImage(bitmap: Bitmap?, parentWidth: Int = 0) {
        val shouldScroll = shouldScrollToBottomOnLoad && bitmap != null
        Log.d("ZoomablePageView", "setImage: bitmap=${bitmap != null}, shouldScrollToBottomOnLoad=$shouldScrollToBottomOnLoad, shouldScroll=$shouldScroll")

        // Hide content while scrolling to bottom to avoid visible "jump"
        if (shouldScroll) {
            scrollView.alpha = 0f
        }

        imageView.setImageBitmap(bitmap)
        // Reset zoom when setting new image
        scale = minZoom
        offsetX = 0f
        pivotY = 0f
        applyTransform()
        updateScrollViewPadding()
        requestLayout()

        // Scroll to bottom if requested (for landscape back navigation)
        if (shouldScroll) {
            shouldScrollToBottomOnLoad = false
            Log.d("ZoomablePageView", "setImage: calling scrollToBottom")
            // Use postDelayed to ensure layout is complete, then scroll and show
            scrollView.postDelayed({
                scrollToBottom()
                // Fade in after scroll is complete
                scrollView.animate().alpha(1f).setDuration(100).start()
            }, 50)
        }
    }

    fun scrollToBottom() {
        Log.d("ZoomablePageView", "scrollToBottom called, imageView.height=${imageView.height}, scrollView.height=${scrollView.height}")
        // Calculate the exact scroll position to bottom
        val contentHeight = imageView.height
        val viewportHeight = scrollView.height
        val maxScroll = (contentHeight - viewportHeight).coerceAtLeast(0)
        Log.d("ZoomablePageView", "scrollToBottom: contentHeight=$contentHeight, viewportHeight=$viewportHeight, maxScroll=$maxScroll")

        if (maxScroll > 0) {
            scrollView.scrollTo(0, maxScroll)
            Log.d("ZoomablePageView", "scrollToBottom: scrolled to $maxScroll, actual scrollY=${scrollView.scrollY}")
        }
    }

    fun scrollToBottomWithFade() {
        // Hide, scroll, then fade in to avoid visible jump
        scrollView.alpha = 0f
        scrollView.post {
            scrollToBottom()
            scrollView.animate().alpha(1f).setDuration(100).start()
        }
    }

    private fun applyTransform() {
        // Use translation for horizontal pan and scale for zoom
        scrollView.translationX = offsetX
        scrollView.scaleX = scale
        scrollView.scaleY = scale
        scrollView.pivotX = 0f
        scrollView.pivotY = pivotY
    }

    private fun animateZoomTo(targetScale: Float, targetOffsetX: Float, targetPivotY: Float = pivotY, duration: Long = 300L) {
        zoomAnimator?.cancel()

        val startScale = scale
        val startOffsetX = offsetX
        val startPivotY = pivotY

        zoomAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            this.duration = duration
            interpolator = DecelerateInterpolator()
            addUpdateListener { animator ->
                val fraction = animator.animatedValue as Float
                scale = startScale + (targetScale - startScale) * fraction
                offsetX = startOffsetX + (targetOffsetX - startOffsetX) * fraction
                pivotY = startPivotY + (targetPivotY - startPivotY) * fraction
                applyTransform()
                updateScrollViewPadding()
                onZoomChange?.invoke(scale)
                onZoomStateChange?.invoke(isZoomed)
            }
            start()
        }
    }

    fun resetZoom() {
        animateZoomTo(minZoom, 0f)
        scrollView.smoothScrollTo(0, 0)
    }

    fun resetState() {
        // Cancel any running animation
        zoomAnimator?.cancel()
        // Reset zoom and scroll state
        scale = minZoom
        offsetX = 0f
        pivotY = 0f
        shouldScrollToBottomOnLoad = false
        applyTransform()
        updateScrollViewPadding()
        scrollView.scrollTo(0, 0)
        scrollView.alpha = 1f
        // Clear callbacks to prevent stale references
        onPreviousPage = null
        onNextPage = null
    }

    fun setPageBackgroundColor(color: Int) {
        bgColor = color
        setBackgroundColor(color)
        scrollView.setBackgroundColor(color)
    }

    private fun handleEdgeTap(tapX: Float) {
        val edgeRatio = edgeTapZone / 100f
        val leftEdge = width * edgeRatio
        val rightEdge = width * (1f - edgeRatio)

        val viewportHeight = height
        val contentHeight = (imageView.height * scale).toInt()
        val currentOffset = scrollView.scrollY
        val maxOffset = (contentHeight - viewportHeight).coerceAtLeast(0)

        // Check if landscape mode
        val isLandscape = width > height

        when {
            tapX < leftEdge -> {
                // Left zone - scroll up or previous page
                if (currentOffset <= 0 && offsetX >= 0) {
                    // In landscape mode, go to previous page scrolled to bottom
                    onPreviousPage?.invoke(isLandscape)
                } else {
                    val newOffset = (currentOffset - viewportHeight).coerceAtLeast(0)
                    scrollView.post { scrollView.smoothScrollTo(0, newOffset) }
                }
                onTap?.invoke("left")
            }
            tapX > rightEdge -> {
                // Right zone - scroll down or next page
                if (currentOffset >= maxOffset - 1) {
                    onNextPage?.invoke()
                } else {
                    val newOffset = (currentOffset + viewportHeight).coerceAtMost(maxOffset)
                    scrollView.post { scrollView.smoothScrollTo(0, newOffset) }
                }
                onTap?.invoke("right")
            }
        }
    }
}
