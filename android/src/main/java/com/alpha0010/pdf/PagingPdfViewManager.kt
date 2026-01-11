package com.alpha0010.pdf

import com.facebook.react.bridge.ReadableArray
import com.facebook.react.common.MapBuilder
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.annotations.ReactProp
import java.util.concurrent.locks.Lock

class PagingPdfViewManager(private val pdfMutex: Lock) : SimpleViewManager<PagingPdfView>() {

    override fun getName(): String {
        return "RNPagingPdfView"
    }

    override fun createViewInstance(context: ThemedReactContext): PagingPdfView {
        return PagingPdfView(context, pdfMutex)
    }

    @ReactProp(name = "source")
    fun setSource(view: PagingPdfView, source: String?) {
        view.setSource(source ?: "")
    }

    @ReactProp(name = "annotations")
    fun setAnnotations(view: PagingPdfView, annotations: String?) {
        view.setAnnotations(annotations)
    }

    @ReactProp(name = "minZoom")
    fun setMinZoom(view: PagingPdfView, minZoom: Float) {
        view.setMinZoom(minZoom)
    }

    @ReactProp(name = "maxZoom")
    fun setMaxZoom(view: PagingPdfView, maxZoom: Float) {
        view.setMaxZoom(maxZoom)
    }

    @ReactProp(name = "edgeTapZone")
    fun setEdgeTapZone(view: PagingPdfView, zone: Float) {
        view.setEdgeTapZone(zone)
    }

    @ReactProp(name = "pdfBackgroundColor", customType = "Color")
    fun setPdfBackgroundColor(view: PagingPdfView, color: Int?) {
        if (color != null) {
            view.setPdfBackgroundColor(color)
        }
    }

    // --- Drawing props ---

    @ReactProp(name = "drawingMode")
    fun setDrawingMode(view: PagingPdfView, mode: String?) {
        view.setDrawingMode(mode ?: "view")
    }

    @ReactProp(name = "strokeColor")
    fun setStrokeColor(view: PagingPdfView, color: String?) {
        view.setStrokeColor(color ?: "#000000")
    }

    @ReactProp(name = "strokeWidth")
    fun setStrokeWidth(view: PagingPdfView, width: Float) {
        view.setStrokeWidth(width)
    }

    @ReactProp(name = "strokeOpacity")
    fun setStrokeOpacity(view: PagingPdfView, opacity: Float) {
        view.setStrokeOpacity(opacity)
    }

    override fun getExportedCustomBubblingEventTypeConstants(): Map<String, Any> {
        return MapBuilder.builder<String, Any>()
            .put("onPdfError", MapBuilder.of("phasedRegistrationNames", MapBuilder.of("bubbled", "onPdfError")))
            .put("onPdfLoadComplete", MapBuilder.of("phasedRegistrationNames", MapBuilder.of("bubbled", "onPdfLoadComplete")))
            .put("onPageChange", MapBuilder.of("phasedRegistrationNames", MapBuilder.of("bubbled", "onPageChange")))
            .put("onZoomChange", MapBuilder.of("phasedRegistrationNames", MapBuilder.of("bubbled", "onZoomChange")))
            .put("onTap", MapBuilder.of("phasedRegistrationNames", MapBuilder.of("bubbled", "onTap")))
            .put("onMiddleClick", MapBuilder.of("phasedRegistrationNames", MapBuilder.of("bubbled", "onMiddleClick")))
            .put("onDrawingStart", MapBuilder.of("phasedRegistrationNames", MapBuilder.of("bubbled", "onDrawingStart")))
            .put("onDrawingEnd", MapBuilder.of("phasedRegistrationNames", MapBuilder.of("bubbled", "onDrawingEnd")))
            .build()
    }

    override fun getCommandsMap(): Map<String, Int> {
        return MapBuilder.of(
            "resetZoom", COMMAND_RESET_ZOOM,
            "scrollToPage", COMMAND_SCROLL_TO_PAGE,
            "clearStrokes", COMMAND_CLEAR_STROKES
        )
    }

    override fun receiveCommand(view: PagingPdfView, commandId: String?, args: ReadableArray?) {
        when (commandId) {
            "resetZoom" -> view.resetZoom()
            "scrollToPage" -> {
                val page = args?.getInt(0) ?: 0
                val animated = args?.getBoolean(1) ?: true
                view.scrollToPage(page, animated)
            }
            "clearStrokes" -> {
                val page = args?.getInt(0) ?: -1
                view.clearStrokes(page)
            }
        }
    }

    fun getAnnotations(view: PagingPdfView): com.facebook.react.bridge.WritableMap {
        return view.getAnnotations()
    }

    companion object {
        private const val COMMAND_RESET_ZOOM = 1
        private const val COMMAND_SCROLL_TO_PAGE = 2
        private const val COMMAND_CLEAR_STROKES = 3
    }
}
