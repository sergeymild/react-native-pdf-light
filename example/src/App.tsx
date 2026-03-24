import React, { useState, useCallback } from 'react';
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

  switch (currentScreen) {
    case 'paging':
      return <PagingPdfScreen onBack={handleBack} />;
    case 'zoomable':
      return <ZoomablePdfScreen onBack={handleBack} />;
    case 'drawing':
      return <DrawingScreen onBack={handleBack} />;
    case 'preview':
      return <AnnotationsPreviewScreen onBack={handleBack} />;
    default:
      return <HomeScreen onNavigate={handleNavigate} />;
  }
}
