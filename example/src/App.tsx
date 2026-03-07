import React, { useState, useCallback } from 'react';
import {
  HomeScreen,
  PagingPdfScreen,
  ZoomablePdfScreen,
  DrawingScreen,
} from './screens';

type Screen = 'home' | 'paging' | 'zoomable' | 'drawing';

export default function App() {
  const [currentScreen, setCurrentScreen] = useState<Screen>('home');

  const handleNavigate = useCallback(
    (screen: 'paging' | 'zoomable' | 'drawing') => {
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
    default:
      return <HomeScreen onNavigate={handleNavigate} />;
  }
}
