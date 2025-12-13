import React, { useCallback, useRef, useImperativeHandle, forwardRef } from 'react';
import {
  findNodeHandle,
  LayoutChangeEvent,
  NativeSyntheticEvent,
  requireNativeComponent,
  UIManager,
  ViewStyle,
} from 'react-native';
import type { DrawingMode, DrawingStroke, DrawingTool } from './drawing/types';
import { DEFAULT_DRAWING_TOOL } from './drawing/types';
import { asPath } from './Util';

// --- Event types ---

export type ErrorEvent = { message: string };

export type LoadCompleteEvent = { height: number; width: number };

export type StrokeEndEvent = {
  id: string;
  color: string;
  width: number;
  opacity: number;
  path: [number, number][];
};

export type StrokeRemovedEvent = {
  id: string;
};

export type ZoomChangeEvent = {
  scale: number;
  offsetX: number;
  offsetY: number;
};

// --- Native Props ---

type NativeDrawablePdfViewProps = {
  // PDF props
  source: string;
  page: number;
  resizeMode?: 'contain' | 'fitWidth';
  annotation?: string;
  annotationStr?: string;

  // Drawing props
  drawingMode: string;
  strokeColor: string;
  strokeWidth: number;
  strokeOpacity: number;
  strokes: string;

  // Zoom props
  minZoom: number;
  maxZoom: number;
  zoomEnabled: boolean;

  // Events
  onLayout?: (event: LayoutChangeEvent) => void;
  onPdfError: (event: NativeSyntheticEvent<ErrorEvent>) => void;
  onPdfLoadComplete: (event: NativeSyntheticEvent<LoadCompleteEvent>) => void;
  onDrawingStart: (event: NativeSyntheticEvent<{}>) => void;
  onDrawingEnd: (event: NativeSyntheticEvent<{}>) => void;
  onStrokeEnd: (event: NativeSyntheticEvent<StrokeEndEvent>) => void;
  onStrokeRemoved: (event: NativeSyntheticEvent<StrokeRemovedEvent>) => void;
  onStrokesCleared: (event: NativeSyntheticEvent<{}>) => void;
  onZoomChange: (event: NativeSyntheticEvent<ZoomChangeEvent>) => void;
  onZoomPanStart: (event: NativeSyntheticEvent<{}>) => void;
  onZoomPanEnd: (event: NativeSyntheticEvent<{}>) => void;
  onSingleTap: (event: NativeSyntheticEvent<{}>) => void;

  style?: ViewStyle;
};

// --- Public Props ---

export type NativeDrawablePdfViewProps_Public = {
  /**
   * Document to display.
   */
  source: string;

  /**
   * Page (0-indexed) of document to display.
   */
  page: number;

  /**
   * How pdf page should be scaled to fit in view dimensions.
   */
  resizeMode?: 'contain' | 'fitWidth';

  /**
   * PAS v1 annotation JSON string.
   */
  annotationStr?: string;

  /**
   * Path to annotation data file.
   */
  annotation?: string;

  /**
   * Drawing mode.
   * - 'view': No drawing, just viewing (zoom enabled)
   * - 'draw': Drawing mode with current tool (zoom disabled)
   * - 'erase': Erase strokes by touching them (zoom disabled)
   * - 'highlight': Drawing with highlighter (zoom disabled)
   */
  drawingMode?: DrawingMode;

  /**
   * Drawing tool configuration.
   */
  drawingTool?: DrawingTool;

  /**
   * Current strokes on this page.
   */
  strokes?: DrawingStroke[];

  /**
   * Minimum zoom level. Default: 1.
   */
  minZoom?: number;

  /**
   * Maximum zoom level. Default: 3.
   */
  maxZoom?: number;

  /**
   * Enable/disable zoom gestures. Default: true.
   * Note: Zoom is automatically disabled in draw/erase/highlight modes.
   */
  zoomEnabled?: boolean;

  /**
   * Callback when an error occurs.
   */
  onError?: (event: ErrorEvent) => void;

  /**
   * Callback for measuring the native view.
   */
  onLayout?: (event: LayoutChangeEvent) => void;

  /**
   * Callback when PDF load completes.
   */
  onLoadComplete?: (event: LoadCompleteEvent) => void;

  /**
   * Callback when drawing starts.
   */
  onDrawingStart?: () => void;

  /**
   * Callback when drawing ends.
   */
  onDrawingEnd?: () => void;

  /**
   * Callback when a stroke is completed.
   */
  onStrokeEnd?: (stroke: DrawingStroke) => void;

  /**
   * Callback when a stroke is removed (erased).
   */
  onStrokeRemoved?: (strokeId: string) => void;

  /**
   * Callback when all strokes are cleared.
   */
  onStrokesCleared?: () => void;

  /**
   * Callback when zoom level changes.
   */
  onZoomChange?: (event: ZoomChangeEvent) => void;

  /**
   * Callback when zoom pan gesture starts (user starts dragging while zoomed).
   */
  onZoomPanStart?: () => void;

  /**
   * Callback when zoom pan gesture ends.
   */
  onZoomPanEnd?: () => void;

  /**
   * Callback when a single tap is detected in view mode (not zoomed).
   * Used for tap-to-scroll functionality.
   */
  onSingleTap?: () => void;

  style?: ViewStyle;
};

