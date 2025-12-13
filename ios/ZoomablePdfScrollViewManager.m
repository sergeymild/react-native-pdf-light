#import <React/RCTViewManager.h>

@interface RCT_EXTERN_REMAP_MODULE(RNZoomablePdfScrollView, ZoomablePdfScrollViewManager, RCTViewManager)

RCT_EXPORT_VIEW_PROPERTY(source, NSString)
RCT_EXPORT_VIEW_PROPERTY(minZoom, CGFloat)
RCT_EXPORT_VIEW_PROPERTY(maxZoom, CGFloat)
RCT_EXPORT_VIEW_PROPERTY(edgeTapZone, CGFloat)
RCT_EXPORT_VIEW_PROPERTY(paddingTop, CGFloat)
RCT_EXPORT_VIEW_PROPERTY(paddingBottom, CGFloat)
RCT_EXPORT_VIEW_PROPERTY(pdfBackgroundColor, UIColor)

RCT_EXPORT_VIEW_PROPERTY(onPdfError, RCTBubblingEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onPdfLoadComplete, RCTBubblingEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onPageChange, RCTBubblingEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onZoomChange, RCTBubblingEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onTap, RCTBubblingEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onMiddleClick, RCTBubblingEventBlock)

// Commands
RCT_EXTERN_METHOD(resetZoom:(nonnull NSNumber *)node)
RCT_EXTERN_METHOD(scrollToPage:(nonnull NSNumber *)node page:(int)page animated:(BOOL)animated)

@end
