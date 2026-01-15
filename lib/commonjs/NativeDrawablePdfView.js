"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.NativeDrawablePdfView = void 0;
var _react = _interopRequireWildcard(require("react"));
var _reactNative = require("react-native");
var _types = require("./drawing/types");
var _Util = require("./Util");
function _interopRequireWildcard(e, t) { if ("function" == typeof WeakMap) var r = new WeakMap(), n = new WeakMap(); return (_interopRequireWildcard = function (e, t) { if (!t && e && e.__esModule) return e; var o, i, f = { __proto__: null, default: e }; if (null === e || "object" != typeof e && "function" != typeof e) return f; if (o = t ? n : r) { if (o.has(e)) return o.get(e); o.set(e, f); } for (const t in e) "default" !== t && {}.hasOwnProperty.call(e, t) && ((i = (o = Object.defineProperty) && Object.getOwnPropertyDescriptor(e, t)) && (i.get || i.set) ? o(f, t, i) : f[t] = e[t]); return f; })(e, t); }
// --- Event types ---

// --- Native Props ---

// --- Public Props ---

// --- Ref type ---

// --- Native component ---

const RNDrawablePdfView = (0, _reactNative.requireNativeComponent)('RNDrawablePdfView');

/**
 * Convert DrawingStroke[] to JSON string for native component.
 */
function strokesToJson(strokes) {
  if (strokes.length === 0) return '';
  return JSON.stringify(strokes);
}

/**
 * Native PDF view with drawing and zoom support.
 *
 * This component renders PDF with native drawing and pinch-to-zoom capabilities.
 * Touch events for drawing and zooming are handled natively for better performance.
 *
 * Features:
 * - Pinch-to-zoom with configurable min/max
 * - Double-tap to zoom in/reset
 * - Pan when zoomed in
 * - Drawing with pen and highlighter
 * - Eraser tool
 *
 * Supported platforms: Android, iOS
 */
const NativeDrawablePdfView = exports.NativeDrawablePdfView = /*#__PURE__*/(0, _react.forwardRef)(function NativeDrawablePdfView(props, ref) {
  const {
    source,
    page,
    resizeMode,
    annotationStr,
    annotation,
    drawingMode = 'view',
    drawingTool = _types.DEFAULT_DRAWING_TOOL,
    strokes = [],
    minZoom = 1,
    maxZoom = 3,
    zoomEnabled = true,
    onError,
    onLayout,
    onLoadComplete,
    onDrawingStart,
    onDrawingEnd,
    onStrokeEnd,
    onStrokeRemoved,
    onStrokesCleared,
    onZoomChange,
    onZoomPanStart,
    onZoomPanEnd,
    onSingleTap,
    style
  } = props;
  const viewRef = (0, _react.useRef)(null);

  // Expose imperative methods
  (0, _react.useImperativeHandle)(ref, () => ({
    clearStrokes: () => {
      if (viewRef.current) {
        const handle = (0, _reactNative.findNodeHandle)(viewRef.current);
        if (handle) {
          _reactNative.UIManager.dispatchViewManagerCommand(handle, 'clearStrokes', []);
        }
      }
    },
    resetZoom: () => {
      if (viewRef.current) {
        const handle = (0, _reactNative.findNodeHandle)(viewRef.current);
        if (handle) {
          _reactNative.UIManager.dispatchViewManagerCommand(handle, 'resetZoom', []);
        }
      }
    }
  }));

  // Event handlers
  const handlePdfError = (0, _react.useCallback)(event => {
    onError === null || onError === void 0 || onError(event.nativeEvent);
  }, [onError]);
  const handlePdfLoadComplete = (0, _react.useCallback)(event => {
    onLoadComplete === null || onLoadComplete === void 0 || onLoadComplete(event.nativeEvent);
  }, [onLoadComplete]);
  const handleDrawingStart = (0, _react.useCallback)(_event => {
    onDrawingStart === null || onDrawingStart === void 0 || onDrawingStart();
  }, [onDrawingStart]);
  const handleDrawingEnd = (0, _react.useCallback)(_event => {
    onDrawingEnd === null || onDrawingEnd === void 0 || onDrawingEnd();
  }, [onDrawingEnd]);
  const handleStrokeEnd = (0, _react.useCallback)(event => {
    const {
      id,
      color,
      width,
      opacity,
      path
    } = event.nativeEvent;
    onStrokeEnd === null || onStrokeEnd === void 0 || onStrokeEnd({
      id,
      color,
      width,
      opacity,
      path
    });
  }, [onStrokeEnd]);
  const handleStrokeRemoved = (0, _react.useCallback)(event => {
    onStrokeRemoved === null || onStrokeRemoved === void 0 || onStrokeRemoved(event.nativeEvent.id);
  }, [onStrokeRemoved]);
  const handleStrokesCleared = (0, _react.useCallback)(_event => {
    onStrokesCleared === null || onStrokesCleared === void 0 || onStrokesCleared();
  }, [onStrokesCleared]);
  const handleZoomChange = (0, _react.useCallback)(event => {
    onZoomChange === null || onZoomChange === void 0 || onZoomChange(event.nativeEvent);
  }, [onZoomChange]);
  const handleZoomPanStart = (0, _react.useCallback)(_event => {
    onZoomPanStart === null || onZoomPanStart === void 0 || onZoomPanStart();
  }, [onZoomPanStart]);
  const handleZoomPanEnd = (0, _react.useCallback)(_event => {
    onZoomPanEnd === null || onZoomPanEnd === void 0 || onZoomPanEnd();
  }, [onZoomPanEnd]);
  const handleSingleTap = (0, _react.useCallback)(_event => {
    onSingleTap === null || onSingleTap === void 0 || onSingleTap();
  }, [onSingleTap]);
  return /*#__PURE__*/_react.default.createElement(RNDrawablePdfView, {
    ref: viewRef,
    source: (0, _Util.asPath)(source),
    page: page,
    resizeMode: resizeMode,
    annotation: (0, _Util.asPath)(annotation),
    annotationStr: annotationStr,
    drawingMode: drawingMode,
    strokeColor: drawingTool.color,
    strokeWidth: drawingTool.strokeWidth,
    strokeOpacity: drawingTool.opacity,
    strokes: strokesToJson(strokes),
    minZoom: minZoom,
    maxZoom: maxZoom,
    zoomEnabled: zoomEnabled,
    onLayout: onLayout,
    onPdfError: handlePdfError,
    onPdfLoadComplete: handlePdfLoadComplete,
    onDrawingStart: handleDrawingStart,
    onDrawingEnd: handleDrawingEnd,
    onStrokeEnd: handleStrokeEnd,
    onStrokeRemoved: handleStrokeRemoved,
    onStrokesCleared: handleStrokesCleared,
    onZoomChange: handleZoomChange,
    onZoomPanStart: handleZoomPanStart,
    onZoomPanEnd: handleZoomPanEnd,
    onSingleTap: handleSingleTap,
    style: style
  });
});
//# sourceMappingURL=NativeDrawablePdfView.js.map