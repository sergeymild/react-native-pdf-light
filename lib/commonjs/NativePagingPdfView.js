"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.NativePagingPdfView = void 0;
var _react = _interopRequireWildcard(require("react"));
var _reactNative = require("react-native");
var _Util = require("./Util");
function _interopRequireWildcard(e, t) { if ("function" == typeof WeakMap) var r = new WeakMap(), n = new WeakMap(); return (_interopRequireWildcard = function (e, t) { if (!t && e && e.__esModule) return e; var o, i, f = { __proto__: null, default: e }; if (null === e || "object" != typeof e && "function" != typeof e) return f; if (o = t ? n : r) { if (o.has(e)) return o.get(e); o.set(e, f); } for (const t in e) "default" !== t && {}.hasOwnProperty.call(e, t) && ((i = (o = Object.defineProperty) && Object.getOwnPropertyDescriptor(e, t)) && (i.get || i.set) ? o(f, t, i) : f[t] = e[t]); return f; })(e, t); }
// --- Event types ---

// --- Native Props ---

// --- Public Props ---

// --- Ref type ---

// --- Native component ---

const RNPagingPdfView = (0, _reactNative.requireNativeComponent)('RNPagingPdfView');

/**
 * Native paged PDF viewer with per-page zoom support.
 *
 * This component displays PDF pages one at a time with horizontal swiping
 * between pages. Each page can be zoomed independently.
 *
 * Features:
 * - Horizontal page swiping (like a book)
 * - Per-page pinch-to-zoom
 * - Page swiping is disabled while zoomed in
 * - Double-tap to zoom in/out
 *
 * Supported platforms: iOS, Android
 */
const NativePagingPdfView = exports.NativePagingPdfView = /*#__PURE__*/(0, _react.forwardRef)(function NativePagingPdfView(props, ref) {
  const {
    source,
    minZoom = 1,
    maxZoom = 3,
    edgeTapZone = 15,
    backgroundColor,
    onError,
    onLayout,
    onLoadComplete,
    onPageChange,
    onZoomChange,
    onTap,
    onMiddleClick,
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
    },
    scrollToPage: (page, animated = true) => {
      if (viewRef.current) {
        const handle = (0, _reactNative.findNodeHandle)(viewRef.current);
        if (handle) {
          _reactNative.UIManager.dispatchViewManagerCommand(handle, 'scrollToPage', [page, animated]);
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
  const handlePageChange = (0, _react.useCallback)(event => {
    onPageChange === null || onPageChange === void 0 || onPageChange(event.nativeEvent.page);
  }, [onPageChange]);
  const handleZoomChange = (0, _react.useCallback)(event => {
    onZoomChange === null || onZoomChange === void 0 || onZoomChange(event.nativeEvent.scale);
  }, [onZoomChange]);
  const handleTap = (0, _react.useCallback)(event => {
    onTap === null || onTap === void 0 || onTap(event.nativeEvent.position);
  }, [onTap]);
  const handleMiddleClick = (0, _react.useCallback)(() => {
    onMiddleClick === null || onMiddleClick === void 0 || onMiddleClick();
  }, [onMiddleClick]);
  return /*#__PURE__*/_react.default.createElement(RNPagingPdfView, {
    ref: viewRef,
    source: (0, _Util.asPath)(source),
    minZoom: minZoom,
    maxZoom: maxZoom,
    edgeTapZone: Math.max(0, Math.min(50, edgeTapZone)),
    pdfBackgroundColor: backgroundColor ? (0, _reactNative.processColor)(backgroundColor) : undefined,
    onLayout: onLayout,
    onPdfError: handlePdfError,
    onPdfLoadComplete: handlePdfLoadComplete,
    onPageChange: handlePageChange,
    onZoomChange: handleZoomChange,
    onTap: handleTap,
    onMiddleClick: handleMiddleClick,
    style: style
  });
});
//# sourceMappingURL=NativePagingPdfView.js.map