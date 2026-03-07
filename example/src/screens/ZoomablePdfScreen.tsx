import React, { useCallback, useRef } from 'react';
import { StyleSheet, View, Text, TouchableOpacity } from 'react-native';
import {
  PdfViewer,
  type NativeZoomablePdfScrollViewRef,
} from 'react-native-pdf-light';
import { useAsset } from '../assets.utils';
import { PageIndicator, type PageIndicatorRef } from '../PageIndicator';

type Props = {
  onBack: () => void;
};

export function ZoomablePdfScreen({ onBack }: Props) {
  const source = useAsset(require('../assets/caldara.pdf'));
  const pdfViewRef = useRef<NativeZoomablePdfScrollViewRef>(null);
  const pageIndicatorRef = useRef<PageIndicatorRef>(null);

  const handleLoadComplete = useCallback(
    (event: { width: number; height: number; pageCount: number }) => {
      console.log('Zoomable PDF loaded:', event);
      pageIndicatorRef.current?.setPageCount(event.pageCount);
    },
    []
  );

  const handlePageChange = useCallback((page: number) => {
    pageIndicatorRef.current?.setPage(page);
  }, []);

  const handleZoomChange = useCallback((scale: number) => {
    console.log('Zoom scale:', scale);
  }, []);

  const handleResetZoom = useCallback(() => {
    pdfViewRef.current?.resetZoom();
  }, []);

  if (!source) {
    return null;
  }

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <TouchableOpacity onPress={onBack} style={styles.backButton}>
          <Text style={styles.backText}>Back</Text>
        </TouchableOpacity>
        <Text style={styles.title}>Zoomable Mode</Text>
        <TouchableOpacity onPress={handleResetZoom} style={styles.resetButton}>
          <Text style={styles.resetText}>Reset</Text>
        </TouchableOpacity>
      </View>

      <PdfViewer
        viewerType="zoomable"
        ref={pdfViewRef}
        source={source}
        minZoom={1}
        maxZoom={5}
        pdfPaddingTop={20}
        pdfPaddingBottom={20}
        backgroundColor="#e8e8e8"
        edgeTapZone={20}
        onLoadComplete={handleLoadComplete}
        onPageChange={handlePageChange}
        onZoomChange={handleZoomChange}
        onError={(e) => console.warn('PDF Error:', e.message)}
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
    backgroundColor: '#fff',
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingTop: 50,
    paddingHorizontal: 16,
    paddingBottom: 12,
    backgroundColor: '#34C759',
  },
  backButton: {
    padding: 8,
  },
  backText: {
    color: '#fff',
    fontSize: 16,
  },
  title: {
    color: '#fff',
    fontSize: 18,
    fontWeight: '600',
  },
  resetButton: {
    padding: 8,
  },
  resetText: {
    color: '#fff',
    fontSize: 16,
  },
  pdfView: {
    flex: 1,
  },
});