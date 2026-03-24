package com.alpha0010.pdf

import com.facebook.react.bridge.ReadableArray
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.annotations.ReactProp
import java.util.concurrent.locks.Lock

class PagingPdfViewManager(private val pdfMutex: Lock) : SimpleViewManager<PagingPdfView>() {

    override fun getName(): String = "RNPagingPdfView"

    override fun createViewInstance(context: ThemedReactContext) = PagingPdfView(context, pdfMutex)

    @ReactProp(name = "source")
    fun setSource(view: PagingPdfView, source: String?) { view.setSource(source ?: "") }

    @ReactProp(name = "annotations")
    fun setAnnotations(view: PagingPdfView, annotations: String?) { view.setAnnotations(annotations) }

    @ReactProp(name = "minZoom")
    fun setMinZoom(view: PagingPdfView, minZoom: Float) { view.setMinZoom(minZoom) }

    @ReactProp(name = "maxZoom")
    fun setMaxZoom(view: PagingPdfView, maxZoom: Float) { view.setMaxZoom(maxZoom) }

    @ReactProp(name = "edgeTapZone")
    fun setEdgeTapZone(view: PagingPdfView, zone: Float) { view.setEdgeTapZone(zone) }

    @ReactProp(name = "pdfBackgroundColor", customType = "Color")
    fun setPdfBackgroundColor(view: PagingPdfView, color: Int?) { if (color != null) view.setPdfBackgroundColor(color) }

    @ReactProp(name = "drawingMode")
    fun setDrawingMode(view: PagingPdfView, mode: String?) { view.setDrawingMode(mode ?: "view") }

    @ReactProp(name = "strokeColor")
    fun setStrokeColor(view: PagingPdfView, color: String?) { view.setStrokeColor(color ?: "#000000") }

    @ReactProp(name = "strokeWidth")
    fun setStrokeWidth(view: PagingPdfView, width: Float) { view.setStrokeWidth(width) }

    @ReactProp(name = "strokeOpacity")
    fun setStrokeOpacity(view: PagingPdfView, opacity: Float) { view.setStrokeOpacity(opacity) }

    @ReactProp(name = "textColor")
    fun setTextColor(view: PagingPdfView, color: String?) { view.setTextColor(color ?: "#0000FF") }

    @ReactProp(name = "textFontSize")
    fun setTextFontSize(view: PagingPdfView, size: Float) { view.setTextFontSize(size) }

    override fun getExportedCustomBubblingEventTypeConstants(): Map<String, Any> = PdfViewerConstants.bubblingEventTypes()

    override fun getCommandsMap(): Map<String, Int> = PdfViewerConstants.commandsMap()

    override fun receiveCommand(view: PagingPdfView, commandId: String?, args: ReadableArray?) {
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
