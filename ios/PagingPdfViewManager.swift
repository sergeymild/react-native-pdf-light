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
        guard let uiManager = bridge.uiManager else { return }
        uiManager.addUIBlock { (_, viewRegistry) in
            guard let viewRegistry,
                  let view = viewRegistry[node] as? PagingPdfView else { return }
            view.resetZoom()
        }
    }

    @objc func scrollToPage(_ node: NSNumber, page: Int, animated: Bool) {
        guard let uiManager = bridge.uiManager else { return }
        uiManager.addUIBlock { (_, viewRegistry) in
            guard let viewRegistry,
                  let view = viewRegistry[node] as? PagingPdfView else { return }
            view.scrollToPage(page, animated: animated)
        }
    }
}