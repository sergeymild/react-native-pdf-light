import React from 'react';
import { LayoutChangeEvent, ViewStyle } from 'react-native';
export type ErrorEvent = {
    message: string;
};
export type LoadCompleteEvent = {
    height: number;
    width: number;
};
export type ZoomChangeEvent = {
    scale: number;
    offsetX: number;
    offsetY: number;
};
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
export type NativeSimplePdfViewRef = {
    /**
     * Reset zoom to default (scale = 1).
     */
    resetZoom: () => void;
};
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
export declare const NativeSimplePdfView: React.ForwardRefExoticComponent<NativeSimplePdfViewProps_Public & React.RefAttributes<NativeSimplePdfViewRef>>;
