import React from 'react';
import { LayoutChangeEvent, ViewStyle } from 'react-native';
import type { DrawingMode, DrawingStroke, DrawingTool } from './drawing/types';
export type ErrorEvent = {
    message: string;
};
export type LoadCompleteEvent = {
    height: number;
    width: number;
};
export type StrokeEndEvent = {
    id: string;
    color: string;
    width: number;
    opacity: number;
    path: [number, number][];
};
export type StrokeRemovedEvent = {
    id: string;
};
export type ZoomChangeEvent = {
    scale: number;
    offsetX: number;
    offsetY: number;
};
export type NativeDrawablePdfViewProps_Public = {
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
     * Current strokes on this page.
     */
    strokes?: DrawingStroke[];
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
     * Note: Zoom is automatically disabled in draw/erase/highlight modes.
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
     * Callback when drawing starts.
     */
    onDrawingStart?: () => void;
    /**
     * Callback when drawing ends.
     */
    onDrawingEnd?: () => void;
    /**
     * Callback when a stroke is completed.
     */
    onStrokeEnd?: (stroke: DrawingStroke) => void;
    /**
     * Callback when a stroke is removed (erased).
     */
    onStrokeRemoved?: (strokeId: string) => void;
    /**
     * Callback when all strokes are cleared.
     */
    onStrokesCleared?: () => void;
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
     * Callback when a single tap is detected in view mode (not zoomed).
     * Used for tap-to-scroll functionality.
     */
    onSingleTap?: () => void;
    style?: ViewStyle;
};
export type NativeDrawablePdfViewRef = {
    /**
     * Clear all strokes from the view.
     */
    clearStrokes: () => void;
    /**
     * Reset zoom to default (scale = 1).
     */
    resetZoom: () => void;
};
/**
 * Native PDF view with drawing and zoom support.
 *
 * This component renders PDF with native drawing and pinch-to-zoom capabilities.
 * Touch events for drawing and zooming are handled natively for better performance.
 *
 * Features:
 * - Pinch-to-zoom with configurable min/max
 * - Double-tap to zoom in/reset
 * - Pan when zoomed in
 * - Drawing with pen and highlighter
 * - Eraser tool
 *
 * Supported platforms: Android, iOS
 */
export declare const NativeDrawablePdfView: React.ForwardRefExoticComponent<NativeDrawablePdfViewProps_Public & React.RefAttributes<NativeDrawablePdfViewRef>>;
