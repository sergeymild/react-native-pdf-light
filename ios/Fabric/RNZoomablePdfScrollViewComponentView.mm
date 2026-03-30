#ifdef RCT_NEW_ARCH_ENABLED

#import "RNZoomablePdfScrollViewComponentView.h"

#import <react/renderer/components/react_native_pdf_light/ComponentDescriptors.h>
#import <react/renderer/components/react_native_pdf_light/EventEmitters.h>
#import <react/renderer/components/react_native_pdf_light/Props.h>
#import <react/renderer/components/react_native_pdf_light/RCTComponentViewHelpers.h>

#import "RCTFabricComponentsPlugins.h"

using namespace facebook::react;

@interface RNZoomablePdfScrollViewComponentView () <RCTRNZoomablePdfScrollViewViewProtocol>
@end

@implementation RNZoomablePdfScrollViewComponentView {
    UIView *_pdfView;
}

+ (void)load {
    [super load];
}

+ (ComponentDescriptorProvider)componentDescriptorProvider {
    return concreteComponentDescriptorProvider<RNZoomablePdfScrollViewComponentDescriptor>();
}

- (void)layoutSubviews {
    [super layoutSubviews];
    NSLog(@"[CV] layoutSubviews self=%@ pdfView=%@ pdfView.superview=%@",
          NSStringFromCGRect(self.frame), NSStringFromCGRect(_pdfView.frame),
          _pdfView.superview);
}

- (void)mountChildComponentView:(UIView<RCTComponentViewProtocol> *)childComponentView index:(NSInteger)index {
    NSLog(@"[CV] mountChildComponentView %@ at %ld", childComponentView, (long)index);
    [super mountChildComponentView:childComponentView index:index];
}

- (void)unmountChildComponentView:(UIView<RCTComponentViewProtocol> *)childComponentView index:(NSInteger)index {
    NSLog(@"[CV] unmountChildComponentView %@ at %ld", childComponentView, (long)index);
    [super unmountChildComponentView:childComponentView index:index];
}

- (void)updateLayoutMetrics:(const facebook::react::LayoutMetrics &)layoutMetrics
           oldLayoutMetrics:(const facebook::react::LayoutMetrics &)oldLayoutMetrics {
    NSLog(@"[CV] updateLayoutMetrics frame={{%f,%f},{%f,%f}}",
          layoutMetrics.frame.origin.x, layoutMetrics.frame.origin.y,
          layoutMetrics.frame.size.width, layoutMetrics.frame.size.height);
    [super updateLayoutMetrics:layoutMetrics oldLayoutMetrics:oldLayoutMetrics];
    NSLog(@"[CV] after updateLayoutMetrics self=%@ pdfView=%@",
          NSStringFromCGRect(self.frame), NSStringFromCGRect(_pdfView.frame));
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        static const auto defaultProps = std::make_shared<const RNZoomablePdfScrollViewProps>();
        _props = defaultProps;

        Class viewClass = NSClassFromString(@"react_native_pdf_light.ZoomablePdfScrollView");
        if (viewClass) {
            _pdfView = [[viewClass alloc] initWithFrame:frame];
            self.contentView = _pdfView;
            [self _setupEventCallbacks];
        }
    }
    return self;
}

