import type * as React from 'react';
import {
  codegenNativeCommands,
  codegenNativeComponent,
  type HostComponent,
  type ViewProps,
} from 'react-native';
import type {
  DirectEventHandler,
  Double,
  Int32,
} from 'react-native/Libraries/Types/CodegenTypes';

// --- Event data types ---

type PdfErrorEventData = Readonly<{ message: string }>;

type PdfLoadCompleteEventData = Readonly<{
  width: Double;
  height: Double;
  pageCount: Int32;
}>;

type PageChangeEventData = Readonly<{ page: Int32 }>;

type ZoomChangeEventData = Readonly<{ scale: Double }>;

type TapEventData = Readonly<{ position: string }>;

type UndoStateChangeEventData = Readonly<{
  canUndo: boolean;
  canRedo: boolean;
}>;

// --- Native Props ---

export interface NativeProps extends ViewProps {
  source: string;
  annotations?: string;
  minZoom?: Double;
  maxZoom?: Double;
  edgeTapZone?: Double;
  pdfBackgroundColor?: Int32;
  drawingMode?: string;
  strokeColor?: string;
  strokeWidth?: Double;
  strokeOpacity?: Double;
  textColor?: string;
  textFontSize?: Double;

  // Events
  onPdfError?: DirectEventHandler<PdfErrorEventData>;
  onPdfLoadComplete?: DirectEventHandler<PdfLoadCompleteEventData>;
  onPageChange?: DirectEventHandler<PageChangeEventData>;
  onZoomChange?: DirectEventHandler<ZoomChangeEventData>;
  onTap?: DirectEventHandler<TapEventData>;
  onMiddleClick?: DirectEventHandler<Readonly<{}>>;
  onDrawingStart?: DirectEventHandler<Readonly<{}>>;
  onDrawingEnd?: DirectEventHandler<Readonly<{}>>;
  onUndoStateChange?: DirectEventHandler<UndoStateChangeEventData>;
}

// --- Commands ---

type ComponentType = HostComponent<NativeProps>;

export interface NativeCommands {
  resetZoom: (viewRef: React.ElementRef<ComponentType>) => void;
  scrollToPage: (
    viewRef: React.ElementRef<ComponentType>,
    page: Int32,
    animated: boolean
  ) => void;
  clearStrokes: (
    viewRef: React.ElementRef<ComponentType>,
    page: Int32
  ) => void;
  undo: (viewRef: React.ElementRef<ComponentType>) => void;
  redo: (viewRef: React.ElementRef<ComponentType>) => void;
  loadAnnotations: (
    viewRef: React.ElementRef<ComponentType>,
    annotations: string
  ) => void;
}

export const Commands: NativeCommands =
  codegenNativeCommands<NativeCommands>({
    supportedCommands: [
      'resetZoom',
      'scrollToPage',
      'clearStrokes',
      'undo',
      'redo',
      'loadAnnotations',
    ],
  });

export default codegenNativeComponent<NativeProps>(
  'RNPagingPdfView'
) as ComponentType;
