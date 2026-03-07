import React, { useCallback, useRef, useImperativeHandle, forwardRef } from 'react';
import { findNodeHandle, processColor, requireNativeComponent, UIManager } from 'react-native';
import { asPath } from './Util';

// --- Event types ---

// --- Native Props ---

// --- Public Props ---

// --- Ref type ---

// --- Native component ---

const RNPagingPdfView = requireNativeComponent('RNPagingPdfView');

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
export const NativePagingPdfView = /*#__PURE__*/forwardRef(function NativePagingPdfView(props, ref) {
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
  return /*#__PURE__*/React.createElement(RNPagingPdfView, {
    ref: viewRef,
    source: asPath(source),
    minZoom: minZoom,
    maxZoom: maxZoom,
    edgeTapZone: Math.max(0, Math.min(50, edgeTapZone)),
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
//# sourceMappingURL=NativePagingPdfView.js.map