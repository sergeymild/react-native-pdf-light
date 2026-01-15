import React from 'react';
import { LayoutChangeEvent, ViewStyle } from 'react-native';
import type { DrawingMode, DrawingTool } from './drawing/types';
export type PagingPdfErrorEvent = {
    message: string;
};
export type PagingPdfLoadCompleteEvent = {
    width: number;
    height: number;
    pageCount: number;
};
export type PagingPdfPageChangeEvent = {
    page: number;
};
export type PagingPdfZoomChangeEvent = {
    scale: number;
};
export type PagingPdfTapEvent = {
    position: 'top' | 'bottom' | 'left' | 'right';
};
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
export declare const NativePagingPdfView: React.ForwardRefExoticComponent<NativePagingPdfViewProps_Public & React.RefAttributes<NativePagingPdfViewRef>>;
