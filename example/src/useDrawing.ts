import { useCallback, useState } from 'react';
import type {
  DrawingMode,
  DrawingStroke,
  DrawingTool,
} from 'react-native-pdf-light';

export interface UseDrawingReturn {
  drawingMode: DrawingMode;
  drawingTool: DrawingTool;
  showColorPicker: boolean;
  showStrokePicker: boolean;
  pageStrokes: Map<number, DrawingStroke[]>;
  setShowColorPicker: (show: boolean) => void;
  setShowStrokePicker: (show: boolean) => void;
  handleDrawingStart: () => void;
  handleDrawingEnd: () => void;
  handleStrokeEnd: (stroke: DrawingStroke, pageIndex: number) => void;
  handleStrokeRemoved: (strokeId: string, pageIndex: number) => void;
  handleStrokesCleared: (pageIndex: number) => void;
  selectMode: (mode: DrawingMode) => void;
  selectColor: (color: string) => void;
  selectStrokeWidth: (strokeWidth: number) => void;
}

export function useDrawing(): UseDrawingReturn {
  const [drawingMode, setDrawingMode] = useState<DrawingMode>('view');
  const [drawingTool, setDrawingTool] = useState<DrawingTool>({
    color: '#FF0000',
    strokeWidth: 4,
    opacity: 1,
  });
  const [showColorPicker, setShowColorPicker] = useState(false);
  const [showStrokePicker, setShowStrokePicker] = useState(false);
  const [pageStrokes, setPageStrokes] = useState<Map<number, DrawingStroke[]>>(
    new Map()
  );

  const handleDrawingStart = useCallback(() => {
    // Pager already disabled via drawingMode
  }, []);

  const handleDrawingEnd = useCallback(() => {
    // Pager state handled by drawingMode
  }, []);

  const handleStrokeEnd = useCallback(
    (stroke: DrawingStroke, pageIndex: number) => {
      setPageStrokes((prev) => {
        const newMap = new Map(prev);
        const strokes = newMap.get(pageIndex) || [];
        newMap.set(pageIndex, [...strokes, stroke]);
        return newMap;
      });
    },
    []
  );

  const handleStrokeRemoved = useCallback(
    (strokeId: string, pageIndex: number) => {
      setPageStrokes((prev) => {
        const newMap = new Map(prev);
        const strokes = newMap.get(pageIndex) || [];
        newMap.set(
          pageIndex,
          strokes.filter((s) => s.id !== strokeId)
        );
        return newMap;
      });
    },
    []
  );

  const handleStrokesCleared = useCallback((pageIndex: number) => {
    setPageStrokes((prev) => {
      const newMap = new Map(prev);
      newMap.set(pageIndex, []);
      return newMap;
    });
  }, []);

  const selectMode = useCallback((mode: DrawingMode) => {
    setDrawingMode(mode);
    setShowColorPicker(false);
    setShowStrokePicker(false);
    if (mode === 'highlight') {
      setDrawingTool((prev: DrawingTool) => ({
        ...prev,
        opacity: 0.3,
        strokeWidth: 20,
      }));
    } else if (mode === 'draw') {
      setDrawingTool((prev: DrawingTool) => ({
        ...prev,
        opacity: 1,
        strokeWidth: prev.strokeWidth > 10 ? 4 : prev.strokeWidth,
      }));
    }
  }, []);

  const selectColor = useCallback((color: string) => {
    setDrawingTool((prev: DrawingTool) => ({ ...prev, color }));
    setShowColorPicker(false);
  }, []);

  const selectStrokeWidth = useCallback((strokeWidth: number) => {
    setDrawingTool((prev: DrawingTool) => ({ ...prev, strokeWidth }));
    setShowStrokePicker(false);
  }, []);

  return {
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
  };
}
