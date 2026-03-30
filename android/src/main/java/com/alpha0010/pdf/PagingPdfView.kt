package com.alpha0010.pdf

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.*
import android.graphics.pdf.PdfRenderer
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.View
import android.view.ViewGroup
import android.view.animation.DecelerateInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.viewpager2.widget.ViewPager2
import androidx.recyclerview.widget.RecyclerView
import kotlinx.coroutines.*
import java.util.concurrent.locks.Lock

/**
 * Paged PDF viewer using ViewPager2 with per-page zoom and vertical scroll.
 * Each page is rendered to fit width with vertical scrolling (like iOS).
 */
@SuppressLint("ViewConstructor")
class PagingPdfView(context: Context, pdfMutex: Lock) : PdfViewerBase(context, pdfMutex) {

    // Views
    private val mViewPager: ViewPager2
    private val mAdapter: PdfPageAdapter

    // Deferred loading flag
    private var mNeedsInitialRender = false

    // Scroll to bottom on next page load (for landscape back navigation)
    private var mPendingScrollToBottom = false
    private var mPendingScrollToBottomPage = -1

    init {
        mBackgroundColor = Color.WHITE
        setBackgroundColor(mBackgroundColor)

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
                if (state == ViewPager2.SCROLL_STATE_IDLE && mPendingScrollToBottom) {
                    val targetPage = mPendingScrollToBottomPage
                    if (targetPage == mCurrentPage) {
                        mPendingScrollToBottom = false
                        mPendingScrollToBottomPage = -1
                        mViewPager.postDelayed({
                            val recyclerView = mViewPager.getChildAt(0) as? RecyclerView
                            val viewHolder = recyclerView?.findViewHolderForAdapterPosition(targetPage) as? PdfPageViewHolder
                            viewHolder?.pageView?.scrollToBottomWithFade()
                        }, 100)
                    }
                }
            }
        })

        addView(mViewPager)
    }

    // MARK: - Override Points

    override fun onSourceChanged() {
        if (width > 0 && height > 0) {
            reloadPdf()
        } else {
            mNeedsInitialRender = true
        }
    }

    override fun onPdfLoaded() {
        mAdapter.notifyDataSetChanged()
        refreshViewChildrenLayout(mViewPager)
    }

    override fun onAnnotationsChanged() {
        mAdapter.notifyDataSetChanged()
    }

    override fun onDrawingModeChanged(mode: DrawingMode) {
        mViewPager.isUserInputEnabled = mode == DrawingMode.VIEW
        invalidateCurrentPage()
    }

    override fun redrawOverlay() {
        invalidateCurrentPage()
    }

    override fun onBackgroundColorChanged() {
        super.onBackgroundColorChanged()
        mAdapter.notifyDataSetChanged()
    }

    // MARK: - Layout

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
            post {
                if (savedPage in 0 until mActualPageCount) {
                    mViewPager.setCurrentItem(savedPage, false)
                }
            }
        }
        mPreviousWidth = w
    }

    // MARK: - Public Commands

    override fun resetZoom() {
        val recyclerView = mViewPager.getChildAt(0) as? RecyclerView ?: return
        val viewHolder = recyclerView.findViewHolderForAdapterPosition(mCurrentPage) as? PdfPageViewHolder
        viewHolder?.resetZoom()
        onZoomChange(1f)
    }

    override fun scrollToPage(page: Int, animated: Boolean) {
        if (page < 0 || page >= mActualPageCount) return
        mViewPager.setCurrentItem(page, animated)
    }

    // MARK: - Helpers

    private fun invalidateCurrentPage() {
        val recyclerView = mViewPager.getChildAt(0) as? RecyclerView ?: return
        val viewHolder = recyclerView.findViewHolderForAdapterPosition(mCurrentPage) as? PdfPageViewHolder ?: return
        viewHolder.pageView.invalidateDrawing()
    }

    private fun refreshViewChildrenLayout(view: View) {
        view.post {
            view.measure(
                MeasureSpec.makeMeasureSpec(view.width, MeasureSpec.EXACTLY),
                MeasureSpec.makeMeasureSpec(view.height, MeasureSpec.EXACTLY)
            )
            view.layout(view.left, view.top, view.right, view.bottom)
        }
    }

    // MARK: - Adapter

    private inner class PdfPageAdapter : RecyclerView.Adapter<PdfPageViewHolder>() {

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): PdfPageViewHolder {
            val pageView = ZoomablePageView(parent.context)
            pageView.layoutParams = RecyclerView.LayoutParams(
                RecyclerView.LayoutParams.MATCH_PARENT,
                RecyclerView.LayoutParams.MATCH_PARENT
            )
            pageView.setPageBackgroundColor(mBackgroundColor)
            pageView.onZoomChange = { scale -> onZoomChange(scale) }
            pageView.onTap = { position -> onTap(position) }
            pageView.onMiddleClick = { onMiddleClick() }
            pageView.onZoomStateChange = { isZoomed ->
                if (drawingController.drawingMode == DrawingMode.VIEW) {
                    mViewPager.isUserInputEnabled = !isZoomed
                }
            }
            pageView.rootOverlayContainer = this@PagingPdfView
            return PdfPageViewHolder(pageView)
        }

        override fun onBindViewHolder(holder: PdfPageViewHolder, position: Int) {
            val viewWidth = this@PagingPdfView.width

            if (viewWidth <= 0 || mPdfPageWidth <= 0 || mPdfPageHeight <= 0) return

            holder.pageView.resetState()

            holder.pageView.minZoom = mMinScale
            holder.pageView.maxZoom = mMaxScale
            holder.pageView.edgeTapZone = mEdgeTapZone

            holder.pageView.drawingController = drawingController
            holder.pageView.textAnnotationHandler = this@PagingPdfView.textAnnotationHandler
            holder.pageView.pageIndex = position
            holder.pageView.onPreviousPage = { scrollToBottom ->
                if (position > 0) {
                    if (scrollToBottom) {
                        mPendingScrollToBottom = true
                        mPendingScrollToBottomPage = position - 1
                    }
                    scrollToPage(position - 1, true)
                }
            }
            holder.pageView.onNextPage = {
                if (position < mActualPageCount - 1) {
                    scrollToPage(position + 1, true)
                }
            }

            if (mPendingScrollToBottom && mPendingScrollToBottomPage == position) {
                holder.pageView.shouldScrollToBottomOnLoad = true
                mPendingScrollToBottom = false
                mPendingScrollToBottomPage = -1
            }

            val cached = mImageCache.get(position)
            if (cached != null) {
                holder.pageView.setImage(cached, viewWidth)
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

            val annotation = if (pageIndex < mParsedAnnotations.size) mParsedAnnotations[pageIndex] else null

            renderScope.launch(Dispatchers.IO) {
                val bitmap = PdfPageRenderer.renderPage(
                    renderer = renderer,
                    pdfMutex = pdfMutex,
                    pageIndex = pageIndex,
                    viewWidth = viewWidth,
                    pageHeight = pageHeight,
                    annotation = annotation
                )

                bitmap?.let {
                    mImageCache.put(pageIndex, it)
                    withContext(Dispatchers.Main) {
                        if (holder.bindingAdapterPosition == pageIndex) {
                            holder.pageView.setImage(it, viewWidth)
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

    // Drawing support
    var drawingController: DrawingController? = null
    var textAnnotationHandler: TextAnnotationHandler? = null
    var pageIndex: Int = 0
    var rootOverlayContainer: ViewGroup? = null

    private val scrollView: androidx.core.widget.NestedScrollView
    private val imageView: ImageView
    private val drawingOverlay: DrawingOverlayView

    private var scale = 1f
    private var offsetX = 0f
    private var pivotY = 0f
    private var bgColor = Color.WHITE

    private val scaleDetector: ScaleGestureDetector
    private val gestureDetector: GestureDetector
    private val panDetector: GestureDetector
    private var zoomAnimator: ValueAnimator? = null

    private var isZoomed: Boolean
        get() = scale > minZoom + 0.01f
        set(_) {}

    private val contentContainer: FrameLayout

    init {
        scrollView = androidx.core.widget.NestedScrollView(context).apply {
            layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT)
            isNestedScrollingEnabled = true
            isFillViewport = true
        }

        contentContainer = FrameLayout(context).apply {
            layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT)
        }

        imageView = ImageView(context).apply {
            layoutParams = FrameLayout.LayoutParams(
                LayoutParams.MATCH_PARENT,
                LayoutParams.WRAP_CONTENT
            ).apply {
                gravity = android.view.Gravity.CENTER_VERTICAL
            }
            scaleType = ImageView.ScaleType.FIT_CENTER
            adjustViewBounds = true
        }

        drawingOverlay = DrawingOverlayView(context).apply {
            layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT)
            setBackgroundColor(Color.TRANSPARENT)
        }

        contentContainer.addView(imageView)
        contentContainer.addView(drawingOverlay)
        scrollView.addView(contentContainer)
        addView(scrollView)

        // Scale gesture detector
        scaleDetector = ScaleGestureDetector(context, object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
            override fun onScaleBegin(detector: ScaleGestureDetector): Boolean = true

            override fun onScale(detector: ScaleGestureDetector): Boolean {
                val newScale = (scale * detector.scaleFactor).coerceIn(minZoom, maxZoom)
                if (newScale != scale) {
                    val focusX = detector.focusX
                    val focusY = detector.focusY

                    val contentX = (focusX - offsetX) / scale
                    val contentY = focusY / scale + scrollView.scrollY

                    scale = newScale
                    pivotY = focusY

                    offsetX = focusX - contentX * scale

                    val newScrollY = (contentY - focusY / scale).toInt().coerceAtLeast(0)
                    scrollView.scrollTo(0, newScrollY)

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

        // Pan detector
        panDetector = GestureDetector(context, object : GestureDetector.SimpleOnGestureListener() {
            override fun onScroll(e1: MotionEvent?, e2: MotionEvent, distanceX: Float, distanceY: Float): Boolean {
                if (!isZoomed) return false
                offsetX -= distanceX
                constrainOffset()
                applyTransform()
                return true
            }
        })

        // Gesture detector for taps
        gestureDetector = GestureDetector(context, object : GestureDetector.SimpleOnGestureListener() {
            override fun onDown(e: MotionEvent): Boolean = true

            override fun onSingleTapUp(e: MotionEvent): Boolean {
                val zone = classifyTapZone(e.x, width, edgeTapZone)
                if (zone != TapZone.MIDDLE) {
                    handleEdgeTap(e.x)
                    return true
                }
                return false
            }

            override fun onSingleTapConfirmed(e: MotionEvent): Boolean {
                val zone = classifyTapZone(e.x, width, edgeTapZone)
                if (zone == TapZone.MIDDLE) {
                    onMiddleClick?.invoke()
                    return true
                }
                return false
            }

            override fun onDoubleTap(e: MotionEvent): Boolean {
                val zone = classifyTapZone(e.x, width, edgeTapZone)
                if (zone != TapZone.MIDDLE) return false

                val currentScrollY = scrollView.scrollY
                val contentY = e.y / scale + currentScrollY


                if (isZoomed) {
                    val targetScale = minZoom
                    val newScrollY = (contentY - e.y / targetScale).toInt().coerceAtLeast(0)


                    pivotY = e.y
                    animateZoomTo(targetScale, 0f, e.y, newScrollY)
                } else {
                    val targetScale = maxZoom
                    val contentX = (e.x - offsetX) / scale
                    var targetOffsetX = e.x - contentX * targetScale

                    val scaledWidth = width * targetScale
                    val minOffsetX = width - scaledWidth
                    targetOffsetX = targetOffsetX.coerceIn(minOffsetX.coerceAtMost(0f), 0f)

                    val newScrollY = (contentY - e.y / targetScale).toInt().coerceAtLeast(0)


                    pivotY = e.y
                    animateZoomTo(targetScale, targetOffsetX, e.y, newScrollY)
                }
                return true
            }
        })

        scrollView.setOnTouchListener { _, event ->
            scaleDetector.onTouchEvent(event)
            gestureDetector.onTouchEvent(event)
            if (isZoomed) {
                panDetector.onTouchEvent(event)
            }
            false
        }
    }

    private fun constrainOffset() {
        if (!isZoomed) {
            offsetX = 0f
            return
        }
        val scaledWidth = width * scale
        val minOffsetX = width - scaledWidth
        offsetX = offsetX.coerceIn(minOffsetX.coerceAtMost(0f), 0f)
    }

    private fun updateScrollViewPadding() {
        // Padding must be enough to scroll all zoomed content.
        // Needed: (content + padding) - viewport >= content - viewport/scale
        // → padding >= viewport * (1 - 1/scale)
        val zoomExtraPadding = if (isZoomed && height > 0) {
            (height * (1f - 1f / scale)).toInt()
        } else 0

        if (scrollView.paddingBottom != zoomExtraPadding) {
            scrollView.setPadding(0, 0, 0, zoomExtraPadding)
            scrollView.clipToPadding = false
        }
    }

    // Saved zoom state before keyboard shows
    private var preKeyboardScrollY: Int? = null
    private var preKeyboardScale: Float? = null
    private var preKeyboardOffsetX: Float? = null
    private var isKeyboardVisible = false

    /** Call before showing keyboard to save zoom state */
    fun saveZoomStateForKeyboard() {
        if (isZoomed) {
            preKeyboardScrollY = scrollView.scrollY
            preKeyboardScale = scale
            preKeyboardOffsetX = offsetX
        }
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        if (oldw == w && oldh > 0 && h < oldh) {
            isKeyboardVisible = true
        } else if (oldw == w && oldh > 0 && h > oldh && isKeyboardVisible) {
            isKeyboardVisible = false
        }
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)
        if (!isKeyboardVisible && preKeyboardScrollY != null) {
            val ss = preKeyboardScrollY!!
            val sc = preKeyboardScale ?: scale
            val ox = preKeyboardOffsetX ?: offsetX
            preKeyboardScrollY = null
            preKeyboardScale = null
            preKeyboardOffsetX = null
            scale = sc
            offsetX = ox
            applyTransform()
            updateScrollViewPadding()
            // Must post to run AFTER NestedScrollView finishes its own layout
            scrollView.post {
                scrollView.scrollTo(0, ss)
            }
        }
    }

    override fun onInterceptTouchEvent(ev: MotionEvent): Boolean {
        val controller = drawingController
        if (controller != null && controller.drawingMode != DrawingMode.VIEW) return true
        return isZoomed || ev.pointerCount > 1
    }

    private var drawingCancelledByMultiTouch = false
    private var lastMultiTouchY = 0f

    private fun averageTouchY(event: MotionEvent): Float {
        var sum = 0f
        for (i in 0 until event.pointerCount) {
            sum += event.getY(i)
        }
        return sum / event.pointerCount
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        val controller = drawingController

        if (controller != null && controller.drawingMode != DrawingMode.VIEW) {
            // Two+ fingers: cancel drawing, handle zoom/pan instead
            if (event.pointerCount > 1) {
                if (!drawingCancelledByMultiTouch) {
                    if (controller.isDrawing) {
                        controller.handleTouchCancelled()
                    }
                    textAnnotationHandler?.handleMultiTouchDetected()
                    drawingCancelledByMultiTouch = true
                    lastMultiTouchY = averageTouchY(event)
                }
                scaleDetector.onTouchEvent(event)

                // Manual 2-finger scroll
                val avgY = averageTouchY(event)
                val deltaY = lastMultiTouchY - avgY
                if (kotlin.math.abs(deltaY) > 0.5f) {
                    scrollView.scrollBy(0, deltaY.toInt())
                    lastMultiTouchY = avgY
                }
                return true
            }

            // After multi-touch ends, keep forwarding scale events until all up
            if (drawingCancelledByMultiTouch) {
                scaleDetector.onTouchEvent(event)
                if (event.action == MotionEvent.ACTION_UP || event.action == MotionEvent.ACTION_CANCEL) {
                    drawingCancelledByMultiTouch = false
                }
                return true
            }

            // Single finger: draw
            handleDrawingTouch(event, controller)
            return true
        }

        scaleDetector.onTouchEvent(event)
        gestureDetector.onTouchEvent(event)

        if (isZoomed) {
            panDetector.onTouchEvent(event)
        }

        if (!scaleDetector.isInProgress && event.pointerCount == 1) {
            try {
                scrollView.onTouchEvent(event)
            } catch (_: IllegalArgumentException) {}
        }

        return true
    }

    private fun setupTextHandler() {
        val handler = textAnnotationHandler ?: return
        handler.delegate = object : TextAnnotationHandlerDelegate {
            override val textHandlerDrawingController: DrawingController get() = drawingController!!
            override val textHandlerContentContainer: View get() = contentContainer
            override val textHandlerHostView: ViewGroup get() = rootOverlayContainer ?: this@ZoomablePageView
            override val textHandlerZoomScale: Float get() = scale

            override fun textHandlerContentRectForPage(page: Int): RectF = drawingOverlay.contentRect
            override fun textHandlerPageForPoint(pointInContent: PointF): Int = pageIndex
            override fun textHandlerRedrawOverlay() {
                drawingOverlay.post { drawingOverlay.invalidate() }
            }
        }
        handler.screenToContentConverter = { ev ->
            val contentX = (ev.x - offsetX) / scale
            val contentY = ev.y / scale + scrollView.scrollY
            PointF(contentX, contentY)
        }
        handler.contentToScreenConverter = { contentPoint ->
            val screenX = contentPoint.x * scale + offsetX
            val screenY = (contentPoint.y - scrollView.scrollY) * scale
            PointF(screenX, screenY)
        }
    }

    private fun handleDrawingTouch(event: MotionEvent, controller: DrawingController) {
        if (controller.drawingMode == DrawingMode.TEXT) {
            setupTextHandler()
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    saveZoomStateForKeyboard()
                    parent?.requestDisallowInterceptTouchEvent(true)
                    textAnnotationHandler?.handleTouchDown(event)
                }
                MotionEvent.ACTION_MOVE -> textAnnotationHandler?.handleTouchMove(event)
                MotionEvent.ACTION_UP -> {
                    saveZoomStateForKeyboard()
                    parent?.requestDisallowInterceptTouchEvent(false)
                    textAnnotationHandler?.handleTouchUp(event)
                }
                MotionEvent.ACTION_CANCEL -> {
                    parent?.requestDisallowInterceptTouchEvent(false)
                    textAnnotationHandler?.handleTouchCancel()
                }
            }
            return
        }

        val contentRect = drawingOverlay.contentRect
        if (contentRect.isEmpty) return

        val contentX = (event.x - offsetX) / scale
        val contentY = event.y / scale + scrollView.scrollY

        val normalizedX = (contentX - contentRect.left) / contentRect.width()
        val normalizedY = (contentY - contentRect.top) / contentRect.height()
        val point = PointF(normalizedX, normalizedY)

        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                parent?.requestDisallowInterceptTouchEvent(true)
                controller.handleTouchBegan(point, pageIndex, contentRect)
            }
            MotionEvent.ACTION_MOVE -> {
                controller.handleTouchMoved(point, pageIndex, contentRect)
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                parent?.requestDisallowInterceptTouchEvent(false)
                controller.handleTouchEnded(pageIndex)
            }
        }

        drawingOverlay.post { drawingOverlay.invalidate() }
    }

    fun invalidateDrawing() {
        drawingOverlay.drawingController = drawingController
        drawingOverlay.pageIndex = pageIndex
        drawingOverlay.zoomScale = scale
        drawingOverlay.post { drawingOverlay.invalidate() }
    }

    fun setImage(bitmap: Bitmap?, parentWidth: Int = 0) {
        val shouldScroll = shouldScrollToBottomOnLoad && bitmap != null

        if (shouldScroll) {
            scrollView.alpha = 0f
        }

        imageView.setImageBitmap(bitmap)
        scale = minZoom
        offsetX = 0f
        pivotY = 0f
        applyTransform()
        updateScrollViewPadding()
        updateDrawingOverlay(parentWidth, bitmap)
        requestLayout()

        if (shouldScroll) {
            shouldScrollToBottomOnLoad = false
            scrollView.postDelayed({
                scrollToBottom()
                scrollView.animate().alpha(1f).setDuration(100).start()
            }, 50)
        }
    }

    fun scrollToBottom() {
        val contentHeight = imageView.height
        val viewportHeight = scrollView.height
        val maxScroll = (contentHeight - viewportHeight).coerceAtLeast(0)
        if (maxScroll > 0) {
            scrollView.scrollTo(0, maxScroll)
        }
    }

    fun scrollToBottomWithFade() {
        scrollView.alpha = 0f
        scrollView.post {
            scrollToBottom()
            scrollView.animate().alpha(1f).setDuration(100).start()
        }
    }

    private fun applyTransform() {
        scrollView.translationX = offsetX
        scrollView.scaleX = scale
        scrollView.scaleY = scale
        scrollView.pivotX = 0f
        scrollView.pivotY = 0f

        drawingOverlay.zoomScale = scale
        drawingOverlay.invalidate()
    }

    private fun updateDrawingOverlay(parentWidth: Int, bitmap: Bitmap?) {
        if (bitmap == null || parentWidth <= 0) {
            drawingOverlay.contentRect = RectF()
            return
        }

        val bitmapWidth = bitmap.width.toFloat()
        val bitmapHeight = bitmap.height.toFloat()
        val viewWidth = parentWidth.toFloat()
        val viewHeight = viewWidth * bitmapHeight / bitmapWidth

        drawingOverlay.contentRect = RectF(0f, 0f, viewWidth, viewHeight)
        drawingOverlay.drawingController = drawingController
        drawingOverlay.pageIndex = pageIndex
        drawingOverlay.zoomScale = scale

        drawingOverlay.post {
            // After layout, imageView.top reflects centering offset from gravity
            val topOffset = imageView.top.toFloat()
            if (topOffset > 0f) {
                drawingOverlay.contentRect = RectF(0f, topOffset, viewWidth, topOffset + viewHeight)
            }
            drawingOverlay.requestLayout()
            drawingOverlay.invalidate()
        }
    }

    private fun animateZoomTo(targetScale: Float, targetOffsetX: Float, targetPivotY: Float = pivotY, targetScrollY: Int = -1, duration: Long = 300L) {
        zoomAnimator?.cancel()

        val startScale = scale
        val startOffsetX = offsetX
        val startPivotY = pivotY
        val startScrollY = scrollView.scrollY

        zoomAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            this.duration = duration
            interpolator = DecelerateInterpolator()
            addUpdateListener { animator ->
                val fraction = animator.animatedValue as Float
                scale = startScale + (targetScale - startScale) * fraction
                offsetX = startOffsetX + (targetOffsetX - startOffsetX) * fraction
                pivotY = startPivotY + (targetPivotY - startPivotY) * fraction
                if (targetScrollY >= 0) {
                    val scrollY = startScrollY + ((targetScrollY - startScrollY) * fraction).toInt()
                    scrollView.scrollTo(0, scrollY)
                }
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
        zoomAnimator?.cancel()
        scale = minZoom
        offsetX = 0f
        pivotY = 0f
        shouldScrollToBottomOnLoad = false
        applyTransform()
        updateScrollViewPadding()
        scrollView.scrollTo(0, 0)
        scrollView.alpha = 1f
        onPreviousPage = null
        onNextPage = null
    }

    fun setPageBackgroundColor(color: Int) {
        bgColor = color
        setBackgroundColor(color)
        scrollView.setBackgroundColor(color)
    }

    private fun handleEdgeTap(tapX: Float) {
        val controller = drawingController
        if (controller != null && controller.drawingMode != DrawingMode.VIEW) return

        val zone = classifyTapZone(tapX, width, edgeTapZone)
        val viewportHeight = height
        val contentHeight = (imageView.height * scale).toInt()
        val currentOffset = scrollView.scrollY
        val maxOffset = (contentHeight - viewportHeight).coerceAtLeast(0)
        val isLandscape = width > height

        when (zone) {
            TapZone.LEFT -> {
                if (currentOffset <= 0 && offsetX >= 0) {
                    onPreviousPage?.invoke(isLandscape)
                } else {
                    val newOffset = (currentOffset - viewportHeight).coerceAtLeast(0)
                    scrollView.post { scrollView.smoothScrollTo(0, newOffset) }
                }
                onTap?.invoke("left")
            }
            TapZone.RIGHT -> {
                if (currentOffset >= maxOffset - 1) {
                    onNextPage?.invoke()
                } else {
                    val newOffset = (currentOffset + viewportHeight).coerceAtMost(maxOffset)
                    scrollView.post { scrollView.smoothScrollTo(0, newOffset) }
                }
                onTap?.invoke("right")
            }
            TapZone.MIDDLE -> { /* handled by gesture detector */ }
        }
    }
}
