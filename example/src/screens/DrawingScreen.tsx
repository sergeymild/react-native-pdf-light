import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  StyleSheet,
  View,
  Text,
  TouchableOpacity,
  SafeAreaView,
  Alert,
  ScrollView,
  Platform,
  ActivityIndicator,
} from 'react-native';
import {
  PdfViewer,
  type NativeZoomablePdfScrollViewRef,
  type DrawingMode,
  type DrawingTool,
  DEFAULT_DRAWING_TOOL,
  DEFAULT_HIGHLIGHTER_TOOL,
  DEFAULT_TEXT_TOOL,
  type AnnotationPage,
} from 'react-native-pdf-light';
import { useAsset } from '../assets.utils';
import { PageIndicator, type PageIndicatorRef } from '../PageIndicator';

// Use your computer's local network IP for real devices
const API_BASE = 'http://192.168.1.124:3001';
const DOC_ID = 'caldara';

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
  { mode: 'text', label: 'Text', color: '#9C27B0' },
];

export function DrawingScreen({ onBack }: Props) {
  const source = useAsset(require('../assets/caldara.pdf'));
  const pdfViewRef = useRef<NativeZoomablePdfScrollViewRef>(null);
  const pageIndicatorRef = useRef<PageIndicatorRef>(null);

  const [drawingMode, setDrawingMode] = useState<DrawingMode>('view');
  const [canUndo, setCanUndo] = useState(false);
  const [canRedo, setCanRedo] = useState(false);
  const [annotations, setAnnotations] = useState<AnnotationPage[] | undefined>(undefined);
  const [loading, setLoading] = useState(true);

  // Load annotations from backend on mount
  useEffect(() => {
    const url = `${API_BASE}/annotations?docId=${DOC_ID}`;
    console.log('[DrawingScreen] Fetching annotations from:', url);
    (async () => {
      try {
        const controller = new AbortController();
        const timeout = setTimeout(() => {
          console.log('[DrawingScreen] Fetch timed out after 3s');
          controller.abort();
        }, 3000);
        console.log('[DrawingScreen] Starting fetch...');
        const res = await fetch(url, { signal: controller.signal });
        clearTimeout(timeout);
        console.log('[DrawingScreen] Fetch response status:', res.status);
        const data = await res.json();
        console.log('[DrawingScreen] Response data:', JSON.stringify(data));
        if (data.annotations) {
          console.log('[DrawingScreen] Loaded', data.annotations.length, 'pages from server');
          for (let i = 0; i < data.annotations.length; i++) {
            const page = data.annotations[i];
            for (let s = 0; s < (page.strokes || []).length; s++) {
              const stroke = page.strokes[s];
              console.log(`[COORDS][LOAD] page=${i} stroke=${s} color=${stroke.color} width=${stroke.width} opacity=${stroke.opacity} points=${stroke.path.length} first=${JSON.stringify(stroke.path[0])} last=${JSON.stringify(stroke.path[stroke.path.length - 1])}`);
            }
            for (let t = 0; t < (page.text || []).length; t++) {
              const txt = page.text[t];
              console.log(`[COORDS][LOAD] page=${i} text=${t} point=${JSON.stringify(txt.point)} fontSize=${txt.fontSize} str="${txt.str}"`);
            }
          }
          setAnnotations(data.annotations);
        } else {
          console.log('[DrawingScreen] No saved annotations on server');
          setAnnotations([]);
        }
      } catch (e: any) {
        console.warn('[DrawingScreen] Fetch error:', e.message || e);
        console.warn('[DrawingScreen] Error name:', e.name);
        setAnnotations([]);
      } finally {
        console.log('[DrawingScreen] Loading complete');
        setLoading(false);
      }
    })();
  }, []);

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

  const handleZoomChange = useCallback((scale: number) => {}, []);

  const handleClearAll = useCallback(() => {
    pdfViewRef.current?.clearStrokes(-1);
  }, []);

  const handleSave = useCallback(async () => {
    console.log('[DrawingScreen] handleSave called');
    console.log('[DrawingScreen] current annotations state:', annotations?.length, 'pages');
    const result = await pdfViewRef.current?.getAnnotations();
    console.log('[DrawingScreen] getAnnotations result:', result ? 'exists' : 'null');
    console.log('[DrawingScreen] getAnnotations keys:', result ? Object.keys(result) : 'none');
    if (result) {
      const userPages = Object.values(result);
      console.log('[DrawingScreen] userPages count:', userPages.length);
      // Log raw getAnnotations data
      for (let i = 0; i < userPages.length; i++) {
        for (let s = 0; s < (userPages[i]?.strokes || []).length; s++) {
          const stroke = userPages[i]!.strokes[s]!;
          console.log(`[COORDS][SAVE_RAW] page=${i} stroke=${s} color=${stroke.color} width=${stroke.width} opacity=${stroke.opacity} points=${stroke.path.length} first=${JSON.stringify(stroke.path[0])} last=${JSON.stringify(stroke.path[stroke.path.length - 1])}`);
        }
        for (let t = 0; t < (userPages[i]?.text || []).length; t++) {
          const txt = userPages[i]!.text[t]!;
          console.log(`[COORDS][SAVE_RAW] page=${i} text=${t} point=${JSON.stringify(txt.point)} fontSize=${txt.fontSize} str="${txt.str}"`);
        }
      }

      // Log existing annotations state
      for (let i = 0; i < (annotations?.length || 0); i++) {
        const page = annotations![i]!;
        for (let s = 0; s < (page.strokes || []).length; s++) {
          const stroke = page.strokes[s]!;
          console.log(`[COORDS][SAVE_EXISTING] page=${i} stroke=${s} color=${stroke.color} width=${stroke.width} opacity=${stroke.opacity} points=${stroke.path.length} first=${JSON.stringify(stroke.path[0])} last=${JSON.stringify(stroke.path[stroke.path.length - 1])}`);
        }
        for (let t = 0; t < (page.text || []).length; t++) {
          const txt = page.text[t]!;
          console.log(`[COORDS][SAVE_EXISTING] page=${i} text=${t} point=${JSON.stringify(txt.point)} fontSize=${txt.fontSize} str="${txt.str}"`);
        }
      }

      // Merge: static (loaded from server) + new user drawings
      const maxLen = Math.max(userPages.length, annotations?.length || 0);
      const merged: AnnotationPage[] = [];
      for (let i = 0; i < maxLen; i++) {
        const existing = annotations?.[i];
        const drawn = userPages[i];
        merged.push({
          strokes: [
            ...(existing?.strokes || []),
            ...(drawn?.strokes || []),
          ],
          text: [
            ...(existing?.text || []),
            ...(drawn?.text || []),
          ],
        });
      }

      // Log merged result
      for (let i = 0; i < merged.length; i++) {
        for (let s = 0; s < merged[i]!.strokes.length; s++) {
          const stroke = merged[i]!.strokes[s]!;
          console.log(`[COORDS][SAVE_MERGED] page=${i} stroke=${s} color=${stroke.color} width=${stroke.width} opacity=${stroke.opacity} points=${stroke.path.length} first=${JSON.stringify(stroke.path[0])} last=${JSON.stringify(stroke.path[stroke.path.length - 1])}`);
        }
        for (let t = 0; t < merged[i]!.text.length; t++) {
          const txt = merged[i]!.text[t]!;
          console.log(`[COORDS][SAVE_MERGED] page=${i} text=${t} point=${JSON.stringify(txt.point)} fontSize=${txt.fontSize} str="${txt.str}"`);
        }
      }

      const strokeCount = merged.reduce(
        (sum, page) => sum + page.strokes.length,
        0
      );
      const textCount = merged.reduce(
        (sum, page) => sum + page.text.length,
        0
      );
      console.log('[DrawingScreen] Merged:', strokeCount, 'strokes,', textCount, 'texts across', merged.length, 'pages');

      try {
        const res = await fetch(`${API_BASE}/annotations?docId=${DOC_ID}`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ annotations: merged }),
        });
        const data = await res.json();
        console.log('[DrawingScreen] Server response:', data);
        Alert.alert(
          'Saved to server',
          `Strokes: ${strokeCount}, Texts: ${textCount}`
        );
      } catch (e: any) {
        console.warn('[DrawingScreen] Save error:', e.message || e);
        Alert.alert('Error', 'Failed to save annotations to server');
      }
    } else {
      console.log('[DrawingScreen] getAnnotations returned null/undefined');
    }
  }, [annotations]);

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
        <Text style={styles.title}>Drawing Mode</Text>
        <View style={styles.placeholder} />
      </View>

      <View style={styles.toolbar}>
        <ScrollView horizontal>
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
          <TouchableOpacity
            style={[styles.undoButton, !canUndo && styles.buttonDisabled]}
            onPress={() => pdfViewRef.current?.undo()}
            disabled={!canUndo}
          >
            <Text style={styles.undoButtonText}>Undo</Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={[styles.undoButton, !canRedo && styles.buttonDisabled]}
            onPress={() => pdfViewRef.current?.redo()}
            disabled={!canRedo}
          >
            <Text style={styles.undoButtonText}>Redo</Text>
          </TouchableOpacity>
          <TouchableOpacity style={styles.clearButton} onPress={handleClearAll}>
            <Text style={styles.clearButtonText}>Clear</Text>
          </TouchableOpacity>
          <TouchableOpacity style={styles.saveButton} onPress={handleSave}>
            <Text style={styles.saveButtonText}>Save</Text>
          </TouchableOpacity>
        </ScrollView>
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
        textTool={DEFAULT_TEXT_TOOL}
        onDrawingStart={() => console.log('Drawing started')}
        onDrawingEnd={() => console.log('Drawing ended')}
        onUndoStateChange={(state) => {
          setCanUndo(state.canUndo);
          setCanRedo(state.canRedo);
        }}
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
  undoButton: {
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 6,
    backgroundColor: '#607D8B',
  },
  undoButtonText: {
    color: '#fff',
    fontSize: 13,
    fontWeight: '500',
  },
  buttonDisabled: {
    opacity: 0.3,
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
