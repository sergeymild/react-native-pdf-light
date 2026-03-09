# react-native-pdf-light — Project Context

## Overview
React Native PDF viewer library with drawing/annotation support.
Two viewer modes: **Zoomable** (vertical scroll + global zoom) and **Paging** (horizontal swipe + per-page zoom).
Both iOS (Swift) and Android (Kotlin).

## Viewer Types

| | Zoomable | Paging |
|---|---|---|
| **Scroll** | Vertical (all pages) | Horizontal (one page at a time) |
| **Zoom** | Global (all pages zoom together) | Per-page |
| **iOS** | UIScrollView + UICollectionView | Per-page scroll views |
| **Android** | RecyclerView + view scale transform | ViewPager2 + NestedScrollView |

## File Map

### TypeScript (`src/`)
- `index.ts` — Exports: PdfViewer, NativeZoomablePdfScrollView, drawing types/tools
- `PdfViewer.tsx` — Unified component. Routes by `viewerType` prop. Defines AnnotationPage/Stroke/Text types.
- `NativeZoomablePdfScrollView.tsx` — Zoomable wrapper. Ref: resetZoom, scrollToPage, clearStrokes, getAnnotations.
- `NativePagingPdfView.tsx` — Paging wrapper. Similar API.
- `drawing/types.ts` — DrawingMode, DrawingTool, DrawingStroke, DEFAULT_DRAWING_TOOL, DEFAULT_HIGHLIGHTER_TOOL
- `PdfUtil.ts` — getPageCount(), getPageSizes()

### iOS (`ios/`)
- `ZoomablePdfScrollView.swift` — UIScrollView zoom + UICollectionView. DrawingOverlayView on content.
- `PagingPdfView.swift` — Horizontal paging. Per-page ZoomablePageView + DrawingOverlayView.
- `DrawablePdfView.swift` — Single-page drawable view
- `DrawingController.swift` — Touch handling, stroke storage (PageStrokes), erase, rendering (CGContext), export with RDP simplification
- `DrawingOverlayView.swift` — CATiledLayer overlay. Single/multi-page modes. Handles touch in draw modes.
- `DrawingTypes.swift` — DrawingMode enum, DrawingStroke struct, PageStrokes container
- `Common.swift` — PdfPageRenderer (2x retina), UIColor hex ext. Draws static annotations onto bitmap.
- `TextAnnotationHandler.swift` — Reusable text input/drag handler. Delegate pattern.
- `AnnotationPage.swift` — PositionedText, Stroke, AnnotationPage (Decodable)
- `*Manager.swift` / `*.m` / `*.h` — RN bridge

### Android (`android/src/main/java/com/alpha0010/pdf/`)
- `ZoomablePdfScrollView.kt` — FrameLayout: RecyclerView + DrawingOverlayView (siblings). View scale transform zoom.
- `PagingPdfView.kt` — ViewPager2. ZoomablePageView per page (NestedScrollView → ImageView + DrawingOverlayView).
- `DrawablePdfView.kt` — Single-page with canvas transform zoom+drawing.
- `DrawingOverlayView.kt` — drawSinglePage (Paging, inside scaled parent) and drawMultiPage (Zoomable, manual zoom calc). Also renders text annotations.
- `Common.kt` — DrawingMode, DrawingStroke, DrawingText, PageStrokes, PageTexts, DrawingController, PdfPageRenderer, parseAnnotations()
- `TextAnnotationHandler.kt` — Reusable text input/drag/hit-test handler. Delegate pattern + coordinate converter lambdas.
- `AnnotationPage.kt` — Data classes (Serializable)
- `*Manager.kt` / `PdfViewPackage.kt` — RN bridge

### Example (`example/src/`)
- `screens/DrawingScreen.tsx` — Drawing demo (viewerType="zoomable"), mode buttons, clear, save
- `screens/ZoomablePdfScreen.tsx` / `PagingPdfScreen.tsx` — Viewer demos
- `assets/caldara.pdf` — Test PDF

## Drawing System

### Two annotation types
1. **Static annotations** (from `annotations` prop) — baked into page bitmap at render time
2. **User drawings** (via DrawingController) — rendered real-time on transparent DrawingOverlayView

### Coordinate system
- All stroke points: **normalized 0-1** relative to page dimensions
- Touch: screen → content (undo zoom/pan/scroll) → normalized
- Render: normalized → content → canvas

### DrawingController (shared logic, per-platform)
- `pageStrokes: PageStrokes` — completed strokes per page (dict: page→[DrawingStroke])
- `activeStroke` — currently being drawn
- `handleTouchBegan/Moved/Ended` — touch pipeline
- Erase: distance threshold (iOS: 5%, Android: 3%)
- Export: `getAnnotationsForExport()` with RDP path simplification (iOS epsilon=1.5, Android epsilon=0.002)

### DrawingOverlayView per viewer

