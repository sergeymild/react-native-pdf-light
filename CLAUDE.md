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
- `AnnotationPage.swift` — PositionedText, Stroke, AnnotationPage (Decodable)
- `*Manager.swift` / `*.m` / `*.h` — RN bridge

### Android (`android/src/main/java/com/alpha0010/pdf/`)
- `ZoomablePdfScrollView.kt` — FrameLayout: RecyclerView + DrawingOverlayView (siblings). View scale transform zoom.
- `PagingPdfView.kt` — ViewPager2. ZoomablePageView per page (NestedScrollView → ImageView + DrawingOverlayView).
- `DrawablePdfView.kt` — Single-page with canvas transform zoom+drawing.
- `DrawingOverlayView.kt` — drawSinglePage (Paging, inside scaled parent) and drawMultiPage (Zoomable, manual zoom calc).
- `Common.kt` — DrawingMode, DrawingStroke, PageStrokes, DrawingController, PdfPageRenderer, parseAnnotations()
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