- (void)_setupEventCallbacks {
    __weak auto weakSelf = self;

    [_pdfView setValue:^(NSDictionary *body) {
        auto strongSelf = weakSelf;
        if (strongSelf && strongSelf->_eventEmitter) {
            auto emitter = std::dynamic_pointer_cast<const RNZoomablePdfScrollViewEventEmitter>(strongSelf->_eventEmitter);
            if (emitter) {
                std::string msg = body[@"message"] ? [body[@"message"] UTF8String] : "";
                emitter->onPdfError({.message = msg});
            }
        }
    } forKey:@"onPdfError"];

    [_pdfView setValue:^(NSDictionary *body) {
        auto strongSelf = weakSelf;
        if (strongSelf && strongSelf->_eventEmitter) {
            auto emitter = std::dynamic_pointer_cast<const RNZoomablePdfScrollViewEventEmitter>(strongSelf->_eventEmitter);
            if (emitter) {
                emitter->onPdfLoadComplete({
                    .width = [body[@"width"] doubleValue],
                    .height = [body[@"height"] doubleValue],
                    .pageCount = [body[@"pageCount"] intValue],
                });
            }
        }
    } forKey:@"onPdfLoadComplete"];

    [_pdfView setValue:^(NSDictionary *body) {
        auto strongSelf = weakSelf;
        if (strongSelf && strongSelf->_eventEmitter) {
            auto emitter = std::dynamic_pointer_cast<const RNZoomablePdfScrollViewEventEmitter>(strongSelf->_eventEmitter);
            if (emitter) {
                emitter->onPageChange({.page = [body[@"page"] intValue]});
            }
        }
    } forKey:@"onPageChange"];

    [_pdfView setValue:^(NSDictionary *body) {
        auto strongSelf = weakSelf;
        if (strongSelf && strongSelf->_eventEmitter) {
            auto emitter = std::dynamic_pointer_cast<const RNZoomablePdfScrollViewEventEmitter>(strongSelf->_eventEmitter);
            if (emitter) {
                emitter->onZoomChange({.scale = [body[@"scale"] doubleValue]});
            }
        }
    } forKey:@"onZoomChange"];

    [_pdfView setValue:^(NSDictionary *body) {
        auto strongSelf = weakSelf;
        if (strongSelf && strongSelf->_eventEmitter) {
            auto emitter = std::dynamic_pointer_cast<const RNZoomablePdfScrollViewEventEmitter>(strongSelf->_eventEmitter);
            if (emitter) {
                std::string pos = body[@"position"] ? [body[@"position"] UTF8String] : "";
                emitter->onTap({.position = pos});
            }
        }
    } forKey:@"onTap"];

    [_pdfView setValue:^(NSDictionary *body) {
        auto strongSelf = weakSelf;
        if (strongSelf && strongSelf->_eventEmitter) {
            auto emitter = std::dynamic_pointer_cast<const RNZoomablePdfScrollViewEventEmitter>(strongSelf->_eventEmitter);
            if (emitter) {
                emitter->onMiddleClick({});
            }
        }
    } forKey:@"onMiddleClick"];

    [_pdfView setValue:^(NSDictionary *body) {
        auto strongSelf = weakSelf;
        if (strongSelf && strongSelf->_eventEmitter) {
            auto emitter = std::dynamic_pointer_cast<const RNZoomablePdfScrollViewEventEmitter>(strongSelf->_eventEmitter);
            if (emitter) {
                emitter->onDrawingStart({});
            }
        }
    } forKey:@"onDrawingStart"];

    [_pdfView setValue:^(NSDictionary *body) {
        auto strongSelf = weakSelf;
        if (strongSelf && strongSelf->_eventEmitter) {
            auto emitter = std::dynamic_pointer_cast<const RNZoomablePdfScrollViewEventEmitter>(strongSelf->_eventEmitter);
            if (emitter) {
                emitter->onDrawingEnd({});
            }
        }
    } forKey:@"onDrawingEnd"];

    [_pdfView setValue:^(NSDictionary *body) {
        auto strongSelf = weakSelf;
        if (strongSelf && strongSelf->_eventEmitter) {
            auto emitter = std::dynamic_pointer_cast<const RNZoomablePdfScrollViewEventEmitter>(strongSelf->_eventEmitter);
            if (emitter) {
                emitter->onUndoStateChange({
                    .canUndo = [body[@"canUndo"] boolValue],
                    .canRedo = [body[@"canRedo"] boolValue],
                });
            }
        }
    } forKey:@"onUndoStateChange"];
}

