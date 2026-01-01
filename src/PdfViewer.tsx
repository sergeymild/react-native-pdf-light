import React, { forwardRef } from 'react';
import type { LayoutChangeEvent, ViewStyle } from 'react-native';
import { NativePagingPdfView } from './NativePagingPdfView';
import {
  NativeZoomablePdfScrollView,
  type NativeZoomablePdfScrollViewRef,
} from './NativeZoomablePdfScrollView';

// --- Unified Event Types ---

export type PdfErrorEvent = { message: string };

export type PdfLoadCompleteEvent = {
  width: number;
  height: number;
  pageCount: number;
};

// --- Annotation Types ---

/**
 * A stroke (line) annotation with normalized coordinates (0-1).
 */
export type AnnotationStroke = {
  /** Hex color string (e.g., "#ff0000") */
  color: string;
  /** Line width in points */
  width: number;
  /** Array of [x, y] points, normalized 0-1 relative to page dimensions */
  path: number[][];
};

/**
 * A text annotation with normalized position (0-1).
 */
export type AnnotationText = {
  /** Hex color string (e.g., "#000000") */
  color: string;
  /** Font size in points */
  fontSize: number;
  /** Position [x, y], normalized 0-1 relative to page dimensions */
  point: number[];
  /** Text content */
  str: string;
};

/**
 * Annotations for a single page.
 */
export type AnnotationPage = {
  strokes: AnnotationStroke[];
  text: AnnotationText[];
};

// --- Common Props ---

type PdfViewerCommonProps = {
  /**
   * Path to PDF document.
   */
  source: string;

  /**
   * Annotations to render on PDF pages.
   * Array index corresponds to page number (0-based).
   * Each element contains strokes and text for that page.
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
   */
  edgeTapZone?: number;

  /**
   * Background color behind PDF pages.
   * Accepts any React Native color value.
   */
  backgroundColor?: string;

  /**
   * Callback when an error occurs.
   */
  onError?: (event: PdfErrorEvent) => void;

  /**
   * Callback for measuring the native view.
   */
  onLayout?: (event: LayoutChangeEvent) => void;

  /**
   * Callback when PDF load completes.
   */
  onLoadComplete?: (event: PdfLoadCompleteEvent) => void;

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
   */
  onTap?: (position: 'top' | 'bottom' | 'left' | 'right') => void;

  /**
   * Callback when user taps in the middle zone.
   */
  onMiddleClick?: () => void;

  style?: ViewStyle;
};

// --- Viewer-specific Props ---

type ZoomableViewerProps = PdfViewerCommonProps & {
  viewerType: 'zoomable';

  /**
   * Extra padding at the top of the scroll content in points. Default: 0.
   */
  pdfPaddingTop?: number;

  /**
   * Extra padding at the bottom of the scroll content in points. Default: 0.
   */
  pdfPaddingBottom?: number;
};

type PagingViewerProps = PdfViewerCommonProps & {
  viewerType: 'paging';
};

export type PdfViewerProps = ZoomableViewerProps | PagingViewerProps;

export type PdfViewerRef = NativeZoomablePdfScrollViewRef;

export const PdfViewer = forwardRef<PdfViewerRef, PdfViewerProps>(
  (props, ref) => {
    const { viewerType, ...rest } = props;

    if (viewerType === 'zoomable') {
      return <NativeZoomablePdfScrollView {...rest} ref={ref} />;
    }

    return <NativePagingPdfView {...rest} ref={ref} />;
  }
);
