import React, { useCallback, useEffect, useRef, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import {
  NativeDrawablePdfView,
  NativeDrawablePdfViewRef,
} from 'react-native-pdf-light';
import { DrawingToolbar } from './DrawingToolbar';
import { PageIndicator, PageIndicatorRef } from './PageIndicator';
import {
  PdfViewer,
  PdfViewerRef,
  RenderPageProps,
  ViewMode,
} from './PdfViewer';
import { useDrawing } from './useDrawing';
import { useAsset } from './assets.utils';

export default function DrawerView() {
  const data = useAsset('sample.pdf');
  const [viewMode, setViewMode] = useState<ViewMode>('horizontal');
  const [isLandscape, setIsLandscape] = useState(false);

  const pdfViewerRef = useRef<PdfViewerRef>(null);
  const pdfViewRefs = useRef<Map<number, NativeDrawablePdfViewRef>>(new Map());
  const currentPageRef = useRef(0);
  const pageIndicatorRef = useRef<PageIndicatorRef>(null);

  // Drawing hook
  const {
    drawingMode,
    drawingTool,
    showColorPicker,
    showStrokePicker,
    pageStrokes,
    setShowColorPicker,
    setShowStrokePicker,
    handleDrawingStart,
    handleDrawingEnd,
    handleStrokeEnd,
    handleStrokeRemoved,
    handleStrokesCleared,
    selectMode,
    selectColor,
    selectStrokeWidth,
  } = useDrawing();

  const clearCurrentPage = useCallback(() => {
    const currentPage = currentPageRef.current;
    pdfViewRefs.current?.get(currentPage)?.clearStrokes();
  }, []);

  // Load page count
  useEffect(() => {
    pageIndicatorRef.current?.setPageCount(data?.pages ?? 0);
  }, [data]);

  // Track zoom state for scroll control
  const [isZoomed, setIsZoomed] = useState(false);

  const handleZoomChange = useCallback((event: { scale: number }) => {
    const zoomed = event.scale > 1.01;
    setIsZoomed(zoomed);
  }, []);

  // Update scroll enabled state based on drawing mode and zoom
  useEffect(() => {
    const shouldScroll = drawingMode === 'view' && !isZoomed;
    pdfViewerRef.current?.setScrollEnabled(shouldScroll);
  }, [drawingMode, isZoomed]);

  const handlePageChange = useCallback((page: number) => {
    currentPageRef.current = page;
    pageIndicatorRef.current?.setPage(page);
  }, []);

  const handleViewModeChange = useCallback(
    (_mode: ViewMode, landscape: boolean) => {
      setIsLandscape(landscape);
    },
    []
  );

  const toggleViewMode = useCallback(() => {
    setViewMode((prev) => (prev === 'horizontal' ? 'vertical' : 'horizontal'));
  }, []);

  // Render page with drawing support
  const renderPage = useCallback(
    ({
      pageIndex,
      setRef,
      resizeMode,
      onLoadComplete,
      onSingleTap,
    }: RenderPageProps) => {
      const combinedSetRef = (ref: NativeDrawablePdfViewRef | null) => {
        if (ref) {
          pdfViewRefs.current.set(pageIndex, ref);
          setRef(ref);
        }
      };

      return (
        <NativeDrawablePdfView
          ref={combinedSetRef}
          source={data!.path!}
          page={pageIndex}
          onError={console.warn}
          onLoadComplete={onLoadComplete}
          resizeMode={resizeMode}
          drawingMode={drawingMode}
          drawingTool={drawingTool}
          strokes={pageStrokes.get(pageIndex) || []}
          zoomEnabled={resizeMode === 'contain'}
          onDrawingStart={handleDrawingStart}
          onDrawingEnd={handleDrawingEnd}
          onStrokeEnd={(stroke) => handleStrokeEnd(stroke, pageIndex)}
          onStrokeRemoved={(strokeId) =>
            handleStrokeRemoved(strokeId, pageIndex)
          }
          onStrokesCleared={() => handleStrokesCleared(pageIndex)}
          onZoomChange={handleZoomChange}
          onSingleTap={onSingleTap}
          style={styles.pdfView}
        />
      );
    },
    [
      data,
      drawingMode,
      drawingTool,
      pageStrokes,
      handleDrawingStart,
      handleDrawingEnd,
      handleStrokeEnd,
      handleStrokeRemoved,
      handleStrokesCleared,
      handleZoomChange,
    ]
  );

  if (!data) {
    return null;
  }

  return (
    <View style={styles.container}>
      <PdfViewer
        ref={pdfViewerRef}
        source={data.path!}
        pageCount={data.pages}
        viewMode={viewMode}
        onPageChange={handlePageChange}
        onViewModeChange={handleViewModeChange}
        renderPage={renderPage}
        scrollEnabled={drawingMode === 'view' && !isZoomed}
      />

      <DrawingToolbar
        drawingMode={drawingMode}
        drawingTool={drawingTool}
        showColorPicker={showColorPicker}
        showStrokePicker={showStrokePicker}
        isLandscape={isLandscape}
        onModeChange={selectMode}
        onColorChange={selectColor}
        onStrokeWidthChange={selectStrokeWidth}
        onColorPickerToggle={setShowColorPicker}
        onStrokePickerToggle={setShowStrokePicker}
        onClear={clearCurrentPage}
      />

      <PageIndicator
        ref={pageIndicatorRef}
        initialPage={0}
        initialPageCount={data.pages}
      />

      {/* Toggle button (portrait only) */}
      {!isLandscape && (
        <Pressable style={styles.toggleButton} onPress={toggleViewMode}>
          <Text style={styles.toggleText}>
            {viewMode === 'horizontal' ? 'Vertical' : 'Horizontal'}
          </Text>
        </Pressable>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  pdfView: {
    flex: 1,
  },
  toggleButton: {
    position: 'absolute',
    top: 50,
    right: 20,
    backgroundColor: 'rgba(0, 0, 0, 0.7)',
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderRadius: 20,
  },
  toggleText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '600',
  },
});
