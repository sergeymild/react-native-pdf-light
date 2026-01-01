import React, { useCallback, useRef, useMemo } from 'react';
import {
  NativeZoomablePdfScrollViewRef,
  PdfViewer,
  type AnnotationPage,
} from 'react-native-pdf-light';
import { useAsset } from './assets.utils';
import { StyleSheet, View } from 'react-native';
import { PageIndicator, type PageIndicatorRef } from './PageIndicator';

export default function App() {
  const source = useAsset(require('./assets/caldara.pdf'));

  const pdfViewRef = useRef<NativeZoomablePdfScrollViewRef>(null);
  const pageIndicatorRef = useRef<PageIndicatorRef>(null);

  // Example annotations - red rectangle on page 2 and text
  const annotations = useMemo<AnnotationPage[]>(
    () => [
      // Page 1 - no annotations
      { strokes: [], text: [] },
      // Page 2 - red rectangle and text annotation
      {
        strokes: [
          {
            color: '#ff0000',
            width: 3,
            path: [
              [0.1, 0.1], // top-left
              [0.9, 0.1], // top-right
              [0.9, 0.2], // bottom-right
              [0.1, 0.2], // bottom-left
              [0.1, 0.1], // close rectangle
            ],
          },
        ],
        text: [
          {
            color: '#0000ff',
            fontSize: 16,
            point: [0.1, 0.25],
            str: 'This is an annotation!',
          },
        ],
      },
    ],
    []
  );

  const handleLoadComplete = useCallback(
    (event: { width: number; height: number; pageCount: number }) => {
      console.log('PDF loaded:', event);
      pageIndicatorRef.current?.setPageCount(event.pageCount);
    },
    []
  );

  const handlePageChange = useCallback((page: number) => {
    pageIndicatorRef.current?.setPage(page);
  }, []);

  const handleZoomChange = useCallback((scale: number) => {
    console.log('Zoom:', scale);
  }, []);

  const handleResetZoom = useCallback(() => {
    pdfViewRef.current?.resetZoom();
  }, []);

  if (!source) {
    return null;
  }

  return (
    <View style={styles.container}>
      <PdfViewer
        viewerType="zoomable"
        ref={pdfViewRef}
        source={source}
        annotations={annotations}
        minZoom={1}
        maxZoom={2}
        backgroundColor="#ffffff"
        edgeTapZone={30}
        onLoadComplete={handleLoadComplete}
        onPageChange={handlePageChange}
        onZoomChange={handleZoomChange}
        onError={(e) => console.warn('PDF Error:', e.message)}
        onMiddleClick={() => {
          console.log('[App.onMiddleClick]');
        }}
        style={styles.pdfView}
      />

      <PageIndicator
        ref={pageIndicatorRef}
        initialPage={0}
        initialPageCount={0}
      />
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
  resetButton: {
    position: 'absolute',
    top: 50,
    right: 20,
    backgroundColor: 'rgba(0, 0, 0, 0.7)',
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderRadius: 20,
  },
  resetText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '600',
  },
});
