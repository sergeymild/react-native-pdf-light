import React, { useCallback, useRef, useImperativeHandle, forwardRef } from 'react';
import { findNodeHandle, requireNativeComponent, UIManager } from 'react-native';
import { DEFAULT_DRAWING_TOOL } from './drawing/types';
import { asPath } from './Util';

// --- Event types ---

// --- Native Props ---

// --- Public Props ---

// --- Ref type ---

// --- Native component ---

const RNDrawablePdfView = requireNativeComponent('RNDrawablePdfView');

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
export const NativeDrawablePdfView = /*#__PURE__*/forwardRef(function NativeDrawablePdfView(props, ref) {
  const {
    source,
    page,
    resizeMode,
    annotationStr,
    annotation,
    drawingMode = 'view',
    drawingTool = DEFAULT_DRAWING_TOOL,
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
  const viewRef = useRef(null);

  // Expose imperative methods
  useImperativeHandle(ref, () => ({
    clearStrokes: () => {
      if (viewRef.current) {
        const handle = findNodeHandle(viewRef.current);
        if (handle) {
          UIManager.dispatchViewManagerCommand(handle, 'clearStrokes', []);
        }
      }
    },
    resetZoom: () => {
      if (viewRef.current) {
        const handle = findNodeHandle(viewRef.current);
        if (handle) {
          UIManager.dispatchViewManagerCommand(handle, 'resetZoom', []);
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
  const handleDrawingStart = useCallback(_event => {
    onDrawingStart === null || onDrawingStart === void 0 || onDrawingStart();
  }, [onDrawingStart]);
  const handleDrawingEnd = useCallback(_event => {
    onDrawingEnd === null || onDrawingEnd === void 0 || onDrawingEnd();
  }, [onDrawingEnd]);
  const handleStrokeEnd = useCallback(event => {
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
  const handleStrokeRemoved = useCallback(event => {
    onStrokeRemoved === null || onStrokeRemoved === void 0 || onStrokeRemoved(event.nativeEvent.id);
  }, [onStrokeRemoved]);
  const handleStrokesCleared = useCallback(_event => {
    onStrokesCleared === null || onStrokesCleared === void 0 || onStrokesCleared();
  }, [onStrokesCleared]);
  const handleZoomChange = useCallback(event => {
    onZoomChange === null || onZoomChange === void 0 || onZoomChange(event.nativeEvent);
  }, [onZoomChange]);
  const handleZoomPanStart = useCallback(_event => {
    onZoomPanStart === null || onZoomPanStart === void 0 || onZoomPanStart();
  }, [onZoomPanStart]);
  const handleZoomPanEnd = useCallback(_event => {
    onZoomPanEnd === null || onZoomPanEnd === void 0 || onZoomPanEnd();
  }, [onZoomPanEnd]);
  const handleSingleTap = useCallback(_event => {
    onSingleTap === null || onSingleTap === void 0 || onSingleTap();
  }, [onSingleTap]);
  return /*#__PURE__*/React.createElement(RNDrawablePdfView, {
    ref: viewRef,
    source: asPath(source),
    page: page,
    resizeMode: resizeMode,
    annotation: asPath(annotation),
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