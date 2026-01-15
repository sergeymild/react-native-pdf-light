"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.NativeSimplePdfView = void 0;
var _react = _interopRequireWildcard(require("react"));
var _reactNative = require("react-native");
var _Util = require("./Util");
function _interopRequireWildcard(e, t) { if ("function" == typeof WeakMap) var r = new WeakMap(), n = new WeakMap(); return (_interopRequireWildcard = function (e, t) { if (!t && e && e.__esModule) return e; var o, i, f = { __proto__: null, default: e }; if (null === e || "object" != typeof e && "function" != typeof e) return f; if (o = t ? n : r) { if (o.has(e)) return o.get(e); o.set(e, f); } for (const t in e) "default" !== t && {}.hasOwnProperty.call(e, t) && ((i = (o = Object.defineProperty) && Object.getOwnPropertyDescriptor(e, t)) && (i.get || i.set) ? o(f, t, i) : f[t] = e[t]); return f; })(e, t); }
// --- Event types ---

// --- Native Props ---

// --- Public Props ---

// --- Ref type ---

// --- Native component ---

const RNSimplePdfView = (0, _reactNative.requireNativeComponent)('RNSimplePdfView');

/**
 * Lightweight native PDF view with zoom support (no drawing).
 *
 * This component renders PDF with native pinch-to-zoom capabilities.
 * Touch events for zooming are handled natively for better performance.
 *
 * Features:
 * - Pinch-to-zoom with configurable min/max
 * - Double-tap to zoom in/reset
 * - Pan when zoomed in
 * - Annotations rendering
 *
 * Use this component when you don't need drawing capabilities and want
 * a lighter-weight PDF viewer.
 *
 * Supported platforms: Android, iOS
 */
const NativeSimplePdfView = exports.NativeSimplePdfView = /*#__PURE__*/(0, _react.forwardRef)(function NativeSimplePdfView(props, ref) {
  const {
    source,
    page,
    resizeMode,
    annotationStr,
    annotation,
    minZoom = 1,
    maxZoom = 3,
    zoomEnabled = true,
    onError,
    onLayout,
    onLoadComplete,
    onZoomChange,
    onZoomPanStart,
    onZoomPanEnd,
    onSingleTap,
    style
  } = props;
  const viewRef = (0, _react.useRef)(null);

  // Expose imperative methods
  (0, _react.useImperativeHandle)(ref, () => ({
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
  return /*#__PURE__*/_react.default.createElement(RNSimplePdfView, {
    ref: viewRef,
    source: (0, _Util.asPath)(source),
    page: page,
    resizeMode: resizeMode,
    annotation: (0, _Util.asPath)(annotation),
    annotationStr: annotationStr,
    minZoom: minZoom,
    maxZoom: maxZoom,
    zoomEnabled: zoomEnabled,
    onLayout: onLayout,
    onPdfError: handlePdfError,
    onPdfLoadComplete: handlePdfLoadComplete,
    onZoomChange: handleZoomChange,
    onZoomPanStart: handleZoomPanStart,
    onZoomPanEnd: handleZoomPanEnd,
    onSingleTap: handleSingleTap,
    style: style
  });
});
//# sourceMappingURL=NativeSimplePdfView.js.map