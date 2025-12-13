import React from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import type { DrawingMode, DrawingTool } from 'react-native-pdf-light';

const COLORS = ['#000000', '#FF0000', '#00FF00', '#0000FF', '#FFFF00'];
const STROKE_WIDTHS = [2, 4, 6, 8];

export interface DrawingToolbarProps {
  drawingMode: DrawingMode;
  drawingTool: DrawingTool;
  showColorPicker: boolean;
  showStrokePicker: boolean;
  isLandscape?: boolean;
  onModeChange: (mode: DrawingMode) => void;
  onColorChange: (color: string) => void;
  onStrokeWidthChange: (strokeWidth: number) => void;
  onColorPickerToggle: (show: boolean) => void;
  onStrokePickerToggle: (show: boolean) => void;
  onClear: () => void;
}

export function DrawingToolbar({
  drawingMode,
  drawingTool,
  showColorPicker,
  showStrokePicker,
  isLandscape = false,
  onModeChange,
  onColorChange,
  onStrokeWidthChange,
  onColorPickerToggle,
  onStrokePickerToggle,
  onClear,
}: DrawingToolbarProps) {
  return (
    <>
      {/* Main Toolbar */}
      <View style={[styles.toolbar, isLandscape && styles.toolbarLandscape]}>
        <ScrollView
          horizontal
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={styles.toolbarContent}
        >
          {/* Mode buttons */}
          <Pressable
            style={[
              styles.button,
              drawingMode === 'view' && styles.buttonActive,
            ]}
            onPress={() => onModeChange('view')}
          >
            <Text style={styles.buttonText}>View</Text>
          </Pressable>

          <Pressable
            style={[
              styles.button,
              drawingMode === 'draw' && styles.buttonActive,
            ]}
            onPress={() => onModeChange('draw')}
          >
            <Text style={styles.buttonText}>Draw</Text>
          </Pressable>

          <Pressable
            style={[
              styles.button,
              drawingMode === 'highlight' && styles.buttonActive,
            ]}
            onPress={() => onModeChange('highlight')}
          >
            <Text style={styles.buttonText}>Highlight</Text>
          </Pressable>

          <Pressable
            style={[
              styles.button,
              drawingMode === 'erase' && styles.buttonActive,
            ]}
            onPress={() => onModeChange('erase')}
          >
            <Text style={styles.buttonText}>Erase</Text>
          </Pressable>

          {/* Separator */}
          <View style={styles.separator} />

          {/* Color picker button */}
          {(drawingMode === 'draw' || drawingMode === 'highlight') && (
            <Pressable
              style={[
                styles.colorButton,
                { backgroundColor: drawingTool.color },
              ]}
              onPress={() => {
                onColorPickerToggle(!showColorPicker);
                onStrokePickerToggle(false);
              }}
            />
          )}

          {/* Stroke width button */}
          {drawingMode === 'draw' && (
            <Pressable
              style={styles.button}
              onPress={() => {
                onStrokePickerToggle(!showStrokePicker);
                onColorPickerToggle(false);
              }}
            >
              <Text style={styles.buttonText}>{drawingTool.strokeWidth}px</Text>
            </Pressable>
          )}

          {/* Clear button */}
          {drawingMode !== 'view' && (
            <>
              <View style={styles.separator} />
              <Pressable style={styles.button} onPress={onClear}>
                <Text style={styles.buttonText}>Clear</Text>
              </Pressable>
            </>
          )}
        </ScrollView>
      </View>

      {/* Color picker dropdown */}
      {showColorPicker && (
        <View style={styles.pickerContainer}>
          {COLORS.map((color) => (
            <Pressable
              key={color}
              style={[
                styles.colorOption,
                { backgroundColor: color },
                drawingTool.color === color && styles.colorOptionActive,
              ]}
              onPress={() => onColorChange(color)}
            />
          ))}
        </View>
      )}

      {/* Stroke width picker dropdown */}
      {showStrokePicker && (
        <View style={styles.pickerContainer}>
          {STROKE_WIDTHS.map((sw) => (
            <Pressable
              key={sw}
              style={[
                styles.strokeOption,
                drawingTool.strokeWidth === sw && styles.strokeOptionActive,
              ]}
              onPress={() => onStrokeWidthChange(sw)}
            >
              <View
                style={[
                  styles.strokePreview,
                  { height: sw, backgroundColor: drawingTool.color },
                ]}
              />
            </Pressable>
          ))}
        </View>
      )}
    </>
  );
}

const styles = StyleSheet.create({
  toolbar: {
    position: 'absolute',
    bottom: 40,
    left: 12,
    right: 12,
    backgroundColor: 'rgba(0, 0, 0, 0.8)',
    borderRadius: 12,
    paddingVertical: 8,
  },
  toolbarLandscape: {
    left: '20%',
    right: '20%',
  },
  toolbarContent: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 8,
    gap: 8,
  },
  button: {
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 8,
    backgroundColor: 'rgba(255, 255, 255, 0.1)',
  },
  buttonActive: {
    backgroundColor: 'rgba(255, 255, 255, 0.3)',
  },
  buttonText: {
    color: '#fff',
    fontSize: 13,
    fontWeight: '600',
  },
  separator: {
    width: 1,
    height: 24,
    backgroundColor: 'rgba(255, 255, 255, 0.3)',
  },
  colorButton: {
    width: 32,
    height: 32,
    borderRadius: 16,
    borderWidth: 2,
    borderColor: '#fff',
  },
  pickerContainer: {
    position: 'absolute',
    bottom: 100,
    left: 20,
    right: 20,
    flexDirection: 'row',
    backgroundColor: 'rgba(0, 0, 0, 0.9)',
    borderRadius: 12,
    padding: 12,
    justifyContent: 'center',
    gap: 12,
  },
  colorOption: {
    width: 40,
    height: 40,
    borderRadius: 20,
    borderWidth: 2,
    borderColor: 'transparent',
  },
  colorOptionActive: {
    borderColor: '#fff',
  },
  strokeOption: {
    width: 50,
    height: 40,
    borderRadius: 8,
    backgroundColor: 'rgba(255, 255, 255, 0.1)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  strokeOptionActive: {
    backgroundColor: 'rgba(255, 255, 255, 0.3)',
  },
  strokePreview: {
    width: 30,
    borderRadius: 2,
  },
});
