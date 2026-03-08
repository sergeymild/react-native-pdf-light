import React, { useCallback, useRef, useMemo, useState } from 'react';
import {
  StyleSheet,
  View,
  Text,
  TouchableOpacity,
  SafeAreaView,
  Alert,
} from 'react-native';
import {
  PdfViewer,
  type NativeZoomablePdfScrollViewRef,
  type DrawingMode,
  type DrawingTool,
  DEFAULT_DRAWING_TOOL,
  DEFAULT_HIGHLIGHTER_TOOL,
  type AnnotationPage,
} from 'react-native-pdf-light';
import { useAsset } from '../assets.utils';
import { PageIndicator, type PageIndicatorRef } from '../PageIndicator';

type Props = {
  onBack: () => void;
};

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

export function DrawingScreen({ onBack }: Props) {
  const source = useAsset(require('../assets/caldara.pdf'));
  const pdfViewRef = useRef<NativeZoomablePdfScrollViewRef>(null);
  const pageIndicatorRef = useRef<PageIndicatorRef>(null);

  const [drawingMode, setDrawingMode] = useState<DrawingMode>('view');

  const drawingTool: DrawingTool = useMemo(() => {
    if (drawingMode === 'highlight') {
      return DEFAULT_HIGHLIGHTER_TOOL;
    }
    return DEFAULT_DRAWING_TOOL;
  }, [drawingMode]);

  const handleLoadComplete = useCallback(
    (event: { width: number; height: number; pageCount: number }) => {
      console.log('Drawing PDF loaded:', event);
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

  const annotations = useMemo<AnnotationPage[]>(
    () => [
      { strokes: [], text: [] },
      {
        strokes: [
          {
            color: '#ff0000',
            width: 3,
            path: [
              [0.1, 0.1],
              [0.9, 0.1],
              [0.9, 0.2],
              [0.1, 0.2],
              [0.1, 0.1],
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

  const handleSave = useCallback(async () => {
    const result = await pdfViewRef.current?.getAnnotations();
    if (result) {
      const strokeCount = Object.values(result).reduce(
        (sum, strokes) => sum + strokes.length,
        0
      );
      console.log('Annotations:', JSON.stringify(result, null, 2));
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
      <View style={styles.header}>
        <TouchableOpacity onPress={onBack} style={styles.backButton}>
          <Text style={styles.backText}>Back</Text>
        </TouchableOpacity>
        <Text style={styles.title}>Drawing Mode</Text>
        <View style={styles.placeholder} />
      </View>

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
        viewerType="zoomable"
        ref={pdfViewRef}
        source={source}
        minZoom={1}
        maxZoom={2}
        backgroundColor="#ffffff"
        edgeTapZone={30}
        annotations={annotations}
        drawingMode={drawingMode}
        drawingTool={drawingTool}
        onDrawingStart={() => console.log('Drawing started')}
        onDrawingEnd={() => console.log('Drawing ended')}
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
    backgroundColor: '#FF9800',
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
