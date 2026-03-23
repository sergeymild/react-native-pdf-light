/**
 * A stroke (line) annotation with normalized coordinates (0-1).
 */
export type AnnotationStroke = {
  /** Unique identifier (required for user-drawn strokes, optional for static) */
  id?: string;
  /** Hex color string (e.g., "#ff0000") */
  color: string;
  /** Line width in points */
  width: number;
  /** Stroke opacity 0-1 (default 1) */
  opacity?: number;
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

/**
 * Ref type shared by both Zoomable and Paging PDF viewers.
 */
export type PdfViewerRef = {
  /** Reset zoom to default (scale = 1). */
  resetZoom: () => void;
  /** Scroll to specific page. */
  scrollToPage: (page: number, animated?: boolean) => void;
  /** Clear strokes for a specific page or all pages. Pass -1 to clear all. */
  clearStrokes: (page?: number) => void;
  /**
   * Get all annotations (strokes and text) from all pages.
   * Returns a promise with Record<pageIndex, { strokes, text }>.
   */
  getAnnotations: () => Promise<
    Record<string, { strokes: AnnotationStroke[]; text: AnnotationText[] }>
  >;
  /** Undo the last drawing action. */
  undo: () => void;
  /** Redo the last undone action. */
  redo: () => void;
};
