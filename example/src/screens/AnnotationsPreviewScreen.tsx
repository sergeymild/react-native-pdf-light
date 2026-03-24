import React, { useCallback, useEffect, useRef, useState } from 'react';
import {
  StyleSheet,
  View,
  Text,
  TouchableOpacity,
  SafeAreaView,
  ActivityIndicator,
} from 'react-native';
import {
  PdfViewer,
  type AnnotationPage,
} from 'react-native-pdf-light';
import { useAsset } from '../assets.utils';
import { PageIndicator, type PageIndicatorRef } from '../PageIndicator';

const API_BASE = 'http://192.168.1.124:3001';
const DOC_ID = 'caldara';

type Props = {
  onBack: () => void;
};

export function AnnotationsPreviewScreen({ onBack }: Props) {
  const source = useAsset(require('../assets/caldara.pdf'));
  const pageIndicatorRef = useRef<PageIndicatorRef>(null);
  const [annotations, setAnnotations] = useState<AnnotationPage[] | undefined>(undefined);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const url = `${API_BASE}/annotations?docId=${DOC_ID}`;
    console.log('[Preview] Fetching annotations from:', url);
    (async () => {
      try {
        const controller = new AbortController();
        const timeout = setTimeout(() => {
          console.log('[Preview] Fetch timed out after 3s');
          controller.abort();
        }, 3000);
        const res = await fetch(url, { signal: controller.signal });
        clearTimeout(timeout);
        console.log('[Preview] Fetch status:', res.status);
        const data = await res.json();
        const pages = data.annotations ?? [];
        console.log('[Preview] Got', pages.length, 'pages');
        if (pages.length > 0) {
          const p0 = pages[0];
          console.log('[Preview] Page 0:', p0.strokes?.length, 'strokes,', p0.text?.length, 'texts');
        }
        setAnnotations(pages);
      } catch (e: any) {
        console.warn('[Preview] Fetch error:', e.message || e);
        setAnnotations([]);
      } finally {
        console.log('[Preview] Loading complete, annotations set');
        setLoading(false);
      }
    })();
  }, []);

  const handleLoadComplete = useCallback(
    (event: { pageCount: number }) => {
      console.log('[Preview] PDF loaded, pageCount:', event.pageCount, 'annotations:', annotations?.length);
      pageIndicatorRef.current?.setPageCount(event.pageCount);
    },
    [annotations]
  );

  const handlePageChange = useCallback((page: number) => {
    pageIndicatorRef.current?.setPage(page);
  }, []);

  if (!source || loading) {
    return (
      <SafeAreaView style={styles.container}>
        <ActivityIndicator size="large" color="#fff" style={{ flex: 1 }} />
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <TouchableOpacity onPress={onBack} style={styles.backButton}>
          <Text style={styles.backText}>Back</Text>
        </TouchableOpacity>
        <Text style={styles.title}>Annotations Preview</Text>
        <View style={styles.placeholder} />
      </View>

      <PdfViewer
        viewerType="zoomable"
        source={source}
        minZoom={1}
        maxZoom={3}
        backgroundColor="#ffffff"
        annotations={annotations}
        onLoadComplete={handleLoadComplete}
        onPageChange={handlePageChange}
        style={styles.pdfView}
      />

      <PageIndicator
        ref={pageIndicatorRef}
        initialPage={0}
        initialPageCount={0}
      />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#333',
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 12,
    backgroundColor: '#673AB7',
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
  placeholder: {
    width: 50,
  },
  pdfView: {
    flex: 1,
  },
});