- (void)updateProps:(const Props::Shared &)props oldProps:(const Props::Shared &)oldProps {
    const auto &oldViewProps = *std::static_pointer_cast<const RNZoomablePdfScrollViewProps>(_props);
    const auto &newViewProps = *std::static_pointer_cast<const RNZoomablePdfScrollViewProps>(props);

    NSLog(@"[CV] updateProps START self=%@ pdfView=%@",
          NSStringFromCGRect(self.frame), NSStringFromCGRect(_pdfView.frame));

    if (oldViewProps.source != newViewProps.source) {
        [_pdfView setValue:@(newViewProps.source.c_str()) forKey:@"source"];
    }
    if (oldViewProps.annotations != newViewProps.annotations) {
        NSString *val = newViewProps.annotations.empty() ? @"" : @(newViewProps.annotations.c_str());
        [_pdfView setValue:val forKey:@"annotations"];
    }
    if (oldViewProps.minZoom != newViewProps.minZoom) {
        [_pdfView setValue:@(newViewProps.minZoom) forKey:@"minZoom"];
    }
    if (oldViewProps.maxZoom != newViewProps.maxZoom) {
        [_pdfView setValue:@(newViewProps.maxZoom) forKey:@"maxZoom"];
    }
    if (oldViewProps.edgeTapZone != newViewProps.edgeTapZone) {
        [_pdfView setValue:@(newViewProps.edgeTapZone) forKey:@"edgeTapZone"];
    }
    if (oldViewProps.pdfPaddingTop != newViewProps.pdfPaddingTop) {
        [_pdfView setValue:@(newViewProps.pdfPaddingTop) forKey:@"pdfPaddingTop"];
    }
    if (oldViewProps.pdfPaddingBottom != newViewProps.pdfPaddingBottom) {
        [_pdfView setValue:@(newViewProps.pdfPaddingBottom) forKey:@"pdfPaddingBottom"];
    }
    if (oldViewProps.pdfBackgroundColor != newViewProps.pdfBackgroundColor) {
        int c = newViewProps.pdfBackgroundColor;
        if (c != 0) {
            UIColor *color = [UIColor colorWithRed:((c>>16)&0xFF)/255.0
                                             green:((c>>8)&0xFF)/255.0
                                              blue:(c&0xFF)/255.0
                                             alpha:((c>>24)&0xFF)/255.0];
            [_pdfView setValue:color forKey:@"pdfBackgroundColor"];
        }
    }
    if (oldViewProps.drawingMode != newViewProps.drawingMode) {
        [_pdfView setValue:@(newViewProps.drawingMode.c_str()) forKey:@"drawingMode"];
    }
    if (oldViewProps.strokeColor != newViewProps.strokeColor) {
        [_pdfView setValue:@(newViewProps.strokeColor.c_str()) forKey:@"strokeColor"];
    }
    if (oldViewProps.strokeWidth != newViewProps.strokeWidth) {
        [_pdfView setValue:@(newViewProps.strokeWidth) forKey:@"strokeWidth"];
    }
    if (oldViewProps.strokeOpacity != newViewProps.strokeOpacity) {
        [_pdfView setValue:@(newViewProps.strokeOpacity) forKey:@"strokeOpacity"];
    }
    if (oldViewProps.textColor != newViewProps.textColor) {
        [_pdfView setValue:@(newViewProps.textColor.c_str()) forKey:@"textColor"];
    }
    if (oldViewProps.textFontSize != newViewProps.textFontSize) {
        [_pdfView setValue:@(newViewProps.textFontSize) forKey:@"textFontSize"];
    }

    NSLog(@"[CV] before super updateProps pdfView=%@", NSStringFromCGRect(_pdfView.frame));
    [super updateProps:props oldProps:oldProps];
    NSLog(@"[CV] after super updateProps pdfView=%@", NSStringFromCGRect(_pdfView.frame));
}

- (void)handleCommand:(const NSString *)commandName args:(const NSArray *)args {
    RCTRNZoomablePdfScrollViewHandleCommand(self, commandName, args);
}

#pragma mark - RCTRNZoomablePdfScrollViewViewProtocol

- (void)resetZoom {
    SEL sel = NSSelectorFromString(@"resetZoom");
    if ([_pdfView respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [_pdfView performSelector:sel];
#pragma clang diagnostic pop
    }
}

- (void)scrollToPage:(NSInteger)page animated:(BOOL)animated {
    SEL sel = NSSelectorFromString(@"scrollToPage:animated:");
    if ([_pdfView respondsToSelector:sel]) {
        NSMethodSignature *sig = [_pdfView methodSignatureForSelector:sel];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setSelector:sel];
        [inv setTarget:_pdfView];
        [inv setArgument:&page atIndex:2];
        [inv setArgument:&animated atIndex:3];
        [inv invoke];
    }
}

- (void)clearStrokes:(NSInteger)page {
    SEL sel = NSSelectorFromString(@"clearStrokesWithPage:");
    if ([_pdfView respondsToSelector:sel]) {
        NSMethodSignature *sig = [_pdfView methodSignatureForSelector:sel];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setSelector:sel];
        [inv setTarget:_pdfView];
        [inv setArgument:&page atIndex:2];
        [inv invoke];
    }
}

- (void)undo {
    SEL sel = NSSelectorFromString(@"undo");
    if ([_pdfView respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [_pdfView performSelector:sel];
#pragma clang diagnostic pop
    }
}

- (void)redo {
    SEL sel = NSSelectorFromString(@"redo");
    if ([_pdfView respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [_pdfView performSelector:sel];
#pragma clang diagnostic pop
    }
}

- (void)loadAnnotations:(NSString *)annotations {
    SEL sel = NSSelectorFromString(@"loadAnnotations:");
    if ([_pdfView respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [_pdfView performSelector:sel withObject:annotations];
#pragma clang diagnostic pop
    }
}

@end

Class<RCTComponentViewProtocol> RNZoomablePdfScrollViewCls(void) {
    return RNZoomablePdfScrollViewComponentView.class;
}

#endif
