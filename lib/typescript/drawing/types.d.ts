/**
 * Drawing mode for the PDF view.
 */
export type DrawingMode = 'view' | 'draw' | 'erase' | 'highlight';
/**
 * Drawing tool configuration.
 */
export interface DrawingTool {
    /** Stroke color in hex format "#RRGGBB" */
    color: string;
    /** Stroke width in points (1-20) */
    strokeWidth: number;
    /** Stroke opacity (0-1). Use 0.3 for highlighter effect. */
    opacity: number;
}
/**
 * A single stroke drawn on the PDF.
 * Coordinates are normalized to 0-1 range relative to page dimensions.
 */
export interface DrawingStroke {
    /** Unique identifier for this stroke */
    id: string;
    /** Stroke color in hex format "#RRGGBB" */
    color: string;
    /** Stroke width in points */
    width: number;
    /** Stroke opacity (0-1) */
    opacity: number;
    /** Array of [x, y] points, normalized to 0-1 range */
    path: [number, number][];
}
/**
 * Annotations for a single page.
 */
export interface PageAnnotations {
    strokes: DrawingStroke[];
}
/**
 * Default drawing tool configuration.
 */
export declare const DEFAULT_DRAWING_TOOL: DrawingTool;
/**
 * Default highlighter tool configuration.
 */
export declare const DEFAULT_HIGHLIGHTER_TOOL: DrawingTool;
