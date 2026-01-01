package com.alpha0010.pdf

import com.facebook.react.bridge.ReadableArray
import com.facebook.react.common.MapBuilder
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.annotations.ReactProp
import java.util.concurrent.locks.Lock

class ZoomablePdfScrollViewManager(private val pdfMutex: Lock) : SimpleViewManager<ZoomablePdfScrollView>() {

    override fun getName(): String {
        return "RNZoomablePdfScrollView"
    }

    override fun createViewInstance(context: ThemedReactContext): ZoomablePdfScrollView {
        return ZoomablePdfScrollView(context, pdfMutex)
    }

    @ReactProp(name = "source")
    fun setSource(view: ZoomablePdfScrollView, source: String?) {
        view.setSource(source ?: "")
    }

    @ReactProp(name = "annotations")
    fun setAnnotations(view: ZoomablePdfScrollView, annotations: String?) {
        view.setAnnotations(annotations)
    }

    @ReactProp(name = "minZoom")
    fun setMinZoom(view: ZoomablePdfScrollView, minZoom: Float) {
        view.setMinZoom(minZoom)
    }

    @ReactProp(name = "maxZoom")
    fun setMaxZoom(view: ZoomablePdfScrollView, maxZoom: Float) {
        view.setMaxZoom(maxZoom)
    }

    @ReactProp(name = "edgeTapZone")
    fun setEdgeTapZone(view: ZoomablePdfScrollView, zone: Float) {
        view.setEdgeTapZone(zone)
    }

    @ReactProp(name = "pdfPaddingTop")
    fun setPdfPaddingTop(view: ZoomablePdfScrollView, padding: Float) {
        view.setPdfPaddingTop(padding)
    }

    @ReactProp(name = "pdfPaddingBottom")
    fun setPdfPaddingBottom(view: ZoomablePdfScrollView, padding: Float) {
        view.setPdfPaddingBottom(padding)
    }

    @ReactProp(name = "pdfBackgroundColor", customType = "Color")
    fun setPdfBackgroundColor(view: ZoomablePdfScrollView, color: Int?) {
        if (color != null) {
            view.setPdfBackgroundColor(color)
        }
    }

    override fun getExportedCustomBubblingEventTypeConstants(): Map<String, Any> {
        return MapBuilder.builder<String, Any>()
            .put("onPdfError", MapBuilder.of("phasedRegistrationNames", MapBuilder.of("bubbled", "onPdfError")))
            .put("onPdfLoadComplete", MapBuilder.of("phasedRegistrationNames", MapBuilder.of("bubbled", "onPdfLoadComplete")))
            .put("onPageChange", MapBuilder.of("phasedRegistrationNames", MapBuilder.of("bubbled", "onPageChange")))
            .put("onZoomChange", MapBuilder.of("phasedRegistrationNames", MapBuilder.of("bubbled", "onZoomChange")))
            .put("onTap", MapBuilder.of("phasedRegistrationNames", MapBuilder.of("bubbled", "onTap")))
            .put("onMiddleClick", MapBuilder.of("phasedRegistrationNames", MapBuilder.of("bubbled", "onMiddleClick")))
            .build()
    }

    override fun getCommandsMap(): Map<String, Int> {
        return MapBuilder.of(
            "resetZoom", COMMAND_RESET_ZOOM,
            "scrollToPage", COMMAND_SCROLL_TO_PAGE
        )
    }

    override fun receiveCommand(view: ZoomablePdfScrollView, commandId: String?, args: ReadableArray?) {
        when (commandId) {
            "resetZoom" -> view.resetZoom()
            "scrollToPage" -> {
                val page = args?.getInt(0) ?: 0
                val animated = args?.getBoolean(1) ?: true
                view.scrollToPage(page, animated)
            }
        }
    }

    companion object {
        private const val COMMAND_RESET_ZOOM = 1
        private const val COMMAND_SCROLL_TO_PAGE = 2
    }
}
