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
  NativeModules,
  processColor,
  requireNativeComponent,
  UIManager,
  ViewStyle,
} from 'react-native';
import type { DrawingMode, DrawingTool } from './drawing/types';
import { DEFAULT_DRAWING_TOOL } from './drawing/types';
import { asPath } from './Util';

// --- Event types ---

export type PagingPdfErrorEvent = { message: string };

export type PagingPdfLoadCompleteEvent = {
  width: number;
  height: number;
  pageCount: number;
};

export type PagingPdfPageChangeEvent = { page: number };

export type PagingPdfZoomChangeEvent = { scale: number };

export type PagingPdfTapEvent = { position: 'top' | 'bottom' | 'left' | 'right' };

// --- Annotation Types ---

export type AnnotationStroke = {
  id?: string;
  color: string;
  width: number;
  opacity?: number;
  path: number[][];
};

export type AnnotationText = {
  color: string;
  fontSize: number;
  point: number[];
  str: string;
};

export type AnnotationPage = {
  strokes: AnnotationStroke[];
  text: AnnotationText[];
};

// --- Native Props ---

type NativePagingPdfViewProps = {
  source: string;
  annotations?: string; // JSON string of AnnotationPage[]
  minZoom: number;
  maxZoom: number;
  edgeTapZone: number;
  pdfBackgroundColor?: ReturnType<typeof processColor>;

  // Drawing props
  drawingMode: string;
  strokeColor: string;
  strokeWidth: number;
  strokeOpacity: number;

  onLayout?: (event: LayoutChangeEvent) => void;
  onPdfError: (event: NativeSyntheticEvent<PagingPdfErrorEvent>) => void;
  onPdfLoadComplete: (
    event: NativeSyntheticEvent<PagingPdfLoadCompleteEvent>
  ) => void;
  onPageChange: (event: NativeSyntheticEvent<PagingPdfPageChangeEvent>) => void;
  onZoomChange: (event: NativeSyntheticEvent<PagingPdfZoomChangeEvent>) => void;
  onTap: (event: NativeSyntheticEvent<PagingPdfTapEvent>) => void;
  onMiddleClick: (event: NativeSyntheticEvent<{}>) => void;

  // Drawing events
  onDrawingStart: (event: NativeSyntheticEvent<{}>) => void;
  onDrawingEnd: (event: NativeSyntheticEvent<{}>) => void;

  style?: ViewStyle;
};

// --- Public Props ---

export type NativePagingPdfViewProps_Public = {
  /**
   * Path to PDF document.
   */
  source: string;

  /**
   * Annotations to render on PDF pages.
   * Array index corresponds to page number (0-based).
   */
  annotations?: AnnotationPage[];

  /**
   * Minimum zoom level. Default: 1.
   */
  minZoom?: number;

  /**
   * Maximum zoom level. Default: 3.
   */
  maxZoom?: number;

  /**
   * Edge tap zone size as percentage (0-50). Default: 15.
   * Left and right edges of this size will trigger scroll on tap.
   * At page boundaries, tapping will switch to previous/next page.
   * The remaining middle area triggers onMiddleClick.
   */
  edgeTapZone?: number;

  /**
   * Background color behind PDF pages. Default: white (#ffffff).
   * Accepts any React Native color value (e.g., '#000000', 'black', 'rgb(0,0,0)').
   */
  backgroundColor?: string;

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
   * Callback when an error occurs.
   */
  onError?: (event: PagingPdfErrorEvent) => void;

  /**
   * Callback for measuring the native view.
   */
  onLayout?: (event: LayoutChangeEvent) => void;

  /**
   * Callback when PDF load completes.
   */
  onLoadComplete?: (event: PagingPdfLoadCompleteEvent) => void;

  /**
   * Callback when current page changes.
   */
  onPageChange?: (page: number) => void;

  /**
   * Callback when zoom level changes.
   */
  onZoomChange?: (scale: number) => void;

  /**
   * Callback when user taps on scroll zones.
   * 'left' = left edge zone, 'right' = right edge zone
   */
  onTap?: (position: 'top' | 'bottom' | 'left' | 'right') => void;

  /**
   * Callback when user taps in the middle zone.
   */
  onMiddleClick?: () => void;

  /**
   * Callback when drawing starts.
   */
  onDrawingStart?: () => void;

  /**
   * Callback when drawing ends.
   */
  onDrawingEnd?: () => void;

  style?: ViewStyle;
};

