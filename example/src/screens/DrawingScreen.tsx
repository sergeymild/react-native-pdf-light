import React, {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from 'react';
import {
  StyleSheet,
  View,
  Text,
  TouchableOpacity,
  ActivityIndicator,
  Modal,
} from 'react-native';
import {
  SafeAreaView,
  useSafeAreaInsets,
} from 'react-native-safe-area-context';
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
import ColorPicker, {
  HueSlider,
  Panel1,
  Swatches,
} from 'reanimated-color-picker';
import { runOnJS } from 'react-native-reanimated';
import { useAsset } from '../assets.utils';
import { PageIndicator, type PageIndicatorRef } from '../PageIndicator';
import {
  IcClose,
  IcUndo,
  IcRedo,
  IcDraw,
  IcHighlight,
  IcText,
  IcErase,
} from '../icons';

const API_BASE = 'http://192.168.1.124:3001';
const DOC_ID = 'caldara';

const TOOLBAR_COLOR = '#2D2B55';

type Props = {
  onBack: () => void;
};

type ToolButton = {
  mode: DrawingMode;
  Icon: React.FC<{ size?: number; color?: string }>;
};

const TOOLS: ToolButton[] = [
  { mode: 'draw', Icon: IcDraw },
  { mode: 'highlight', Icon: IcHighlight },
  { mode: 'text', Icon: IcText },
  { mode: 'erase', Icon: IcErase },
];

export function DrawingScreen({ onBack }: Props) {
  const insets = useSafeAreaInsets();
  const source = useAsset(require('../assets/caldara.pdf'));
  const pdfViewRef = useRef<NativeZoomablePdfScrollViewRef>(null);
  const pageIndicatorRef = useRef<PageIndicatorRef>(null);

  const [drawingMode, setDrawingMode] = useState<DrawingMode>('view');
  const [canUndo, setCanUndo] = useState(false);
  const [canRedo, setCanRedo] = useState(false);
  const [loading, setLoading] = useState(true);
  const [selectedColor, setSelectedColor] = useState(
    DEFAULT_DRAWING_TOOL.color
  );
  const [colorPickerVisible, setColorPickerVisible] = useState(false);
  const loadedAnnotationsRef = useRef<AnnotationPage[] | null>(null);

  useEffect(() => {
    const url = `${API_BASE}/annotations?docId=${DOC_ID}`;
    (async () => {
      try {
        const controller = new AbortController();
        const timeout = setTimeout(() => controller.abort(), 3000);
        const res = await fetch(url, { signal: controller.signal });
        clearTimeout(timeout);
        const data = await res.json();
        if (data.annotations) {
          loadedAnnotationsRef.current = data.annotations;
        } else {
          loadedAnnotationsRef.current = [];
        }
      } catch {
        loadedAnnotationsRef.current = [];
      } finally {
        setLoading(false);
      }
    })();
  }, []);

  const drawingTool: DrawingTool = useMemo(() => {
    if (drawingMode === 'highlight') {
      return { ...DEFAULT_HIGHLIGHTER_TOOL, color: selectedColor };
    }
    return { ...DEFAULT_DRAWING_TOOL, color: selectedColor };
  }, [drawingMode, selectedColor]);

  const handleLoadComplete = useCallback(
    (event: { width: number; height: number; pageCount: number }) => {
      pageIndicatorRef.current?.setPageCount(event.pageCount);
      if (
        loadedAnnotationsRef.current &&
        loadedAnnotationsRef.current.length > 0
      ) {
        pdfViewRef.current?.loadAnnotations(loadedAnnotationsRef.current);
      }
    },
    []
  );

  const handlePageChange = useCallback((page: number) => {
    pageIndicatorRef.current?.setPage(page);
  }, []);

  const handleToolPress = useCallback((mode: DrawingMode) => {
    setDrawingMode((prev) => (prev === mode ? 'view' : mode));
  }, []);

  const handleSave = useCallback(async () => {
    const result = await pdfViewRef.current?.getAnnotations();
    if (result) {
      const pages = Object.values(result);
      const pageKeys = Object.keys(result).map(Number);
      const maxPage = pageKeys.length > 0 ? Math.max(...pageKeys) : -1;
      const annotationsArray: AnnotationPage[] = [];
      for (let i = 0; i <= maxPage; i++) {
        const page = result[String(i)];
        annotationsArray.push({
          strokes: page?.strokes || [],
          text: page?.text || [],
        });
      }
      try {
        await fetch(`${API_BASE}/annotations?docId=${DOC_ID}`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ annotations: annotationsArray }),
        });
      } catch (e: any) {
        console.warn('[DrawingScreen] Save error:', e.message || e);
      }
    }
  }, []);

  const onColorSelect = useCallback((color: { hex: string }) => {
    'worklet';
    runOnJS(setSelectedColor)(color.hex);
  }, []);

  if (!source || loading) {
    return (
      <SafeAreaView style={styles.container}>
        <ActivityIndicator size="large" color="#fff" style={{ flex: 1 }} />
      </SafeAreaView>
    );
  }

  return (
    <View style={styles.container}>
      <PdfViewer
        viewerType="paging"
        ref={pdfViewRef}
        source={source}
        minZoom={1}
        maxZoom={2}
        backgroundColor="#ffffff"
        edgeTapZone={30}
        drawingMode={drawingMode}
        drawingTool={drawingTool}
        textTool={DEFAULT_TEXT_TOOL}
        onDrawingStart={() => {}}
        onDrawingEnd={() => {}}
        onUndoStateChange={(state) => {
          setCanUndo(state.canUndo);
          setCanRedo(state.canRedo);
        }}
        onLoadComplete={handleLoadComplete}
        onPageChange={handlePageChange}
        onZoomChange={() => {}}
        onError={(e) => console.warn('PDF Error:', e.message)}
        style={styles.pdfView}
      />

      {/* Close button - top left */}
      <SafeAreaView style={styles.topLeftContainer} pointerEvents="box-none">
        <TouchableOpacity style={styles.floatingButton} onPress={onBack}>
          <IcClose size={20} />
        </TouchableOpacity>
      </SafeAreaView>

      {/* Undo/Redo/Save - top right */}
      <SafeAreaView style={styles.topRightContainer} pointerEvents="box-none">
        <TouchableOpacity
          style={[styles.floatingButton, !canUndo && styles.buttonDisabled]}
          onPress={() => pdfViewRef.current?.undo()}
          disabled={!canUndo}
        >
          <IcUndo size={20} color="white" />
        </TouchableOpacity>
        <TouchableOpacity
          style={[styles.floatingButton, !canRedo && styles.buttonDisabled]}
          onPress={() => pdfViewRef.current?.redo()}
          disabled={!canRedo}
        >
          <IcRedo size={20} color="white" />
        </TouchableOpacity>
        <TouchableOpacity style={styles.floatingButton} onPress={handleSave}>
          <Text>Sa</Text>
        </TouchableOpacity>
      </SafeAreaView>

      {/* Bottom toolbar */}
      <SafeAreaView style={styles.bottomContainer} pointerEvents="box-none">
        <View style={styles.toolbar}>
          {TOOLS.map((tool) => {
            const isActive = drawingMode === tool.mode;
            return (
              <TouchableOpacity
                key={tool.mode}
                style={[styles.toolButton, isActive && styles.toolButtonActive]}
                onPress={() => handleToolPress(tool.mode)}
              >
                <tool.Icon
                  size={24}
                  color={isActive ? '#fff' : 'rgba(255,255,255,0.5)'}
                />
              </TouchableOpacity>
            );
          })}

          {/* Color picker circle */}
          <TouchableOpacity
            style={styles.colorPickerButton}
            onPress={() => setColorPickerVisible(true)}
          >
            <View style={styles.colorRing}>
              <View
                style={[
                  styles.colorCircleInner,
                  { backgroundColor: selectedColor },
                ]}
              />
            </View>
          </TouchableOpacity>
        </View>
      </SafeAreaView>

      <PageIndicator
        ref={pageIndicatorRef}
        initialPage={0}
        initialPageCount={0}
        topInset={insets.top}
      />

      {/* Color picker modal */}
      <Modal
        visible={colorPickerVisible}
        transparent
        animationType="slide"
        onRequestClose={() => setColorPickerVisible(false)}
      >
        <TouchableOpacity
          style={styles.modalOverlay}
          activeOpacity={1}
          onPress={() => setColorPickerVisible(false)}
        >
          <TouchableOpacity
            activeOpacity={1}
            onPress={() => {}}
            style={styles.modalContent}
          >
            <View style={styles.modalHandle} />
            <Text style={styles.modalTitle}>Pick a color</Text>
            <ColorPicker
              value={selectedColor}
              onComplete={onColorSelect}
              style={styles.colorPicker}
            >
              <Panel1 style={styles.colorPanel} />
              <HueSlider style={styles.hueSlider} />
              <Swatches
                colors={[
                  '#000000',
                  '#FF0000',
                  '#FF8800',
                  '#FFFF00',
                  '#00FF00',
                  '#0088FF',
                  '#0000FF',
                  '#8800FF',
                  '#FF00FF',
                  '#FFFFFF',
                ]}
                style={styles.swatches}
              />
            </ColorPicker>
            <TouchableOpacity
              style={styles.doneButton}
              onPress={() => setColorPickerVisible(false)}
            >
              <Text style={styles.doneButtonText}>Done</Text>
            </TouchableOpacity>
          </TouchableOpacity>
        </TouchableOpacity>
      </Modal>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#333',
  },
  pdfView: {
    flex: 1,
  },
  topLeftContainer: {
    position: 'absolute',
    top: 0,
    left: 16,
  },
  topRightContainer: {
    position: 'absolute',
    top: 0,
    right: 16,
    alignItems: 'center',
    gap: 10,
  },
  floatingButton: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: TOOLBAR_COLOR,
    alignItems: 'center',
    justifyContent: 'center',
  },
  buttonDisabled: {
    opacity: 0.4,
  },
  bottomContainer: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    alignItems: 'center',
    paddingBottom: 8,
  },
  toolbar: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: TOOLBAR_COLOR,
    borderRadius: 28,
    paddingHorizontal: 12,
    paddingVertical: 8,
    gap: 8,
  },
  toolButton: {
    width: 44,
    height: 44,
    borderRadius: 22,
    alignItems: 'center',
    justifyContent: 'center',
  },
  toolButtonActive: {
    backgroundColor: 'rgba(255,255,255,0.15)',
  },
  colorPickerButton: {
    marginLeft: 4,
    width: 36,
    height: 36,
    alignItems: 'center',
    justifyContent: 'center',
  },
  colorRing: {
    width: 32,
    height: 32,
    borderRadius: 16,
    borderWidth: 3,
    borderColor: '#FF4500',
    alignItems: 'center',
    justifyContent: 'center',
    // Simulate rainbow ring with multiple colors via shadow (simplified)
    shadowColor: '#FF00FF',
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.5,
    shadowRadius: 3,
  },
  colorCircleInner: {
    width: 22,
    height: 22,
    borderRadius: 11,
  },
  modalOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.5)',
    justifyContent: 'flex-end',
  },
  modalContent: {
    backgroundColor: '#fff',
    borderTopLeftRadius: 20,
    borderTopRightRadius: 20,
    paddingHorizontal: 20,
    paddingBottom: 40,
    paddingTop: 12,
  },
  modalHandle: {
    width: 40,
    height: 4,
    borderRadius: 2,
    backgroundColor: '#ccc',
    alignSelf: 'center',
    marginBottom: 16,
  },
  modalTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: '#333',
    marginBottom: 16,
    textAlign: 'center',
  },
  colorPicker: {
    gap: 16,
  },
  colorPanel: {
    height: 200,
    borderRadius: 12,
  },
  hueSlider: {
    height: 32,
    borderRadius: 16,
  },
  swatches: {
    justifyContent: 'center',
    gap: 8,
  },
  doneButton: {
    marginTop: 20,
    backgroundColor: TOOLBAR_COLOR,
    borderRadius: 12,
    paddingVertical: 14,
    alignItems: 'center',
  },
  doneButtonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
});
