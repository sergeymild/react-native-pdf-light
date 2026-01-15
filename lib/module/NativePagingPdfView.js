import React, { useCallback, useRef, useImperativeHandle, forwardRef } from 'react';
import { findNodeHandle, NativeModules, processColor, requireNativeComponent, UIManager } from 'react-native';
import { DEFAULT_DRAWING_TOOL } from './drawing/types';
import { asPath } from './Util';

// --- Event types ---

// --- Annotation Types ---

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
    annotations,
    minZoom = 1,
    maxZoom = 3,
    edgeTapZone = 15,
    backgroundColor,
    drawingMode = 'view',
    drawingTool = DEFAULT_DRAWING_TOOL,
    onError,
    onLayout,
    onLoadComplete,
    onPageChange,
    onZoomChange,
    onTap,
    onMiddleClick,
    onDrawingStart,
    onDrawingEnd,
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
    },
    clearStrokes: (page = -1) => {
      if (viewRef.current) {
        const handle = findNodeHandle(viewRef.current);
        if (handle) {
          UIManager.dispatchViewManagerCommand(handle, 'clearStrokes', [page]);
        }
      }
    },
    getAnnotations: async () => {
      if (viewRef.current) {
        const handle = findNodeHandle(viewRef.current);
        if (handle) {
          const manager = NativeModules.RNPagingPdfView;
          if (manager !== null && manager !== void 0 && manager.getAnnotations) {
            return manager.getAnnotations(handle);
          }
        }
      }
      return {};
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
  const handleDrawingStart = useCallback(_event => {
    onDrawingStart === null || onDrawingStart === void 0 || onDrawingStart();
  }, [onDrawingStart]);
  const handleDrawingEnd = useCallback(_event => {
    onDrawingEnd === null || onDrawingEnd === void 0 || onDrawingEnd();
  }, [onDrawingEnd]);
  return /*#__PURE__*/React.createElement(RNPagingPdfView, {
    ref: viewRef,
    source: asPath(source),
    annotations: annotations ? JSON.stringify(annotations) : undefined,
    minZoom: minZoom,
    maxZoom: maxZoom,
    edgeTapZone: Math.max(0, Math.min(50, edgeTapZone)),
    pdfBackgroundColor: backgroundColor ? processColor(backgroundColor) : undefined,
    drawingMode: drawingMode,
    strokeColor: drawingTool.color,
    strokeWidth: drawingTool.strokeWidth,
    strokeOpacity: drawingTool.opacity,
    onLayout: onLayout,
    onPdfError: handlePdfError,
    onPdfLoadComplete: handlePdfLoadComplete,
    onPageChange: handlePageChange,
    onZoomChange: handleZoomChange,
    onTap: handleTap,
    onMiddleClick: handleMiddleClick,
    onDrawingStart: handleDrawingStart,
    onDrawingEnd: handleDrawingEnd,
    style: style
  });
});
//# sourceMappingURL=NativePagingPdfView.js.map