// --- Ref type ---

export type NativePagingPdfViewRef = {
  /**
   * Reset zoom to default (scale = 1).
   */
  resetZoom: () => void;

  /**
   * Scroll to specific page.
   */
  scrollToPage: (page: number, animated?: boolean) => void;

  /**
   * Clear strokes for a specific page or all pages.
   * @param page Page index to clear, or -1 to clear all pages.
   */
  clearStrokes: (page?: number) => void;

  /**
   * Get all annotations (strokes) from all pages.
   * Returns a promise with Record<pageIndex, strokes[]>.
   * Strokes are stored natively - use this to retrieve them when needed.
   */
  getAnnotations: () => Promise<Record<string, AnnotationStroke[]>>;
};

// --- Native component ---

const RNPagingPdfView =
  requireNativeComponent<NativePagingPdfViewProps>('RNPagingPdfView');

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
export const NativePagingPdfView = forwardRef<
  NativePagingPdfViewRef,
  NativePagingPdfViewProps_Public
>(function NativePagingPdfView(props, ref) {
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
    scrollToPage: (page: number, animated = true) => {
      if (viewRef.current) {
        const handle = findNodeHandle(viewRef.current);
        if (handle) {
          UIManager.dispatchViewManagerCommand(handle, 'scrollToPage', [
            page,
            animated,
          ]);
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
    getAnnotations: async (): Promise<Record<string, AnnotationStroke[]>> => {
      if (viewRef.current) {
        const handle = findNodeHandle(viewRef.current);
        if (handle) {
          const manager = NativeModules.RNPagingPdfView;
          if (manager?.getAnnotations) {
            return manager.getAnnotations(handle);
          }
        }
      }
      return {};
    },
  }));

  // Event handlers
  const handlePdfError = useCallback(
    (event: NativeSyntheticEvent<PagingPdfErrorEvent>) => {
      onError?.(event.nativeEvent);
    },
    [onError]
  );

  const handlePdfLoadComplete = useCallback(
    (event: NativeSyntheticEvent<PagingPdfLoadCompleteEvent>) => {
      onLoadComplete?.(event.nativeEvent);
    },
    [onLoadComplete]
  );

  const handlePageChange = useCallback(
    (event: NativeSyntheticEvent<PagingPdfPageChangeEvent>) => {
      onPageChange?.(event.nativeEvent.page);
    },
    [onPageChange]
  );

  const handleZoomChange = useCallback(
    (event: NativeSyntheticEvent<PagingPdfZoomChangeEvent>) => {
      onZoomChange?.(event.nativeEvent.scale);
    },
    [onZoomChange]
  );

  const handleTap = useCallback(
    (event: NativeSyntheticEvent<PagingPdfTapEvent>) => {
      onTap?.(event.nativeEvent.position);
    },
    [onTap]
  );

  const handleMiddleClick = useCallback(() => {
    onMiddleClick?.();
  }, [onMiddleClick]);

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

  return (
    <RNPagingPdfView
      ref={viewRef}
      source={asPath(source)}
      annotations={annotations ? JSON.stringify(annotations) : undefined}
      minZoom={minZoom}
      maxZoom={maxZoom}
      edgeTapZone={Math.max(0, Math.min(50, edgeTapZone))}
      pdfBackgroundColor={backgroundColor ? processColor(backgroundColor) : undefined}
      drawingMode={drawingMode}
      strokeColor={drawingTool.color}
      strokeWidth={drawingTool.strokeWidth}
      strokeOpacity={drawingTool.opacity}
      onLayout={onLayout}
      onPdfError={handlePdfError}
      onPdfLoadComplete={handlePdfLoadComplete}
      onPageChange={handlePageChange}
      onZoomChange={handleZoomChange}
      onTap={handleTap}
      onMiddleClick={handleMiddleClick}
      onDrawingStart={handleDrawingStart}
      onDrawingEnd={handleDrawingEnd}
      style={style}
    />
  );
});
