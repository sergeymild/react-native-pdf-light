package com.alpha0010.pdf

import com.facebook.react.bridge.ReadableArray
import com.facebook.react.common.MapBuilder
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.annotations.ReactProp
import java.util.concurrent.locks.Lock

class DrawablePdfViewManager(private val pdfMutex: Lock) : SimpleViewManager<DrawablePdfView>() {

  override fun getName() = "RNDrawablePdfView"

  override fun createViewInstance(reactContext: ThemedReactContext): DrawablePdfView {
    return DrawablePdfView(reactContext, pdfMutex)
  }

  override fun getExportedCustomBubblingEventTypeConstants(): MutableMap<String, Any> {
    return MapBuilder.builder<String, Any>()
      .put("onPdfError", MapBuilder.of("phasedRegistrationNames", MapBuilder.of("bubbled", "onPdfError")))
      .put("onPdfLoadComplete", MapBuilder.of("phasedRegistrationNames", MapBuilder.of("bubbled", "onPdfLoadComplete")))
      .put("onDrawingStart", MapBuilder.of("phasedRegistrationNames", MapBuilder.of("bubbled", "onDrawingStart")))
      .put("onDrawingEnd", MapBuilder.of("phasedRegistrationNames", MapBuilder.of("bubbled", "onDrawingEnd")))
      .put("onStrokeEnd", MapBuilder.of("phasedRegistrationNames", MapBuilder.of("bubbled", "onStrokeEnd")))
      .put("onStrokeRemoved", MapBuilder.of("phasedRegistrationNames", MapBuilder.of("bubbled", "onStrokeRemoved")))
      .put("onStrokesCleared", MapBuilder.of("phasedRegistrationNames", MapBuilder.of("bubbled", "onStrokesCleared")))
      .put("onZoomChange", MapBuilder.of("phasedRegistrationNames", MapBuilder.of("bubbled", "onZoomChange")))
      .put("onSingleTap", MapBuilder.of("phasedRegistrationNames", MapBuilder.of("bubbled", "onSingleTap")))
      .build()
  }

  override fun onAfterUpdateTransaction(view: DrawablePdfView) {
    super.onAfterUpdateTransaction(view)
    view.renderPdf()
  }

  // --- PDF Props ---

  @ReactProp(name = "source")
  fun setSource(view: DrawablePdfView, source: String?) {
    view.setSource(source ?: "")
  }

  @ReactProp(name = "page", defaultInt = 0)
  fun setPage(view: DrawablePdfView, page: Int) {
    view.setPage(page)
  }

  @ReactProp(name = "resizeMode")
  fun setResizeMode(view: DrawablePdfView, mode: String?) {
    view.setResizeMode(mode ?: ResizeMode.CONTAIN.jsName)
  }

  @ReactProp(name = "annotationStr")
  fun setAnnotationStr(view: DrawablePdfView, source: String?) {
    view.setAnnotation(source ?: "", file = false)
  }

  @ReactProp(name = "annotation")
  fun setAnnotation(view: DrawablePdfView, source: String?) {
    view.setAnnotation(source ?: "", file = true)
  }

  // --- Drawing Props ---

  @ReactProp(name = "drawingMode")
  fun setDrawingMode(view: DrawablePdfView, mode: String?) {
    view.setDrawingMode(mode ?: "view")
  }

  @ReactProp(name = "strokeColor")
  fun setStrokeColor(view: DrawablePdfView, color: String?) {
    view.setStrokeColor(color ?: "#000000")
  }

  @ReactProp(name = "strokeWidth", defaultFloat = 3f)
  fun setStrokeWidth(view: DrawablePdfView, width: Float) {
    view.setStrokeWidth(width)
  }

  @ReactProp(name = "strokeOpacity", defaultFloat = 1f)
  fun setStrokeOpacity(view: DrawablePdfView, opacity: Float) {
    view.setStrokeOpacity(opacity)
  }

  @ReactProp(name = "strokes")
  fun setStrokes(view: DrawablePdfView, strokes: String?) {
    view.setStrokes(strokes ?: "")
  }

  // --- Zoom Props ---

  @ReactProp(name = "minZoom", defaultFloat = 1f)
  fun setMinZoom(view: DrawablePdfView, minZoom: Float) {
    view.setMinZoom(minZoom)
  }

  @ReactProp(name = "maxZoom", defaultFloat = 3f)
  fun setMaxZoom(view: DrawablePdfView, maxZoom: Float) {
    view.setMaxZoom(maxZoom)
  }

  @ReactProp(name = "zoomEnabled", defaultBoolean = true)
  fun setZoomEnabled(view: DrawablePdfView, enabled: Boolean) {
    view.setZoomEnabled(enabled)
  }

  // --- Commands ---

  override fun getCommandsMap(): MutableMap<String, Int> {
    return MapBuilder.of(
      "clearStrokes", COMMAND_CLEAR_STROKES,
      "resetZoom", COMMAND_RESET_ZOOM
    )
  }

  override fun receiveCommand(view: DrawablePdfView, commandId: String?, args: ReadableArray?) {
    when (commandId) {
      "clearStrokes" -> view.clearStrokes()
      "resetZoom" -> view.resetZoom()
    }
  }

  companion object {
    private const val COMMAND_CLEAR_STROKES = 1
    private const val COMMAND_RESET_ZOOM = 2
  }
}