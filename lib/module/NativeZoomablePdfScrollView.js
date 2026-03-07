import React, { useCallback, useRef, useImperativeHandle, forwardRef } from 'react';
import { findNodeHandle, processColor, requireNativeComponent, UIManager } from 'react-native';
import { asPath } from './Util';

// --- Event types ---

// --- Native Props ---

// --- Public Props ---

// --- Ref type ---

// --- Native component ---

const RNZoomablePdfScrollView = requireNativeComponent('RNZoomablePdfScrollView');

/**
 * Native scrollable PDF viewer with global zoom support.
 *
 * This component displays all PDF pages in a scrollable list with
 * native UIScrollView zooming on iOS. All pages zoom together as a single unit.
 *
 * Features:
 * - Pinch-to-zoom entire document
 * - Vertical scrolling through pages
 * - Smooth native scrolling and zooming
 *
 * Supported platforms: iOS
 */
export const NativeZoomablePdfScrollView = /*#__PURE__*/forwardRef(function NativeZoomablePdfScrollView(props, ref) {
  const {
    source,
    minZoom = 1,
    maxZoom = 3,
    edgeTapZone = 15,
    pdfPaddingTop = 0,
    pdfPaddingBottom = 0,
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
  const viewRef = useRef(null);

  // Expose imperative methods
  useImperativeHandle(ref, () => ({
    resetZoom: () => {
      if (viewRef.current) {
        const handle = findNodeHandle(viewRef.current);
        if (handle) {
          UIManager.dispatchViewManagerCommand(handle, 'resetZoom', []);
        }
      }
    },
    scrollToPage: (page, animated = true) => {
      if (viewRef.current) {
        const handle = findNodeHandle(viewRef.current);
        if (handle) {
          UIManager.dispatchViewManagerCommand(handle, 'scrollToPage', [page, animated]);
        }
      }
    }
  }));

  // Event handlers
  const handlePdfError = useCallback(event => {
    onError === null || onError === void 0 || onError(event.nativeEvent);
  }, [onError]);
  const handlePdfLoadComplete = useCallback(event => {
    onLoadComplete === null || onLoadComplete === void 0 || onLoadComplete(event.nativeEvent);
  }, [onLoadComplete]);
  const handlePageChange = useCallback(event => {
    onPageChange === null || onPageChange === void 0 || onPageChange(event.nativeEvent.page);
  }, [onPageChange]);
  const handleZoomChange = useCallback(event => {
    onZoomChange === null || onZoomChange === void 0 || onZoomChange(event.nativeEvent.scale);
  }, [onZoomChange]);
  const handleTap = useCallback(event => {
    onTap === null || onTap === void 0 || onTap(event.nativeEvent.position);
  }, [onTap]);
  const handleMiddleClick = useCallback(() => {
    onMiddleClick === null || onMiddleClick === void 0 || onMiddleClick();
  }, [onMiddleClick]);
  return /*#__PURE__*/React.createElement(RNZoomablePdfScrollView, {
    ref: viewRef,
    source: asPath(source),
    minZoom: minZoom,
    maxZoom: maxZoom,
    edgeTapZone: Math.max(0, Math.min(50, edgeTapZone)),
    pdfPaddingTop: Math.max(0, pdfPaddingTop),
    pdfPaddingBottom: Math.max(0, pdfPaddingBottom),
    pdfBackgroundColor: backgroundColor ? processColor(backgroundColor) : undefined,
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
//# sourceMappingURL=NativeZoomablePdfScrollView.js.map