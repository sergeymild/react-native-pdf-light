import React, { forwardRef } from 'react';
import type { LayoutChangeEvent, ViewStyle } from 'react-native';
import { NativePagingPdfView } from './NativePagingPdfView';
import { NativeZoomablePdfScrollView } from './NativeZoomablePdfScrollView';
import type { DrawingMode, DrawingTool, TextTool } from './drawing/types';
import type { AnnotationPage, PdfViewerRef } from './types';

export type { AnnotationStroke, AnnotationText, AnnotationPage, PdfViewerRef } from './types';

// --- Unified Event Types ---

export type PdfErrorEvent = { message: string };

export type PdfLoadCompleteEvent = {
  width: number;
  height: number;
  pageCount: number;
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

  // --- Drawing Props ---

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
   * Text tool configuration for text annotations.
   */
  textTool?: TextTool;

  /**
   * Callback when drawing starts.
   */
  onDrawingStart?: () => void;

  /**
   * Callback when drawing ends.
   */
  onDrawingEnd?: () => void;

  /**
   * Callback when undo/redo availability changes.
   */
  onUndoStateChange?: (state: { canUndo: boolean; canRedo: boolean }) => void;

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

export const PdfViewer = forwardRef<PdfViewerRef, PdfViewerProps>(
  (props, ref) => {
    const { viewerType, ...rest } = props;

    if (viewerType === 'zoomable') {
      return <NativeZoomablePdfScrollView {...rest} ref={ref} />;
    }

    return <NativePagingPdfView {...rest} ref={ref} />;
  }
);
