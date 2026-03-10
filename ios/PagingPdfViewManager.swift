@objc(PagingPdfViewManager)
class PagingPdfViewManager: RCTViewManager {

    @objc
    override static func requiresMainQueueSetup() -> Bool {
        return true
    }

    override func view() -> UIView! {
        return PagingPdfView()
    }

    @objc func resetZoom(_ node: NSNumber) {
        withPdfView(node) { $0.resetZoom() }
    }

    @objc func scrollToPage(_ node: NSNumber, page: Int, animated: Bool) {
        withPdfView(node) { $0.scrollToPage(page, animated: animated) }
    }

    @objc func clearStrokes(_ node: NSNumber, page: Int) {
        withPdfView(node) { $0.clearStrokes(page: page) }
    }

    @objc func getAnnotations(_ node: NSNumber,
                               resolver: @escaping RCTPromiseResolveBlock,
                               rejecter: @escaping RCTPromiseRejectBlock) {
        withPdfView(node, rejecter: rejecter) { resolver($0.getAnnotations()) }
    }

    private func withPdfView(_ node: NSNumber, rejecter: RCTPromiseRejectBlock? = nil, action: @escaping (PagingPdfView) -> Void) {
        guard let uiManager = bridge.uiManager else {
            rejecter?("ERROR", "UIManager not available", nil)
            return
        }
        uiManager.addUIBlock { (_, viewRegistry) in
            guard let viewRegistry,
                  let view = viewRegistry[node] as? PagingPdfView else {
                rejecter?("ERROR", "View not found", nil)
                return
            }
            action(view)
        }
    }
}
