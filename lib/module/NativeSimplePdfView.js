import React, { useCallback, useRef, useImperativeHandle, forwardRef } from 'react';
import { findNodeHandle, requireNativeComponent, UIManager } from 'react-native';
import { asPath } from './Util';

// --- Event types ---

// --- Native Props ---

// --- Public Props ---

// --- Ref type ---

// --- Native component ---

const RNSimplePdfView = requireNativeComponent('RNSimplePdfView');

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
export const NativeSimplePdfView = /*#__PURE__*/forwardRef(function NativeSimplePdfView(props, ref) {
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
    }
  }));

  // Event handlers
  const handlePdfError = useCallback(event => {
    onError === null || onError === void 0 || onError(event.nativeEvent);
  }, [onError]);
  const handlePdfLoadComplete = useCallback(event => {
    onLoadComplete === null || onLoadComplete === void 0 || onLoadComplete(event.nativeEvent);
  }, [onLoadComplete]);
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
  return /*#__PURE__*/React.createElement(RNSimplePdfView, {
    ref: viewRef,
    source: asPath(source),
    page: page,
    resizeMode: resizeMode,
    annotation: asPath(annotation),
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