| Viewer | Platform | Overlay Position | Zoom Handling |
|--------|----------|-----------------|---------------|
| Zoomable | iOS | Inside UIScrollView content | UIScrollView handles zoom |
| Zoomable | Android | **Sibling** of RecyclerView | Manual calc (zoomScale, offsetX, scrollOffset, recyclerPaddingTop) |
| Paging | iOS | Inside per-page scroll content | Scroll view handles zoom |
| Paging | Android | **Inside** per-page NestedScrollView | Parent view transform (inherits scale) |
| Drawable | Android | N/A (same view draws everything) | Canvas translate+scale |

### Static annotations rendering
- Baked into page bitmap in PdfPageRenderer (both platforms)
- iOS: 2x retina, UIGraphicsImageRenderer
- Android: Canvas(bitmap) after PdfRenderer
- Format: `AnnotationPage { strokes: [{color, width, path}], text: [{color, fontSize, point, str}] }`

### Key gotchas
1. **Android Zoomable overlay is sibling of RV** — must manually track zoom/scroll/paddingTop
2. **Android RV paddingTop changes during zoom** — `recyclerPaddingTop` must be passed to overlay
3. **Stroke width**: iOS divides by zoomScale, Android multipage multiplies by zoomScale, Android singlepage uses 1 (parent scales)
4. **Static vs user annotations**: Completely separate. Static = baked in bitmap. User = live overlay.
5. **Android PagingPdfView zoom reset**: `notifyDataSetChanged()` triggers `onBindViewHolder` → `resetState()` which resets zoom. Setters like `setDrawingMode`, `setAnnotations`, `setPdfBackgroundColor` must guard against redundant calls. `setDrawingMode` uses `invalidateCurrentPage()` instead of `notifyDataSetChanged`.
6. **Android RN Yoga layout vs dynamic views**: Views added dynamically to RN-managed ViewGroups (PagingPdfView, ZoomablePdfScrollView) don't get measured/laid out by Yoga. Must manually call `measure()` + `layout()` on EditText and drag label.
7. **iOS PagingPdfView zoom reset**: `updateImageViewFrame` must NOT set `contentContainer.frame` during active zoom (UIScrollView transform conflict). Use `bounds`/`center` and guard with `scrollView.zoomScale != 1.0`.

## Text Annotation System

### Architecture
- **iOS**: `TextAnnotationHandler.swift` — delegate pattern, reused by both viewers
- **Android**: `TextAnnotationHandler.kt` — delegate pattern + converter lambdas, reused by both viewers

### Android TextAnnotationHandler
- `TextAnnotationHandlerDelegate` interface: drawingController, contentContainer, hostView, zoomScale, contentRectForPage, pageForPoint, redrawOverlay
- `screenToContentConverter` lambda: touch coords → content coords (accounts for zoom, scroll, padding)
- `contentToScreenConverter` lambda: content coords → screen coords (inverse of above)
- EditText for input: added to hostView, manually measured (`EXACTLY` width spec for non-zero width) and laid out
- Drag label (TextView): added to hostView (PagingPdfView uses `rootOverlayContainer` to avoid ViewPager2 z-order issues), manually measured and laid out via `label.layout()`
- Font size scaled by `zoomScale` for both EditText and drag label (they're outside the zoom transform hierarchy)

### Coordinate converters per viewer (Android)
| | screenToContent | contentToScreen |
|---|---|---|
| **Zoomable** | `x = (eventX - offsetX) / scale`, `y = eventY / scale - paddingTop + scrollOffset` | `x = contentX * scale + offsetX`, `y = (contentY - scrollOffset + paddingTop) * scale` |
| **Paging** | `x = (eventX - offsetX) / scale`, `y = eventY / scale + scrollView.scrollY` | `x = contentX * scale + offsetX`, `y = (contentY - scrollView.scrollY) * scale` |

### iOS TextAnnotationHandler
- Drag uses `touch.location(in: contentContainer)` directly — avoids contentOffset dependency
- `draggingTouchOffset` stored in hostView coords, converted via zoomScale on finish
- Erase mode also deletes text annotations (hit-test in `DrawingController.eraseStroke`)

## Props
- `source` — file path to PDF
- `viewerType` — 'zoomable' | 'paging'
- `annotations` — AnnotationPage[] (static, baked into bitmap)
- `drawingMode` — 'view' | 'draw' | 'erase' | 'highlight'
- `drawingTool` — { color, strokeWidth, opacity }
- `minZoom`/`maxZoom`, `edgeTapZone`, `backgroundColor`
- `pdfPaddingTop`/`pdfPaddingBottom` (zoomable only)
- Events: onLoadComplete, onPageChange, onZoomChange, onTap, onMiddleClick, onDrawingStart, onDrawingEnd, onStrokeEnd, onStrokeRemoved
- Ref: `resetZoom()`, `scrollToPage()`, `clearStrokes(page)`, `getAnnotations()`

## Build
- react-native-builder-bob (commonjs, module, typescript)
- iOS: Swift, min iOS 10, CocoaPods
- Android: Kotlin, minSdk 21, coroutines, serialization, viewpager2, recyclerview