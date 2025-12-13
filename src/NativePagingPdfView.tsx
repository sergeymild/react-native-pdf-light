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
  processColor,
  requireNativeComponent,
  UIManager,
  ViewStyle,
} from 'react-native';
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

// --- Native Props ---

type NativePagingPdfViewProps = {
  source: string;
  minZoom: number;
  maxZoom: number;
  edgeTapZone: number;
  pdfBackgroundColor?: ReturnType<typeof processColor>;

  onLayout?: (event: LayoutChangeEvent) => void;
  onPdfError: (event: NativeSyntheticEvent<PagingPdfErrorEvent>) => void;
  onPdfLoadComplete: (
    event: NativeSyntheticEvent<PagingPdfLoadCompleteEvent>
  ) => void;
  onPageChange: (event: NativeSyntheticEvent<PagingPdfPageChangeEvent>) => void;
  onZoomChange: (event: NativeSyntheticEvent<PagingPdfZoomChangeEvent>) => void;
  onTap: (event: NativeSyntheticEvent<PagingPdfTapEvent>) => void;
  onMiddleClick: (event: NativeSyntheticEvent<{}>) => void;

  style?: ViewStyle;
};

// --- Public Props ---

export type NativePagingPdfViewProps_Public = {
  /**
   * Path to PDF document.
   */
  source: string;

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

  return (
    <RNPagingPdfView
      ref={viewRef}
      source={asPath(source)}
      minZoom={minZoom}
      maxZoom={maxZoom}
      edgeTapZone={Math.max(0, Math.min(50, edgeTapZone))}
      pdfBackgroundColor={backgroundColor ? processColor(backgroundColor) : undefined}
      onLayout={onLayout}
      onPdfError={handlePdfError}
      onPdfLoadComplete={handlePdfLoadComplete}
      onPageChange={handlePageChange}
      onZoomChange={handleZoomChange}
      onTap={handleTap}
      onMiddleClick={handleMiddleClick}
      style={style}
    />
  );
});
