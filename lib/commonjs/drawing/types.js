"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.DEFAULT_HIGHLIGHTER_TOOL = exports.DEFAULT_DRAWING_TOOL = void 0;
/**
 * Drawing mode for the PDF view.
 */

/**
 * Drawing tool configuration.
 */

/**
 * A single stroke drawn on the PDF.
 * Coordinates are normalized to 0-1 range relative to page dimensions.
 */

/**
 * Annotations for a single page.
 */

/**
 * Default drawing tool configuration.
 */
const DEFAULT_DRAWING_TOOL = exports.DEFAULT_DRAWING_TOOL = {
  color: '#000000',
  strokeWidth: 3,
  opacity: 1
};

/**
 * Default highlighter tool configuration.
 */
const DEFAULT_HIGHLIGHTER_TOOL = exports.DEFAULT_HIGHLIGHTER_TOOL = {
  color: '#FFFF00',
  strokeWidth: 20,
  opacity: 0.3
};
//# sourceMappingURL=types.js.map