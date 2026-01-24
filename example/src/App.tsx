import React, { useState, useCallback } from 'react';
import { HomeScreen, PagingPdfScreen, ZoomablePdfScreen } from './screens';

type Screen = 'home' | 'paging' | 'zoomable';

export default function App() {
  const [currentScreen, setCurrentScreen] = useState<Screen>('home');

  const handleNavigate = useCallback((screen: 'paging' | 'zoomable') => {
    setCurrentScreen(screen);
  }, []);

  const handleBack = useCallback(() => {
    setCurrentScreen('home');
  }, []);

  switch (currentScreen) {
    case 'paging':
      return <PagingPdfScreen onBack={handleBack} />;
    case 'zoomable':
      return <ZoomablePdfScreen onBack={handleBack} />;
    default:
      return <HomeScreen onNavigate={handleNavigate} />;
  }
}