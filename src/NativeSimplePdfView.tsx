import React, {
  useCallback,
  useRef,
  useImperativeHandle,
  forwardRef,
} from 'react';
import {
  findNodeHandle,
  LayoutChangeEvent,
  NativeSyntheticEvent,
  requireNativeComponent,
  UIManager,
  ViewStyle,
} from 'react-native';
import { asPath } from './Util';

// --- Event types ---

export type ErrorEvent = { message: string };

export type LoadCompleteEvent = { height: number; width: number };

export type ZoomChangeEvent = {
  scale: number;
  offsetX: number;
  offsetY: number;
};

// --- Native Props ---

type NativeSimplePdfViewProps = {
  // PDF props
  source: string;
  page: number;
  resizeMode?: 'contain' | 'fitWidth';
  annotation?: string;
  annotationStr?: string;

  // Zoom props
  minZoom: number;
  maxZoom: number;
  zoomEnabled: boolean;

  // Events
  onLayout?: (event: LayoutChangeEvent) => void;
  onPdfError: (event: NativeSyntheticEvent<ErrorEvent>) => void;
  onPdfLoadComplete: (event: NativeSyntheticEvent<LoadCompleteEvent>) => void;
  onZoomChange: (event: NativeSyntheticEvent<ZoomChangeEvent>) => void;
  onZoomPanStart: (event: NativeSyntheticEvent<{}>) => void;
  onZoomPanEnd: (event: NativeSyntheticEvent<{}>) => void;
  onSingleTap: (event: NativeSyntheticEvent<{}>) => void;

  style?: ViewStyle;
};

// --- Public Props ---

export type NativeSimplePdfViewProps_Public = {
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
   * Minimum zoom level. Default: 1.
   */
  minZoom?: number;

  /**
   * Maximum zoom level. Default: 3.
   */
  maxZoom?: number;

  /**
   * Enable/disable zoom gestures. Default: true.
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
   * Callback when a single tap is detected (not zoomed).
   * Used for tap-to-scroll functionality.
   */
  onSingleTap?: () => void;

  style?: ViewStyle;
};

// --- Ref type ---

export type NativeSimplePdfViewRef = {
  /**
   * Reset zoom to default (scale = 1).
   */
  resetZoom: () => void;
};

// --- Native component ---

const RNSimplePdfView =
  requireNativeComponent<NativeSimplePdfViewProps>('RNSimplePdfView');

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
export const NativeSimplePdfView = forwardRef<
  NativeSimplePdfViewRef,
  NativeSimplePdfViewProps_Public
>(function NativeSimplePdfView(props, ref) {
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
    style,
  } = props;

  const viewRef = useRef<any>(null);

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
    <RNSimplePdfView
      ref={viewRef}
      source={asPath(source)}
      page={page}
      resizeMode={resizeMode}
      annotation={asPath(annotation)}
      annotationStr={annotationStr}
      minZoom={minZoom}
      maxZoom={maxZoom}
      zoomEnabled={zoomEnabled}
      onLayout={onLayout}
      onPdfError={handlePdfError}
      onPdfLoadComplete={handlePdfLoadComplete}
      onZoomChange={handleZoomChange}
      onZoomPanStart={handleZoomPanStart}
      onZoomPanEnd={handleZoomPanEnd}
      onSingleTap={handleSingleTap}
      style={style}
    />
  );
});
