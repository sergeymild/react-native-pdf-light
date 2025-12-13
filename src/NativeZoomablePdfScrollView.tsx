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

export type ZoomablePdfErrorEvent = { message: string };

export type ZoomablePdfLoadCompleteEvent = {
  width: number;
  height: number;
  pageCount: number;
};

export type ZoomablePdfPageChangeEvent = { page: number };

export type ZoomablePdfZoomChangeEvent = { scale: number };

export type ZoomablePdfTapEvent = {
  position: 'top' | 'bottom' | 'left' | 'right';
};

// --- Native Props ---

type NativeZoomablePdfScrollViewProps = {
  source: string;
  minZoom: number;
  maxZoom: number;
  edgeTapZone: number;
  pdfPaddingTop: number;
  pdfPaddingBottom: number;
  pdfBackgroundColor?: ReturnType<typeof processColor>;

  onLayout?: (event: LayoutChangeEvent) => void;
  onPdfError: (event: NativeSyntheticEvent<ZoomablePdfErrorEvent>) => void;
  onPdfLoadComplete: (
    event: NativeSyntheticEvent<ZoomablePdfLoadCompleteEvent>
  ) => void;
  onPageChange: (
    event: NativeSyntheticEvent<ZoomablePdfPageChangeEvent>
  ) => void;
  onZoomChange: (
    event: NativeSyntheticEvent<ZoomablePdfZoomChangeEvent>
  ) => void;
  onTap: (event: NativeSyntheticEvent<ZoomablePdfTapEvent>) => void;
  onMiddleClick: (event: NativeSyntheticEvent<{}>) => void;

  style?: ViewStyle;
};

// --- Public Props ---

export type NativeZoomablePdfScrollViewProps_Public = {
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
   * The remaining middle area triggers onMiddleClick.
   */
  edgeTapZone?: number;

  /**
   * Background color behind PDF pages. Default: gray (#333333).
   * Accepts any React Native color value (e.g., '#000000', 'black', 'rgb(0,0,0)').
   */
  backgroundColor?: string;

  /**
   * Extra padding at the top of the scroll content in points. Default: 0.
   * Useful for adding empty space before the first page.
   */
  pdfPaddingTop?: number;

  /**
   * Extra padding at the bottom of the scroll content in points. Default: 0.
   * Useful for adding empty space after the last page.
   */
  pdfPaddingBottom?: number;

  /**
   * Callback when an error occurs.
   */
  onError?: (event: ZoomablePdfErrorEvent) => void;

  /**
   * Callback for measuring the native view.
   */
  onLayout?: (event: LayoutChangeEvent) => void;

  /**
   * Callback when PDF load completes.
   */
  onLoadComplete?: (event: ZoomablePdfLoadCompleteEvent) => void;

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
   * Landscape mode: 'top' = upper half, 'bottom' = lower half
   * Portrait mode: 'left' = left 15%, 'right' = right 15%
   */
  onTap?: (position: 'top' | 'bottom' | 'left' | 'right') => void;

  /**
   * Callback when user taps in the middle zone (70%) in portrait mode.
   */
  onMiddleClick?: () => void;

  style?: ViewStyle;
};

// --- Ref type ---

export type NativeZoomablePdfScrollViewRef = {
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

const RNZoomablePdfScrollView =
  requireNativeComponent<NativeZoomablePdfScrollViewProps>(
    'RNZoomablePdfScrollView'
  );

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
export const NativeZoomablePdfScrollView = forwardRef<
  NativeZoomablePdfScrollViewRef,
  NativeZoomablePdfScrollViewProps_Public
>(function NativeZoomablePdfScrollView(props, ref) {
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
    (event: NativeSyntheticEvent<ZoomablePdfErrorEvent>) => {
      onError?.(event.nativeEvent);
    },
    [onError]
  );

  const handlePdfLoadComplete = useCallback(
    (event: NativeSyntheticEvent<ZoomablePdfLoadCompleteEvent>) => {
      onLoadComplete?.(event.nativeEvent);
    },
    [onLoadComplete]
  );

  const handlePageChange = useCallback(
    (event: NativeSyntheticEvent<ZoomablePdfPageChangeEvent>) => {
      onPageChange?.(event.nativeEvent.page);
    },
    [onPageChange]
  );

  const handleZoomChange = useCallback(
    (event: NativeSyntheticEvent<ZoomablePdfZoomChangeEvent>) => {
      onZoomChange?.(event.nativeEvent.scale);
    },
    [onZoomChange]
  );

  const handleTap = useCallback(
    (event: NativeSyntheticEvent<ZoomablePdfTapEvent>) => {
      onTap?.(event.nativeEvent.position);
    },
    [onTap]
  );

  const handleMiddleClick = useCallback(() => {
    onMiddleClick?.();
  }, [onMiddleClick]);

  return (
    <RNZoomablePdfScrollView
      ref={viewRef}
      source={asPath(source)}
      minZoom={minZoom}
      maxZoom={maxZoom}
      edgeTapZone={Math.max(0, Math.min(50, edgeTapZone))}
      pdfPaddingTop={Math.max(0, pdfPaddingTop)}
      pdfPaddingBottom={Math.max(0, pdfPaddingBottom)}
      pdfBackgroundColor={
        backgroundColor ? processColor(backgroundColor) : undefined
      }
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
