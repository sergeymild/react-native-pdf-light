#import <React/RCTViewManager.h>

@interface RCT_EXTERN_REMAP_MODULE(RNDrawablePdfView, DrawablePdfViewManager, RCTViewManager)

// PDF Props
RCT_EXPORT_VIEW_PROPERTY(source, NSString)
RCT_EXPORT_VIEW_PROPERTY(page, NSNumber)
RCT_EXPORT_VIEW_PROPERTY(resizeMode, NSString)
RCT_EXPORT_VIEW_PROPERTY(annotation, NSString)
RCT_EXPORT_VIEW_PROPERTY(annotationStr, NSString)

// Drawing Props
RCT_EXPORT_VIEW_PROPERTY(drawingMode, NSString)
RCT_EXPORT_VIEW_PROPERTY(strokeColor, NSString)
RCT_EXPORT_VIEW_PROPERTY(strokeWidth, CGFloat)
RCT_EXPORT_VIEW_PROPERTY(strokeOpacity, CGFloat)
RCT_EXPORT_VIEW_PROPERTY(strokes, NSString)

// Zoom Props
RCT_EXPORT_VIEW_PROPERTY(minZoom, CGFloat)
RCT_EXPORT_VIEW_PROPERTY(maxZoom, CGFloat)
RCT_EXPORT_VIEW_PROPERTY(zoomEnabled, BOOL)

// Events
RCT_EXPORT_VIEW_PROPERTY(onPdfError, RCTBubblingEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onPdfLoadComplete, RCTBubblingEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onDrawingStart, RCTBubblingEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onDrawingEnd, RCTBubblingEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onStrokeEnd, RCTBubblingEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onStrokeRemoved, RCTBubblingEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onStrokesCleared, RCTBubblingEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onZoomChange, RCTBubblingEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onZoomPanStart, RCTBubblingEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onZoomPanEnd, RCTBubblingEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onSingleTap, RCTBubblingEventBlock)

// Commands
RCT_EXTERN_METHOD(clearStrokes:(nonnull NSNumber *)node)
RCT_EXTERN_METHOD(resetZoom:(nonnull NSNumber *)node)

@end