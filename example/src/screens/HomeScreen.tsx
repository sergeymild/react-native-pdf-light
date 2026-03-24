import React from 'react';
import { StyleSheet, View, Text, TouchableOpacity } from 'react-native';

type Screen = 'paging' | 'zoomable' | 'drawing' | 'preview';

type Props = {
  onNavigate: (screen: Screen) => void;
};

export function HomeScreen({ onNavigate }: Props) {
  return (
    <View style={styles.container}>
      <Text style={styles.title}>PDF Viewer Examples</Text>
      <Text style={styles.subtitle}>Choose a display mode</Text>

      <TouchableOpacity
        style={[styles.button, styles.pagingButton]}
        onPress={() => onNavigate('paging')}
      >
        <Text style={styles.buttonTitle}>Paging Mode</Text>
        <Text style={styles.buttonDescription}>
          Horizontal page-by-page navigation with swipe gestures
        </Text>
      </TouchableOpacity>

      <TouchableOpacity
        style={[styles.button, styles.zoomableButton]}
        onPress={() => onNavigate('zoomable')}
      >
        <Text style={styles.buttonTitle}>Zoomable Mode</Text>
        <Text style={styles.buttonDescription}>
          Continuous vertical scroll with pinch-to-zoom support
        </Text>
      </TouchableOpacity>

      <TouchableOpacity
        style={[styles.button, styles.drawingButton]}
        onPress={() => onNavigate('drawing')}
      >
        <Text style={styles.buttonTitle}>Drawing Mode</Text>
        <Text style={styles.buttonDescription}>
          Draw, highlight, and annotate on PDF pages
        </Text>
      </TouchableOpacity>

      <TouchableOpacity
        style={[styles.button, styles.previewButton]}
        onPress={() => onNavigate('preview')}
      >
        <Text style={styles.buttonTitle}>Annotations Preview</Text>
        <Text style={styles.buttonDescription}>
          View saved annotations baked into PDF pages (read-only)
        </Text>
      </TouchableOpacity>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f8f9fa',
    paddingTop: 100,
    paddingHorizontal: 24,
  },
  title: {
    fontSize: 28,
    fontWeight: '700',
    color: '#1a1a1a',
    textAlign: 'center',
    marginBottom: 8,
  },
  subtitle: {
    fontSize: 16,
    color: '#666',
    textAlign: 'center',
    marginBottom: 48,
  },
  button: {
    borderRadius: 16,
    padding: 24,
    marginBottom: 20,
  },
  pagingButton: {
    backgroundColor: '#007AFF',
  },
  zoomableButton: {
    backgroundColor: '#34C759',
  },
  drawingButton: {
    backgroundColor: '#FF9800',
  },
  previewButton: {
    backgroundColor: '#673AB7',
  },
  buttonTitle: {
    fontSize: 20,
    fontWeight: '600',
    color: '#fff',
    marginBottom: 8,
  },
  buttonDescription: {
    fontSize: 14,
    color: 'rgba(255, 255, 255, 0.85)',
    lineHeight: 20,
  },
});