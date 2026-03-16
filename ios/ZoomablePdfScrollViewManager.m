#import <React/RCTViewManager.h>

@interface RCT_EXTERN_REMAP_MODULE(RNZoomablePdfScrollView, ZoomablePdfScrollViewManager, RCTViewManager)

RCT_EXPORT_VIEW_PROPERTY(source, NSString)
RCT_EXPORT_VIEW_PROPERTY(annotations, NSString)
RCT_EXPORT_VIEW_PROPERTY(minZoom, CGFloat)
RCT_EXPORT_VIEW_PROPERTY(maxZoom, CGFloat)
RCT_EXPORT_VIEW_PROPERTY(edgeTapZone, CGFloat)
RCT_EXPORT_VIEW_PROPERTY(pdfPaddingTop, CGFloat)
RCT_EXPORT_VIEW_PROPERTY(pdfPaddingBottom, CGFloat)
RCT_EXPORT_VIEW_PROPERTY(pdfBackgroundColor, UIColor)

// Drawing props
RCT_EXPORT_VIEW_PROPERTY(drawingMode, NSString)
RCT_EXPORT_VIEW_PROPERTY(strokeColor, NSString)
RCT_EXPORT_VIEW_PROPERTY(strokeWidth, CGFloat)
RCT_EXPORT_VIEW_PROPERTY(strokeOpacity, CGFloat)
RCT_EXPORT_VIEW_PROPERTY(strokes, NSString)

// Events
RCT_EXPORT_VIEW_PROPERTY(onPdfError, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onPdfLoadComplete, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onPageChange, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onZoomChange, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onTap, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onMiddleClick, RCTDirectEventBlock)

// Drawing events
RCT_EXPORT_VIEW_PROPERTY(onDrawingStart, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onDrawingEnd, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onUndoStateChange, RCTDirectEventBlock)

// Text annotation props
RCT_EXPORT_VIEW_PROPERTY(textColor, NSString)
RCT_EXPORT_VIEW_PROPERTY(textFontSize, CGFloat)

// Commands
RCT_EXTERN_METHOD(undo:(nonnull NSNumber *)node)
RCT_EXTERN_METHOD(redo:(nonnull NSNumber *)node)
RCT_EXTERN_METHOD(resetZoom:(nonnull NSNumber *)node)
RCT_EXTERN_METHOD(scrollToPage:(nonnull NSNumber *)node page:(int)page animated:(BOOL)animated)
RCT_EXTERN_METHOD(clearStrokes:(nonnull NSNumber *)node page:(int)page)
RCT_EXTERN_METHOD(getAnnotations:(nonnull NSNumber *)node
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

@end
