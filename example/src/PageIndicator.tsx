import React, {
  forwardRef,
  useImperativeHandle,
  useState,
  useCallback,
} from 'react';
import { StyleSheet, Text, View } from 'react-native';

export interface PageIndicatorRef {
  setPage: (page: number) => void;
  setPageCount: (count: number) => void;
  getPage: () => number;
  getPageCount: () => number;
}

export interface PageIndicatorProps {
  initialPage?: number;
  initialPageCount?: number;
}

export const PageIndicator = forwardRef<PageIndicatorRef, PageIndicatorProps>(
  ({ initialPage = 0, initialPageCount = 0 }, ref) => {
    const [currentPage, setCurrentPage] = useState(initialPage);
    const [pageCount, setPageCount] = useState(initialPageCount);

    const setPage = useCallback((page: number) => {
      setCurrentPage(page);
    }, []);

    const setPageCountValue = useCallback((count: number) => {
      setPageCount(count);
    }, []);

    const getPage = useCallback(() => currentPage, [currentPage]);
    const getPageCount = useCallback(() => pageCount, [pageCount]);

    useImperativeHandle(
      ref,
      () => ({
        setPage,
        setPageCount: setPageCountValue,
        getPage,
        getPageCount,
      }),
      [setPage, setPageCountValue, getPage, getPageCount]
    );

    if (pageCount === 0) {
      return null;
    }

    return (
      <View style={styles.container}>
        <Text style={styles.text}>
          {currentPage + 1} / {pageCount}
        </Text>
      </View>
    );
  }
);

const styles = StyleSheet.create({
  container: {
    position: 'absolute',
    top: 50,
    alignSelf: 'center',
    backgroundColor: 'rgba(0, 0, 0, 0.6)',
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 16,
  },
  text: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '500',
  },
});