import React from 'react';
import { LayoutChangeEvent, ViewStyle } from 'react-native';
export type ZoomablePdfErrorEvent = {
    message: string;
};
export type ZoomablePdfLoadCompleteEvent = {
    width: number;
    height: number;
    pageCount: number;
};
export type ZoomablePdfPageChangeEvent = {
    page: number;
};
export type ZoomablePdfZoomChangeEvent = {
    scale: number;
};
export type ZoomablePdfTapEvent = {
    position: 'top' | 'bottom' | 'left' | 'right';
};
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
export declare const NativeZoomablePdfScrollView: React.ForwardRefExoticComponent<NativeZoomablePdfScrollViewProps_Public & React.RefAttributes<NativeZoomablePdfScrollViewRef>>;
