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
import android.widget.ImageView
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.facebook.react.uimanager.PixelUtil
import kotlinx.coroutines.*
import java.util.concurrent.locks.Lock

/**
 * Zoomable scrollable PDF viewer using RecyclerView for virtualization.
 */
@SuppressLint("ViewConstructor")
class ZoomablePdfScrollView(context: Context, pdfMutex: Lock) : PdfViewerBase(context, pdfMutex) {

    // Zoom state
    private var mScale = 1f
    private var mOffsetX = 0f
    private var mOffsetY = 0f
    private var mPivotY = 0f

    // Zoomable-only props
    private var mPaddingTop = 0
    private var mPaddingBottom = 0

    // Views
    private val mRecyclerView: RecyclerView
    private val mAdapter: PdfPageAdapter
    private val mDrawingOverlay: DrawingOverlayView

    // Gesture detectors
    private val mScaleDetector: ScaleGestureDetector
    private val mGestureDetector: GestureDetector
    private val mPanGestureDetector: GestureDetector

    // Zoom animation
    private var zoomAnimator: ValueAnimator? = null

    init {
        // Setup RecyclerView
        mRecyclerView = RecyclerView(context).apply {
            layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT)
            layoutManager = LinearLayoutManager(context, LinearLayoutManager.VERTICAL, false)
            setHasFixedSize(true)
        }

        mAdapter = PdfPageAdapter()
        mRecyclerView.adapter = mAdapter

