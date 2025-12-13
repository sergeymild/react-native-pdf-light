#import <React/RCTViewManager.h>

@interface RCT_EXTERN_REMAP_MODULE(RNZoomablePdfScrollView, ZoomablePdfScrollViewManager, RCTViewManager)

RCT_EXPORT_VIEW_PROPERTY(source, NSString)
RCT_EXPORT_VIEW_PROPERTY(minZoom, CGFloat)
RCT_EXPORT_VIEW_PROPERTY(maxZoom, CGFloat)
RCT_EXPORT_VIEW_PROPERTY(edgeTapZone, CGFloat)
RCT_EXPORT_VIEW_PROPERTY(pdfPaddingTop, CGFloat)
RCT_EXPORT_VIEW_PROPERTY(pdfPaddingBottom, CGFloat)
RCT_EXPORT_VIEW_PROPERTY(pdfBackgroundColor, UIColor)

RCT_EXPORT_VIEW_PROPERTY(onPdfError, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onPdfLoadComplete, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onPageChange, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onZoomChange, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onTap, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onMiddleClick, RCTDirectEventBlock)

// Commands
RCT_EXTERN_METHOD(resetZoom:(nonnull NSNumber *)node)
RCT_EXTERN_METHOD(scrollToPage:(nonnull NSNumber *)node page:(int)page animated:(BOOL)animated)

@end
