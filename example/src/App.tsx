import React, { useCallback, useRef, useMemo, useState } from 'react';
import {
  NativeZoomablePdfScrollViewRef,
  PdfViewer,
  type DrawingMode,
  type DrawingTool,
  DEFAULT_DRAWING_TOOL,
  DEFAULT_HIGHLIGHTER_TOOL,
  type AnnotationPage,
} from 'react-native-pdf-light';
import { useAsset } from './assets.utils';
import {
  StyleSheet,
  View,
  TouchableOpacity,
  Text,
  SafeAreaView,
  Alert,
} from 'react-native';
import { PageIndicator, type PageIndicatorRef } from './PageIndicator';

type ModeButton = {
  mode: DrawingMode;
  label: string;
  color: string;
};

const MODES: ModeButton[] = [
  { mode: 'view', label: 'View', color: '#4CAF50' },
  { mode: 'draw', label: 'Draw', color: '#2196F3' },
  { mode: 'highlight', label: 'Highlight', color: '#FFC107' },
  { mode: 'erase', label: 'Erase', color: '#f44336' },
];

export default function App() {
  const source = useAsset(require('./assets/caldara.pdf'));

  const pdfViewRef = useRef<NativeZoomablePdfScrollViewRef>(null);
  const pageIndicatorRef = useRef<PageIndicatorRef>(null);

  // Drawing state
  const [drawingMode, setDrawingMode] = useState<DrawingMode>('view');

  // Drawing tool based on mode
  const drawingTool: DrawingTool = useMemo(() => {
    if (drawingMode === 'highlight') {
      return DEFAULT_HIGHLIGHTER_TOOL;
    }
    return DEFAULT_DRAWING_TOOL;
  }, [drawingMode]);

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

  const handleClearAll = useCallback(() => {
    pdfViewRef.current?.clearStrokes(-1);
  }, []);

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

  // Get annotations from native and show them
  const handleSave = useCallback(async () => {
    const annotations = await pdfViewRef.current?.getAnnotations();
    if (annotations) {
      const strokeCount = Object.values(annotations).reduce(
        (sum, strokes) => sum + strokes.length,
        0
      );
      console.log('Annotations:', JSON.stringify(annotations, null, 2));
      Alert.alert(
        'Annotations',
        `Total strokes: ${strokeCount}\n\nCheck console for full data.`
      );
    }
  }, []);

  if (!source) {
    return null;
  }

  return (
    <SafeAreaView style={styles.container}>
      {/* Mode toolbar */}
      <View style={styles.toolbar}>
        {MODES.map((btn) => (
          <TouchableOpacity
            key={btn.mode}
            style={[
              styles.modeButton,
              { backgroundColor: btn.color },
              drawingMode === btn.mode && styles.modeButtonActive,
            ]}
            onPress={() => setDrawingMode(btn.mode)}
          >
            <Text
              style={[
                styles.modeButtonText,
                drawingMode === btn.mode && styles.modeButtonTextActive,
              ]}
            >
              {btn.label}
            </Text>
          </TouchableOpacity>
        ))}
        <TouchableOpacity style={styles.clearButton} onPress={handleClearAll}>
          <Text style={styles.clearButtonText}>Clear</Text>
        </TouchableOpacity>
        <TouchableOpacity style={styles.saveButton} onPress={handleSave}>
          <Text style={styles.saveButtonText}>Save</Text>
        </TouchableOpacity>
      </View>

      <PdfViewer
        viewerType="paging"
        ref={pdfViewRef}
        source={source}
        minZoom={1}
        maxZoom={2}
        backgroundColor="#ffffff"
        edgeTapZone={30}
        // Drawing props
        annotations={annotations}
        drawingMode={drawingMode}
        drawingTool={drawingTool}
        onDrawingStart={() => console.log('Drawing started')}
        onDrawingEnd={() => console.log('Drawing ended')}
        // Other callbacks
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
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#333',
  },
  toolbar: {
    flexDirection: 'row',
    paddingHorizontal: 10,
    paddingVertical: 8,
    backgroundColor: '#222',
    gap: 8,
  },
  modeButton: {
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 6,
    opacity: 0.6,
  },
  modeButtonActive: {
    opacity: 1,
    borderWidth: 2,
    borderColor: '#fff',
  },
  modeButtonText: {
    color: '#fff',
    fontSize: 13,
    fontWeight: '500',
  },
  modeButtonTextActive: {
    fontWeight: '700',
  },
  clearButton: {
    marginLeft: 'auto',
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 6,
    backgroundColor: '#666',
  },
  clearButtonText: {
    color: '#fff',
    fontSize: 13,
    fontWeight: '500',
  },
  saveButton: {
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 6,
    backgroundColor: '#4CAF50',
  },
  saveButtonText: {
    color: '#fff',
    fontSize: 13,
    fontWeight: '500',
  },
  pdfView: {
    flex: 1,
  },
});