        // Drawing overlay (full screen, sits above RecyclerView)
        mDrawingOverlay = DrawingOverlayView(context).apply {
            layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT)
            setBackgroundColor(Color.TRANSPARENT)
            drawingController = this@ZoomablePdfScrollView.drawingController
            multiPageMode = true
        }

        addView(mRecyclerView)
        addView(mDrawingOverlay)

        // Setup text annotation handler
        textAnnotationHandler.delegate = object : TextAnnotationHandlerDelegate {
            override val textHandlerDrawingController: DrawingController get() = drawingController
            override val textHandlerContentContainer: View get() = mRecyclerView
            override val textHandlerHostView: ViewGroup get() = this@ZoomablePdfScrollView
            override val textHandlerZoomScale: Float get() = mScale

            override fun textHandlerContentRectForPage(page: Int): RectF {
                val pageHeightPx = getPageHeight()
                return RectF(0f, page * pageHeightPx.toFloat(), width.toFloat(), (page + 1) * pageHeightPx.toFloat())
            }

            override fun textHandlerPageForPoint(pointInContent: PointF): Int {
                val pageHeightPx = getPageHeight()
                if (pageHeightPx <= 0) return 0
                return (pointInContent.y / pageHeightPx).toInt().coerceIn(0, mActualPageCount - 1)
            }

            override fun textHandlerRedrawOverlay() {
                mDrawingOverlay.post { mDrawingOverlay.invalidate() }
            }
        }
        textAnnotationHandler.screenToContentConverter = { event ->
            val scrollOffset = mRecyclerView.computeVerticalScrollOffset()
            val paddingTop = mRecyclerView.paddingTop
            val contentX = (event.x - mOffsetX) / mScale
            val contentY = event.y / mScale - paddingTop + scrollOffset
            PointF(contentX, contentY)
        }
        textAnnotationHandler.contentToScreenConverter = { contentPoint ->
            val scrollOffset = mRecyclerView.computeVerticalScrollOffset()
            val paddingTop = mRecyclerView.paddingTop
            val screenX = contentPoint.x * mScale + mOffsetX
            val screenY = (contentPoint.y - scrollOffset + paddingTop) * mScale
            PointF(screenX, screenY)
        }

        // Setup scale gesture detector
        mScaleDetector = ScaleGestureDetector(context, object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
            override fun onScaleBegin(detector: ScaleGestureDetector): Boolean {
                zoomAnimator?.cancel()
                return true
            }

            override fun onScale(detector: ScaleGestureDetector): Boolean {
                val scaleFactor = detector.scaleFactor
                val newScale = (mScale * scaleFactor).coerceIn(mMinScale, mMaxScale)

                if (newScale != mScale) {
                    val focusX = detector.focusX
                    val focusY = detector.focusY

                    val currentScrollY = mRecyclerView.computeVerticalScrollOffset()
                    val oldPaddingTop = mRecyclerView.paddingTop
                    val contentX = (focusX - mOffsetX) / mScale
                    val contentY = focusY / mScale - oldPaddingTop + currentScrollY

                    mScale = newScale
                    mPivotY = focusY

                    mOffsetX = focusX - contentX * mScale

                    val newZoomExtraTop = if (mScale > 1.01f && height > 0) {
                        (height * (mScale - 1) * 0.05f).toInt()
                    } else 0
                    val newPaddingTop = mPaddingTop + newZoomExtraTop

                    val newScrollY = (contentY - focusY / mScale + newPaddingTop).toInt().coerceAtLeast(0)
                    val scrollDelta = newScrollY - currentScrollY
                    if (scrollDelta != 0) {
                        mRecyclerView.scrollBy(0, scrollDelta)
                    }

                    constrainOffset()
                    applyTransform()
                    onZoomChange(mScale)
                }
                return true
            }
        })

        // Setup gesture detector for taps
        mGestureDetector = GestureDetector(context, object : GestureDetector.SimpleOnGestureListener() {
            override fun onDown(e: MotionEvent): Boolean = true

            override fun onSingleTapUp(e: MotionEvent): Boolean {
                val zone = classifyTapZone(e.x, width, mEdgeTapZone)
                if (zone != TapZone.MIDDLE) {
                    handleEdgeTap(e.x)
                    return true
                }
                return false
            }

            override fun onSingleTapConfirmed(e: MotionEvent): Boolean {
                val zone = classifyTapZone(e.x, width, mEdgeTapZone)
                if (zone == TapZone.MIDDLE) {
                    onMiddleClick()
                    return true
                }
                return false
            }

            override fun onDoubleTap(e: MotionEvent): Boolean {
                val zone = classifyTapZone(e.x, width, mEdgeTapZone)
                if (zone != TapZone.MIDDLE) return false

                val currentScrollY = mRecyclerView.computeVerticalScrollOffset()
                val oldPaddingTop = mRecyclerView.paddingTop
                val contentY = e.y / mScale - oldPaddingTop + currentScrollY



                if (mScale > mMinScale) {

                    mPivotY = e.y
                    animateZoomTo(mMinScale, 0f, contentY, e.y)
                } else {
                    val targetScale = mMaxScale
                    val contentX = (e.x - mOffsetX) / mScale
                    var targetOffsetX = e.x - contentX * targetScale

                    val scaledWidth = width * targetScale
                    val minOffsetX = width - scaledWidth
                    targetOffsetX = targetOffsetX.coerceIn(minOffsetX.coerceAtMost(0f), 0f)


                    mPivotY = e.y
                    animateZoomTo(targetScale, targetOffsetX, contentY, e.y)
                }
                return true
            }
        })

        // Setup pan gesture detector for horizontal panning when zoomed
        mPanGestureDetector = GestureDetector(context, object : GestureDetector.SimpleOnGestureListener() {
            override fun onScroll(e1: MotionEvent?, e2: MotionEvent, distanceX: Float, distanceY: Float): Boolean {
                if (mScale <= 1f) return false
                mOffsetX -= distanceX
                constrainOffset()
                applyTransform()
                return true
            }
        })

        // Scroll listener for page change tracking and drawing overlay sync
        mRecyclerView.addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                updateCurrentPage()
                mDrawingOverlay.scrollOffset = mRecyclerView.computeVerticalScrollOffset().toFloat()
                mDrawingOverlay.recyclerPaddingTop = mRecyclerView.paddingTop.toFloat()
                mDrawingOverlay.invalidate()
            }
        })
    }

    // MARK: - Override Points

    override fun onPdfLoaded() {
        mAdapter.notifyDataSetChanged()
        updateDrawingOverlay()
    }

    override fun onAnnotationsChanged() {
        mAdapter.notifyDataSetChanged()
    }

    override fun onDrawingModeChanged(mode: DrawingMode) {
        updateDrawingOverlay()
        mDrawingOverlay.bringToFront()
    }

    override fun redrawOverlay() {
        updateDrawingOverlay()
    }

    override fun setMinZoom(minZoom: Float) {
        super.setMinZoom(minZoom)
        if (mScale < mMinScale) {
            mScale = mMinScale
            constrainOffset()
            applyTransform()
        }
    }

    override fun setMaxZoom(maxZoom: Float) {
        super.setMaxZoom(maxZoom)
        if (mScale > mMaxScale) {
            mScale = mMaxScale
            constrainOffset()
            applyTransform()
        }
    }

    // MARK: - Zoomable-only Props

    fun setPdfPaddingTop(padding: Float) {
        mPaddingTop = PixelUtil.toPixelFromDIP(padding).toInt().coerceAtLeast(0)
        updateRecyclerViewPadding()
    }

    fun setPdfPaddingBottom(padding: Float) {
        mPaddingBottom = PixelUtil.toPixelFromDIP(padding).toInt().coerceAtLeast(0)
        updateRecyclerViewPadding()
    }

    // MARK: - Transform

    private fun constrainOffset() {
        if (mScale <= 1f) {
            mOffsetX = 0f
            return
        }
        val scaledWidth = width * mScale
        val minOffsetX = width - scaledWidth
        mOffsetX = mOffsetX.coerceIn(minOffsetX.coerceAtMost(0f), 0f)
    }

    private fun applyTransform() {
        mRecyclerView.translationX = mOffsetX
        mRecyclerView.scaleX = mScale
        mRecyclerView.scaleY = mScale
        mRecyclerView.pivotX = 0f
        mRecyclerView.pivotY = 0f

        mDrawingOverlay.zoomScale = mScale
        mDrawingOverlay.offsetX = mOffsetX
        mDrawingOverlay.scrollOffset = mRecyclerView.computeVerticalScrollOffset().toFloat()
        mDrawingOverlay.recyclerPaddingTop = mRecyclerView.paddingTop.toFloat()
        mDrawingOverlay.invalidate()

        updateRecyclerViewPadding()
    }

    private fun updateRecyclerViewPadding() {
        val zoomExtraTop = if (mScale > 1.01f && height > 0) {
            (height * (mScale - 1) * 0.05f).toInt()
        } else 0
        val zoomExtraBottom = if (mScale > 1.01f && height > 0) {
            (height * (mScale - 1) * 0.25f).toInt()
        } else 0

        val newTopPadding = mPaddingTop + zoomExtraTop
        val newBottomPadding = mPaddingBottom + zoomExtraBottom

        if (mRecyclerView.paddingTop != newTopPadding || mRecyclerView.paddingBottom != newBottomPadding) {
            mRecyclerView.setPadding(0, newTopPadding, 0, newBottomPadding)
            mRecyclerView.clipToPadding = false
            mRecyclerView.requestLayout()
        }
    }

    private fun updateDrawingOverlay() {
        val pageHeightPx = getPageHeight()
        if (pageHeightPx <= 0) return

        mDrawingOverlay.pageCount = mActualPageCount
        mDrawingOverlay.pageHeight = pageHeightPx.toFloat()
        mDrawingOverlay.scrollOffset = mRecyclerView.computeVerticalScrollOffset().toFloat()
        mDrawingOverlay.recyclerPaddingTop = mRecyclerView.paddingTop.toFloat()
        mDrawingOverlay.zoomScale = mScale
        mDrawingOverlay.invalidate()
    }

    // MARK: - Touch Handling

    @SuppressLint("ClickableViewAccessibility")
    override fun onInterceptTouchEvent(ev: MotionEvent): Boolean = true

    private var mDrawingCancelledByMultiTouch = false
    private var mLastMultiTouchY = 0f

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (drawingController.drawingMode != DrawingMode.VIEW) {
            // Two+ fingers: cancel drawing, handle zoom/pan instead
            if (event.pointerCount > 1) {
                if (!mDrawingCancelledByMultiTouch) {
                    if (drawingController.isDrawing) {
                        drawingController.handleTouchCancelled()
                    }
                    textAnnotationHandler.handleMultiTouchDetected()
                    mDrawingCancelledByMultiTouch = true
                    mLastMultiTouchY = averageTouchY(event)
                }
                mScaleDetector.onTouchEvent(event)

                // Manual 2-finger scroll: track average Y movement
                val avgY = averageTouchY(event)
                val deltaY = mLastMultiTouchY - avgY
                if (kotlin.math.abs(deltaY) > 0.5f) {
                    mRecyclerView.scrollBy(0, deltaY.toInt())
                    mLastMultiTouchY = avgY
                }
                return true
            }

            // After multi-touch ends, keep forwarding scale events until all up
            if (mDrawingCancelledByMultiTouch) {
                mScaleDetector.onTouchEvent(event)
                if (event.action == MotionEvent.ACTION_UP || event.action == MotionEvent.ACTION_CANCEL) {
                    mDrawingCancelledByMultiTouch = false
                }
                return true
            }

            // Single finger: draw
            handleDrawingTouch(event)
            return true
        }

        mScaleDetector.onTouchEvent(event)
        mGestureDetector.onTouchEvent(event)

        if (mScale > 1f) {
            mPanGestureDetector.onTouchEvent(event)
        }

        if (event.pointerCount == 1 && !mScaleDetector.isInProgress) {
            mRecyclerView.onTouchEvent(event)
        }

        return true
    }

    private fun averageTouchY(event: MotionEvent): Float {
        var sum = 0f
        for (i in 0 until event.pointerCount) {
            sum += event.getY(i)
        }
        return sum / event.pointerCount
    }

    private fun handleDrawingTouch(event: MotionEvent) {
        if (drawingController.drawingMode == DrawingMode.TEXT) {
            when (event.action) {
                MotionEvent.ACTION_DOWN -> textAnnotationHandler.handleTouchDown(event)
                MotionEvent.ACTION_MOVE -> textAnnotationHandler.handleTouchMove(event)
                MotionEvent.ACTION_UP -> textAnnotationHandler.handleTouchUp(event)
                MotionEvent.ACTION_CANCEL -> textAnnotationHandler.handleTouchCancel()
            }
            return
        }

        val pageHeightPx = getPageHeight()
        if (pageHeightPx <= 0) return

        if (mDrawingOverlay.pageCount == 0 || mDrawingOverlay.pageHeight <= 0f) {
            updateDrawingOverlay()
        }

        val scrollOffset = mRecyclerView.computeVerticalScrollOffset()
        val paddingTop = mRecyclerView.paddingTop

        val contentX = (event.x - mOffsetX) / mScale
        val contentY = event.y / mScale - paddingTop + scrollOffset

        val pageIndex = (contentY / pageHeightPx).toInt().coerceIn(0, mActualPageCount - 1)

        val normalizedX = contentX / width
        val normalizedY = (contentY - pageIndex * pageHeightPx) / pageHeightPx
        val point = PointF(normalizedX.toFloat(), normalizedY.toFloat())

        val pageTop = pageIndex * pageHeightPx - scrollOffset
        val contentRect = RectF(0f, pageTop.toFloat(), width.toFloat(), (pageTop + pageHeightPx).toFloat())

        when (event.action) {
            MotionEvent.ACTION_DOWN -> drawingController.handleTouchBegan(point, pageIndex, contentRect)
            MotionEvent.ACTION_MOVE -> drawingController.handleTouchMoved(point, pageIndex, contentRect)
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> drawingController.handleTouchEnded(pageIndex)
        }
    }

    // MARK: - Edge Tap Handling

    private fun handleEdgeTap(tapX: Float) {
        if (drawingController.drawingMode != DrawingMode.VIEW) return

        val zone = classifyTapZone(tapX, width, mEdgeTapZone)
        val viewportHeight = height
        val layoutManager = mRecyclerView.layoutManager as? LinearLayoutManager ?: return
        val isPortraitMode = height > width

        when (zone) {
            TapZone.LEFT -> {
                if (isPortraitMode) {
                    scrollToCenteredPage(getCurrentCenteredPage() - 1)
                } else {
                    val firstVisible = layoutManager.findFirstVisibleItemPosition()
                    val firstView = layoutManager.findViewByPosition(firstVisible)
                    val actualTopPadding = mRecyclerView.paddingTop

                    if (firstVisible == 0 && firstView != null) {
                        val currentTop = firstView.top
                        if (currentTop < actualTopPadding) {
                            val scrollAmount = currentTop - actualTopPadding
                            mRecyclerView.post { mRecyclerView.smoothScrollBy(0, scrollAmount) }
                        }
                    } else {
                        mRecyclerView.post { mRecyclerView.smoothScrollBy(0, -viewportHeight) }
                    }
                }
                onTap("left")
            }
            TapZone.RIGHT -> {
                if (isPortraitMode) {
                    scrollToCenteredPage(getCurrentCenteredPage() + 1)
                } else {
                    val lastVisible = layoutManager.findLastVisibleItemPosition()
                    val lastView = layoutManager.findViewByPosition(lastVisible)
                    val actualBottomPadding = mRecyclerView.paddingBottom

                    if (lastVisible == mActualPageCount - 1 && lastView != null) {
                        val currentBottom = lastView.bottom
                        val targetBottom = viewportHeight - actualBottomPadding
                        if (currentBottom > targetBottom) {
                            val scrollAmount = currentBottom - targetBottom
                            mRecyclerView.post { mRecyclerView.smoothScrollBy(0, scrollAmount) }
                        }
                    } else {
                        mRecyclerView.post { mRecyclerView.smoothScrollBy(0, viewportHeight) }
                    }
                }
                onTap("right")
            }
            TapZone.MIDDLE -> { /* handled by gesture detector */ }
        }
    }

    private fun getCurrentCenteredPage(): Int {
        val pageHeight = getPageHeight()
        if (pageHeight <= 0) return 0
        val viewportCenterY = mRecyclerView.computeVerticalScrollOffset() + height / 2
        return (viewportCenterY / pageHeight).coerceIn(0, mActualPageCount - 1)
    }

    private fun scrollToCenteredPage(targetPage: Int) {
        val page = targetPage.coerceIn(0, mActualPageCount - 1)
        val pageHeight = getPageHeight()
        if (pageHeight <= 0) return

        val pageCenterY = page * pageHeight + pageHeight / 2
        val targetOffset = pageCenterY - height / 2
        val currentScroll = mRecyclerView.computeVerticalScrollOffset()

        val maxScroll = mActualPageCount * pageHeight - height + mRecyclerView.paddingTop + mRecyclerView.paddingBottom
        val clampedOffset = targetOffset.coerceIn(-mRecyclerView.paddingTop, maxScroll.coerceAtLeast(0))
        val scrollBy = clampedOffset - currentScroll

        mRecyclerView.post { mRecyclerView.smoothScrollBy(0, scrollBy) }
    }

    // MARK: - Page Tracking

    private fun updateCurrentPage() {
        val layoutManager = mRecyclerView.layoutManager as? LinearLayoutManager ?: return
        val firstVisible = layoutManager.findFirstVisibleItemPosition()
        val lastVisible = layoutManager.findLastVisibleItemPosition()

        if (firstVisible == RecyclerView.NO_POSITION) return

        val centerPosition = (firstVisible + lastVisible) / 2
        val newPage = centerPosition.coerceIn(0, mActualPageCount - 1)

        if (newPage != mCurrentPage) {
            mCurrentPage = newPage
            onPageChange()
        }
    }

    // MARK: - Zoom Animation

    private fun animateZoomTo(targetScale: Float, targetOffsetX: Float, contentY: Float = 0f, tapY: Float = 0f, duration: Long = 300L) {
        zoomAnimator?.cancel()

        val startScale = mScale
        val startOffsetX = mOffsetX
        val startPivotY = mPivotY
        val hasScrollTarget = tapY != 0f || contentY != 0f

        zoomAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            this.duration = duration
            interpolator = DecelerateInterpolator()
            addUpdateListener { animator ->
                val fraction = animator.animatedValue as Float
                mScale = startScale + (targetScale - startScale) * fraction
                mOffsetX = startOffsetX + (targetOffsetX - startOffsetX) * fraction
                mPivotY = startPivotY + (tapY - startPivotY) * fraction

                applyTransform()

                if (hasScrollTarget) {
                    // Recompute correct scroll for current scale/padding to keep tap point stable
                    val currentPaddingTop = mRecyclerView.paddingTop
                    val targetScrollY = (contentY + currentPaddingTop - tapY / mScale).toInt().coerceAtLeast(0)
                    val currentScrollY = mRecyclerView.computeVerticalScrollOffset()
                    val delta = targetScrollY - currentScrollY
                    if (delta != 0) {
                        mRecyclerView.scrollBy(0, delta)
                    }
                }

                onZoomChange(mScale)
            }
            start()
        }
    }

    // MARK: - Layout

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)

        if (w != mPreviousWidth && mPreviousWidth > 0 && mActualPageCount > 0) {
            mImageCache.evictAll()
            mScale = mMinScale
            mOffsetX = 0f
            mOffsetY = 0f
            mPivotY = 0f
            applyTransform()
            mAdapter.notifyDataSetChanged()
            updateDrawingOverlay()
        }
        mPreviousWidth = w
    }

    override fun onDetachedFromWindow() {
        zoomAnimator?.cancel()
        super.onDetachedFromWindow()
    }

    // MARK: - Public Commands

    override fun resetZoom() {
        animateZoomTo(mMinScale, 0f)
    }

    override fun scrollToPage(page: Int, animated: Boolean) {
        if (page < 0 || page >= mActualPageCount) return

        val layoutManager = mRecyclerView.layoutManager as? LinearLayoutManager ?: return
        if (animated) {
            mRecyclerView.smoothScrollToPosition(page)
        } else {
            layoutManager.scrollToPositionWithOffset(page, 0)
        }
    }

    // MARK: - Adapter

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

            val params = holder.imageView.layoutParams as RecyclerView.LayoutParams
            params.bottomMargin = 0

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
                            holder.imageView.setImageBitmap(it)
                        }
                    }
                }
            }
        }
    }

    private class PdfPageViewHolder(val imageView: ImageView) : RecyclerView.ViewHolder(imageView)
}