// --- Ref type ---

export type NativeDrawablePdfViewRef = {
  /**
   * Clear all strokes from the view.
   */
  clearStrokes: () => void;

  /**
   * Reset zoom to default (scale = 1).
   */
  resetZoom: () => void;
};

// --- Native component ---

const RNDrawablePdfView =
  requireNativeComponent<NativeDrawablePdfViewProps>('RNDrawablePdfView');

/**
 * Convert DrawingStroke[] to JSON string for native component.
 */
function strokesToJson(strokes: DrawingStroke[]): string {
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
export const NativeDrawablePdfView = forwardRef<
  NativeDrawablePdfViewRef,
  NativeDrawablePdfViewProps_Public
>(function NativeDrawablePdfView(props, ref) {
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
    style,
  } = props;

  const viewRef = useRef<any>(null);

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
    },
  }));

  // Event handlers
  const handlePdfError = useCallback(
    (event: NativeSyntheticEvent<ErrorEvent>) => {
      onError?.(event.nativeEvent);
    },
    [onError]
  );

  const handlePdfLoadComplete = useCallback(
    (event: NativeSyntheticEvent<LoadCompleteEvent>) => {
      onLoadComplete?.(event.nativeEvent);
    },
    [onLoadComplete]
  );

  const handleDrawingStart = useCallback(
    (_event: NativeSyntheticEvent<{}>) => {
      onDrawingStart?.();
    },
    [onDrawingStart]
  );

  const handleDrawingEnd = useCallback(
    (_event: NativeSyntheticEvent<{}>) => {
      onDrawingEnd?.();
    },
    [onDrawingEnd]
  );

  const handleStrokeEnd = useCallback(
    (event: NativeSyntheticEvent<StrokeEndEvent>) => {
      const { id, color, width, opacity, path } = event.nativeEvent;
      onStrokeEnd?.({
        id,
        color,
        width,
        opacity,
        path,
      });
    },
    [onStrokeEnd]
  );

  const handleStrokeRemoved = useCallback(
    (event: NativeSyntheticEvent<StrokeRemovedEvent>) => {
      onStrokeRemoved?.(event.nativeEvent.id);
    },
    [onStrokeRemoved]
  );

  const handleStrokesCleared = useCallback(
    (_event: NativeSyntheticEvent<{}>) => {
      onStrokesCleared?.();
    },
    [onStrokesCleared]
  );

  const handleZoomChange = useCallback(
    (event: NativeSyntheticEvent<ZoomChangeEvent>) => {
      onZoomChange?.(event.nativeEvent);
    },
    [onZoomChange]
  );

  const handleZoomPanStart = useCallback(
    (_event: NativeSyntheticEvent<{}>) => {
      onZoomPanStart?.();
    },
    [onZoomPanStart]
  );

  const handleZoomPanEnd = useCallback(
    (_event: NativeSyntheticEvent<{}>) => {
      onZoomPanEnd?.();
    },
    [onZoomPanEnd]
  );

  const handleSingleTap = useCallback(
    (_event: NativeSyntheticEvent<{}>) => {
      onSingleTap?.();
    },
    [onSingleTap]
  );

  return (
    <RNDrawablePdfView
      ref={viewRef}
      source={asPath(source)}
      page={page}
      resizeMode={resizeMode}
      annotation={asPath(annotation)}
      annotationStr={annotationStr}
      drawingMode={drawingMode}
      strokeColor={drawingTool.color}
      strokeWidth={drawingTool.strokeWidth}
      strokeOpacity={drawingTool.opacity}
      strokes={strokesToJson(strokes)}
      minZoom={minZoom}
      maxZoom={maxZoom}
      zoomEnabled={zoomEnabled}
      onLayout={onLayout}
      onPdfError={handlePdfError}
      onPdfLoadComplete={handlePdfLoadComplete}
      onDrawingStart={handleDrawingStart}
      onDrawingEnd={handleDrawingEnd}
      onStrokeEnd={handleStrokeEnd}
      onStrokeRemoved={handleStrokeRemoved}
      onStrokesCleared={handleStrokesCleared}
      onZoomChange={handleZoomChange}
      onZoomPanStart={handleZoomPanStart}
      onZoomPanEnd={handleZoomPanEnd}
      onSingleTap={handleSingleTap}
      style={style}
    />
  );
});