# react-native-pdf-light

[![npm version](https://img.shields.io/npm/v/react-native-pdf-light)](https://www.npmjs.com/package/react-native-pdf-light)
![CI](https://github.com/alpha0010/react-native-pdf-viewer/workflows/CI/badge.svg)

Native PDF viewer for React Native with pinch-to-zoom and page navigation support.

Uses `android.graphics.pdf.PdfRenderer` on Android and `CGPDFDocument` on iOS.

## Installation

```sh
npm install react-native-pdf-light
```

If iOS build fails with `Undefined symbol: __swift_FORCE_LOAD_...`, add an
empty `.swift` file to the xcode project.

## Usage

```tsx
import { PdfViewer } from 'react-native-pdf-light';

// Zoomable scrolling viewer (iOS only)
<PdfViewer
  viewerType="zoomable"
  source="/path/to/document.pdf"
  onLoadComplete={({ pageCount }) => console.log(`Loaded ${pageCount} pages`)}
  onPageChange={(page) => console.log(`Current page: ${page}`)}
/>

// Paging viewer with horizontal swipe (iOS & Android)
<PdfViewer
  viewerType="paging"
  source="/path/to/document.pdf"
  onLoadComplete={({ pageCount }) => console.log(`Loaded ${pageCount} pages`)}
/>
```

## Components

### `<PdfViewer />`

Main PDF viewer component with two display modes.

#### Common Props

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `viewerType` | `'zoomable' \| 'paging'` | required | Viewer display mode |
| `source` | `string` | required | Path to PDF document |
| `minZoom` | `number` | `1` | Minimum zoom level |
| `maxZoom` | `number` | `3` | Maximum zoom level |
| `edgeTapZone` | `number` | `15` | Edge tap zone size as percentage (0-50) |
| `backgroundColor` | `string` | - | Background color behind PDF pages |
| `onError` | `(event: PdfErrorEvent) => void` | - | Callback when an error occurs |
| `onLayout` | `(event: LayoutChangeEvent) => void` | - | Callback for measuring the native view |
| `onLoadComplete` | `(event: PdfLoadCompleteEvent) => void` | - | Callback when PDF load completes |
| `onPageChange` | `(page: number) => void` | - | Callback when current page changes |
| `onZoomChange` | `(scale: number) => void` | - | Callback when zoom level changes |
| `onTap` | `(position: 'top' \| 'bottom' \| 'left' \| 'right') => void` | - | Callback when user taps on edge zones |
| `onMiddleClick` | `() => void` | - | Callback when user taps in the middle zone |
| `style` | `ViewStyle` | - | View stylesheet |

#### Zoomable Viewer Props (`viewerType="zoomable"`)

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `pdfPaddingTop` | `number` | `0` | Extra padding at the top of scroll content (points) |
| `pdfPaddingBottom` | `number` | `0` | Extra padding at the bottom of scroll content (points) |

**Platform support:** iOS only

**Features:**
- Pinch-to-zoom entire document
- Vertical scrolling through pages
- Smooth native scrolling and zooming

#### Paging Viewer Props (`viewerType="paging"`)

**Platform support:** iOS & Android

**Features:**
- Horizontal page swiping (like a book)
- Per-page pinch-to-zoom
- Page swiping is disabled while zoomed in
- Double-tap to zoom in/out

#### Methods (via ref)

```tsx
const pdfRef = useRef<PdfViewerRef>(null);

// Reset zoom to default (scale = 1)
pdfRef.current?.resetZoom();

// Scroll to specific page (0-indexed)
pdfRef.current?.scrollToPage(5, true); // animated
```

#### Event Types

```tsx
type PdfErrorEvent = { message: string };

type PdfLoadCompleteEvent = {
  width: number;
  height: number;
  pageCount: number;
};
```

### `<NativeZoomablePdfScrollView />`

Low-level native scrollable PDF viewer with global zoom support. Available as a direct export for advanced use cases.

```tsx
import { NativeZoomablePdfScrollView } from 'react-native-pdf-light';
```

## Alternatives

- [react-native-pdf](https://github.com/wonday/react-native-pdf)
- [react-native-file-viewer](https://github.com/vinzscam/react-native-file-viewer)
- [react-native-view-pdf](https://github.com/rumax/react-native-PDFView)
- [rn-pdf-reader-js](https://github.com/xcarpentier/rn-pdf-reader-js)

## Contributing

See the [contributing guide](CONTRIBUTING.md) to learn how to contribute to the repository and the development workflow.

## License

MIT
