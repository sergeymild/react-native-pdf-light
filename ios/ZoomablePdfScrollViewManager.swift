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
        guard let uiManager = bridge.uiManager else { return }
        uiManager.addUIBlock { (_, viewRegistry) in
            guard let viewRegistry,
                  let view = viewRegistry[node] as? ZoomablePdfScrollView else { return }
            view.resetZoom()
        }
    }

    @objc func scrollToPage(_ node: NSNumber, page: Int, animated: Bool) {
        guard let uiManager = bridge.uiManager else { return }
        uiManager.addUIBlock { (_, viewRegistry) in
            guard let viewRegistry,
                  let view = viewRegistry[node] as? ZoomablePdfScrollView else { return }
            view.scrollToPage(page, animated: animated)
        }
    }
}
