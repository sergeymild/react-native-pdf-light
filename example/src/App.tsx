import React, { useState, useCallback } from 'react';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import {
  HomeScreen,
  PagingPdfScreen,
  ZoomablePdfScreen,
  DrawingScreen,
  AnnotationsPreviewScreen,
} from './screens';

type Screen = 'home' | 'paging' | 'zoomable' | 'drawing' | 'preview';

export default function App() {
  const [currentScreen, setCurrentScreen] = useState<Screen>('home');

  const handleNavigate = useCallback(
    (screen: 'paging' | 'zoomable' | 'drawing' | 'preview') => {
      setCurrentScreen(screen);
    },
    []
  );

  const handleBack = useCallback(() => {
    setCurrentScreen('home');
  }, []);

  let screen;
  switch (currentScreen) {
    case 'paging':
      screen = <PagingPdfScreen onBack={handleBack} />;
      break;
    case 'zoomable':
      screen = <ZoomablePdfScreen onBack={handleBack} />;
      break;
    case 'drawing':
      screen = <DrawingScreen onBack={handleBack} />;
      break;
    case 'preview':
      screen = <AnnotationsPreviewScreen onBack={handleBack} />;
      break;
    default:
      screen = <HomeScreen onNavigate={handleNavigate} />;
  }

  return <SafeAreaProvider>{screen}</SafeAreaProvider>;
}
