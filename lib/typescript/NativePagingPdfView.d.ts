import React from 'react';
import { LayoutChangeEvent, ViewStyle } from 'react-native';
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
