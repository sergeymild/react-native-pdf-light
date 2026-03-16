@objc(ZoomablePdfScrollViewManager)
class ZoomablePdfScrollViewManager: RCTViewManager {

    @objc
    override static func requiresMainQueueSetup() -> Bool {
        return true
    }

    override func view() -> UIView! {
        return ZoomablePdfScrollView()
    }

    @objc func resetZoom(_ node: NSNumber) {
        withPdfView(node) { $0.resetZoom() }
    }

    @objc func scrollToPage(_ node: NSNumber, page: Int, animated: Bool) {
        withPdfView(node) { $0.scrollToPage(page, animated: animated) }
    }

    @objc func undo(_ node: NSNumber) {
        withPdfView(node) { $0.undo() }
    }

    @objc func redo(_ node: NSNumber) {
        withPdfView(node) { $0.redo() }
    }

    @objc func clearStrokes(_ node: NSNumber, page: Int) {
        withPdfView(node) { $0.clearStrokes(page: page) }
    }

    @objc func getAnnotations(_ node: NSNumber,
                               resolver: @escaping RCTPromiseResolveBlock,
                               rejecter: @escaping RCTPromiseRejectBlock) {
        withPdfView(node, rejecter: rejecter) { resolver($0.getAnnotations()) }
    }

    private func withPdfView(_ node: NSNumber, rejecter: RCTPromiseRejectBlock? = nil, action: @escaping (ZoomablePdfScrollView) -> Void) {
        guard let uiManager = bridge.uiManager else {
            rejecter?("ERROR", "UIManager not available", nil)
            return
        }
        uiManager.addUIBlock { (_, viewRegistry) in
            guard let viewRegistry,
                  let view = viewRegistry[node] as? ZoomablePdfScrollView else {
                rejecter?("ERROR", "View not found", nil)
                return
            }
            action(view)
        }
    }
}
