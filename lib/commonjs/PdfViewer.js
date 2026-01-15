"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.PdfViewer = void 0;
var _react = _interopRequireWildcard(require("react"));
var _NativePagingPdfView = require("./NativePagingPdfView");
var _NativeZoomablePdfScrollView = require("./NativeZoomablePdfScrollView");
function _interopRequireWildcard(e, t) { if ("function" == typeof WeakMap) var r = new WeakMap(), n = new WeakMap(); return (_interopRequireWildcard = function (e, t) { if (!t && e && e.__esModule) return e; var o, i, f = { __proto__: null, default: e }; if (null === e || "object" != typeof e && "function" != typeof e) return f; if (o = t ? n : r) { if (o.has(e)) return o.get(e); o.set(e, f); } for (const t in e) "default" !== t && {}.hasOwnProperty.call(e, t) && ((i = (o = Object.defineProperty) && Object.getOwnPropertyDescriptor(e, t)) && (i.get || i.set) ? o(f, t, i) : f[t] = e[t]); return f; })(e, t); }
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
// --- Unified Event Types ---

// --- Common Props ---

// --- Viewer-specific Props ---

const PdfViewer = exports.PdfViewer = /*#__PURE__*/(0, _react.forwardRef)((props, ref) => {
  const {
    viewerType,
    ...rest
  } = props;
  if (viewerType === 'zoomable') {
    return /*#__PURE__*/_react.default.createElement(_NativeZoomablePdfScrollView.NativeZoomablePdfScrollView, _extends({}, rest, {
      ref: ref
    }));
  }
  return /*#__PURE__*/_react.default.createElement(_NativePagingPdfView.NativePagingPdfView, _extends({}, rest, {
    ref: ref
  }));
});
//# sourceMappingURL=PdfViewer.js.map