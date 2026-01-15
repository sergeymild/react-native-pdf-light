function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
import React, { forwardRef } from 'react';
import { NativePagingPdfView } from './NativePagingPdfView';
import { NativeZoomablePdfScrollView } from './NativeZoomablePdfScrollView';

// --- Unified Event Types ---

// --- Common Props ---

// --- Viewer-specific Props ---

export const PdfViewer = /*#__PURE__*/forwardRef((props, ref) => {
  const {
    viewerType,
    ...rest
  } = props;
  if (viewerType === 'zoomable') {
    return /*#__PURE__*/React.createElement(NativeZoomablePdfScrollView, _extends({}, rest, {
      ref: ref
    }));
  }
  return /*#__PURE__*/React.createElement(NativePagingPdfView, _extends({}, rest, {
    ref: ref
  }));
});
//# sourceMappingURL=PdfViewer.js.map