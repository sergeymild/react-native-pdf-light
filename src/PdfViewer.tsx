import React, { forwardRef } from 'react';
import {
  NativePagingPdfView,
  type NativePagingPdfViewProps_Public,
} from './NativePagingPdfView';
import {
  NativeZoomablePdfScrollView,
  type NativeZoomablePdfScrollViewProps_Public,
  type NativeZoomablePdfScrollViewRef,
} from './NativeZoomablePdfScrollView';

type PdfViewerProps =
  | {
      viewerType: 'zoomable';
      props: NativeZoomablePdfScrollViewProps_Public;
    }
  | {
      viewerType: 'paging';
      props: NativePagingPdfViewProps_Public;
    };

export const PdfViewer = forwardRef<
  NativeZoomablePdfScrollViewRef,
  PdfViewerProps
>((props, ref) => {
  return (
    <>
      {props.viewerType === 'zoomable' ? (
        <NativeZoomablePdfScrollView {...props.props} ref={ref} />
      ) : (
        <NativePagingPdfView {...props.props} ref={ref} />
      )}
    </>
  );
});
