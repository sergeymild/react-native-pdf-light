# Annotations API — Backend Developer Guide

## Overview

PDF viewer supports two types of annotations:
- **Static annotations** — baked into page bitmap at render time (read-only preview)
- **Editable annotations** — loaded into DrawingController as live strokes/texts (can be edited, erased, undo/redo)

Both use the same data format. The difference is how they're passed to the native viewer:
- `annotations` prop → static (baked into bitmap)
- `loadAnnotations()` ref method → editable (live overlay)

All coordinates are **normalized 0-1** relative to page dimensions.

---

## Data Schema

### AnnotationPage[]

The top-level structure is an array where **index = page number** (0-based).

```jsonc
[
  { "strokes": [...], "text": [...] },  // page 0
  { "strokes": [...], "text": [...] },  // page 1
  // ...
]
```

### Stroke

```jsonc
{
  "color": "#ff0000",       // Required. Hex RGB color
  "width": 3,               // Required. Line width in points (typical: 1-20)
  "opacity": 1.0,           // Optional. 0-1, default 1.0. Use 0.3 for highlights
  "path": [                 // Required. Array of [x, y] points, normalized 0-1
    [0.1, 0.15],
    [0.2, 0.16],
    [0.3, 0.14]
  ]
}
```

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `color` | string | yes | — | Hex color `"#RRGGBB"` |
| `width` | number | yes | — | Stroke width in points |
| `opacity` | number | no | `1.0` | Opacity 0-1. Highlights use `0.3` |
| `path` | number[][] | yes | — | Array of `[x, y]` normalized 0-1 |

**Path details:**
- Minimum 1 point (renders as a dot)
- 2 points = straight line
- 3+ points = smooth curve (quadratic Bezier interpolation)
- Coordinates: `[0, 0]` = top-left, `[1, 1]` = bottom-right of page

**Typical stroke types:**

| Type | width | opacity | path points |
|------|-------|---------|-------------|
| Pen | 2-3 | 1.0 | 10-100+ |
| Highlighter | 10-15 | 0.3 | 2-50+ |
| Dot | 3-5 | 1.0 | 1 |

### Text

```jsonc
{
  "color": "#000000",       // Required. Hex RGB color
  "fontSize": 16,           // Required. Font size in points (typical: 12-24)
  "point": [0.05, 0.1],    // Required. [x, y] position, normalized 0-1
  "str": "Hello world"     // Required. Text content (supports \n for line breaks)
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `color` | string | yes | Hex color `"#RRGGBB"` |
| `fontSize` | number | yes | Font size in points |
| `point` | number[] | yes | `[x, y]` position, normalized 0-1 |
| `str` | string | yes | Text content |

---

## API Endpoints

### GET /annotations?docId={docId}

Returns saved annotations for a document.

**Response:**
```json
{
  "annotations": [
    {
      "strokes": [
        {
          "color": "#ff0000",
          "width": 2,
          "opacity": 1,
          "path": [[0.1, 0.1], [0.4, 0.3]]
        },
        {
          "color": "#FFC107",
          "width": 12,
          "opacity": 0.3,
          "path": [[0.05, 0.15], [0.7, 0.15]]
        }
      ],
      "text": [
        {
          "color": "#000000",
          "fontSize": 14,
          "point": [0.05, 0.05],
          "str": "Note on page 1"
        }
      ]
    }
  ]
}
```

If no annotations exist, return `{ "annotations": null }` or `{ "annotations": [] }`.

### POST /annotations?docId={docId}

Saves annotations for a document. Replaces all existing annotations.

**Request body:**
```json
{
  "annotations": [
    {
      "strokes": [...],
      "text": [...]
    }
  ]
}
```

**Response:**
```json
{
  "ok": true,
  "pageCount": 17,
  "strokeCount": 102,
  "textCount": 51
}
```

---

## Client Data Flow

### Loading (read-only preview)

```
Backend GET → AnnotationPage[] → annotations prop → baked into bitmap
```

Annotations are rendered once into the page image. Not editable.

### Loading (editable)

```
Backend GET → AnnotationPage[] → loadAnnotations() → DrawingController
```

Annotations appear on transparent overlay. User can:
- Switch to erase mode and tap to delete
- Undo/redo changes
- Add new strokes and text
- Export all via `getAnnotations()`

### Saving

```
getAnnotations() → Record<pageIndex, {strokes, text}> → convert to array → POST
```

`getAnnotations()` returns a keyed object (`{"0": {...}, "2": {...}}`). Pages with no annotations are omitted. Client converts to array before sending to backend, filling gaps with empty pages:

```typescript
const result = await pdfRef.current.getAnnotations();
const pageKeys = Object.keys(result).map(Number);
const maxPage = Math.max(...pageKeys);
const annotations = [];
for (let i = 0; i <= maxPage; i++) {
  const page = result[String(i)];
  annotations.push({
    strokes: page?.strokes || [],
    text: page?.text || [],
  });
}
// POST { annotations }
```

**Note:** Exported strokes include `id` and `opacity` fields. The `id` field is ignored on load (fresh UUIDs are generated). Path points are simplified using the Ramer-Douglas-Peucker algorithm (epsilon=0.002) to reduce storage.

---

## Coordinate System

All coordinates are **normalized 0-1** relative to page dimensions:

```
(0, 0) ─────────────── (1, 0)
  │                       │
  │     PDF page area     │
  │                       │
(0, 1) ─────────────── (1, 1)
```

- `x = 0` → left edge
- `x = 1` → right edge
- `y = 0` → top edge
- `y = 1` → bottom edge

This means annotations are resolution-independent and work on any screen size.

---

## Database Schema Suggestion

```sql
CREATE TABLE document_annotations (
  id            SERIAL PRIMARY KEY,
  document_id   VARCHAR(255) NOT NULL,
  page_index    INTEGER NOT NULL,
  annotations   JSONB NOT NULL,  -- { "strokes": [...], "text": [...] }
  updated_at    TIMESTAMP DEFAULT NOW(),
  UNIQUE(document_id, page_index)
);
```

Or store as a single JSON blob per document:

```sql
CREATE TABLE document_annotations (
  document_id   VARCHAR(255) PRIMARY KEY,
  annotations   JSONB NOT NULL,  -- AnnotationPage[]
  updated_at    TIMESTAMP DEFAULT NOW()
);
```

---

## Validation Rules

- `color`: must match `/^#[0-9a-fA-F]{6}$/`
- `width`: positive number, typically 1-20
- `opacity`: 0-1, default 1
- `fontSize`: positive number, typically 8-72
- `path`: non-empty array, each element is `[x, y]` where both are 0-1
- `point`: exactly 2 elements `[x, y]` where both are 0-1
- `str`: non-empty string
- `strokes` and `text` arrays can be empty `[]`
- Page array length should match document page count (extra pages are ignored, missing pages get no annotations)
