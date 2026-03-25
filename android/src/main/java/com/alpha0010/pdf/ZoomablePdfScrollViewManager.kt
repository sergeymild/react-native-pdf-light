package com.alpha0010.pdf

import com.facebook.react.bridge.ReadableArray
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.annotations.ReactProp
import java.util.concurrent.locks.Lock

class ZoomablePdfScrollViewManager(private val pdfMutex: Lock) : SimpleViewManager<ZoomablePdfScrollView>() {

    override fun getName(): String = "RNZoomablePdfScrollView"

    override fun createViewInstance(context: ThemedReactContext) = ZoomablePdfScrollView(context, pdfMutex)

    @ReactProp(name = "source")
    fun setSource(view: ZoomablePdfScrollView, source: String?) { view.setSource(source ?: "") }

    @ReactProp(name = "annotations")
    fun setAnnotations(view: ZoomablePdfScrollView, annotations: String?) { view.setAnnotations(annotations) }

    @ReactProp(name = "minZoom")
    fun setMinZoom(view: ZoomablePdfScrollView, minZoom: Float) { view.setMinZoom(minZoom) }

    @ReactProp(name = "maxZoom")
    fun setMaxZoom(view: ZoomablePdfScrollView, maxZoom: Float) { view.setMaxZoom(maxZoom) }

    @ReactProp(name = "edgeTapZone")
    fun setEdgeTapZone(view: ZoomablePdfScrollView, zone: Float) { view.setEdgeTapZone(zone) }

    @ReactProp(name = "pdfPaddingTop")
    fun setPdfPaddingTop(view: ZoomablePdfScrollView, padding: Float) { view.setPdfPaddingTop(padding) }

    @ReactProp(name = "pdfPaddingBottom")
    fun setPdfPaddingBottom(view: ZoomablePdfScrollView, padding: Float) { view.setPdfPaddingBottom(padding) }

    @ReactProp(name = "pdfBackgroundColor", customType = "Color")
    fun setPdfBackgroundColor(view: ZoomablePdfScrollView, color: Int?) { if (color != null) view.setPdfBackgroundColor(color) }

    @ReactProp(name = "drawingMode")
    fun setDrawingMode(view: ZoomablePdfScrollView, mode: String?) { view.setDrawingMode(mode ?: "view") }

    @ReactProp(name = "strokeColor")
    fun setStrokeColor(view: ZoomablePdfScrollView, color: String?) { view.setStrokeColor(color ?: "#000000") }

    @ReactProp(name = "strokeWidth")
    fun setStrokeWidth(view: ZoomablePdfScrollView, width: Float) { view.setStrokeWidth(width) }

    @ReactProp(name = "strokeOpacity")
    fun setStrokeOpacity(view: ZoomablePdfScrollView, opacity: Float) { view.setStrokeOpacity(opacity) }

    @ReactProp(name = "textColor")
    fun setTextColor(view: ZoomablePdfScrollView, color: String?) { view.setTextColor(color ?: "#0000FF") }

    @ReactProp(name = "textFontSize")
    fun setTextFontSize(view: ZoomablePdfScrollView, size: Float) { view.setTextFontSize(size) }

    override fun getExportedCustomBubblingEventTypeConstants(): Map<String, Any> = PdfViewerConstants.bubblingEventTypes()

    override fun getCommandsMap(): Map<String, Int> = PdfViewerConstants.commandsMap()

    override fun receiveCommand(view: ZoomablePdfScrollView, commandId: String?, args: ReadableArray?) {
        android.util.Log.d("PdfViewer", "[receiveCommand] commandId=$commandId argsSize=${args?.size()}")
        when (commandId) {
            "resetZoom" -> view.resetZoom()
            "scrollToPage" -> view.scrollToPage(args?.getInt(0) ?: 0, args?.getBoolean(1) ?: true)
            "clearStrokes" -> view.clearStrokes(args?.getInt(0) ?: -1)
            "undo" -> view.undo()
            "redo" -> view.redo()
            "loadAnnotations" -> view.loadAnnotations(args?.getString(0) ?: "")
        }
    }
}
