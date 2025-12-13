@objc(DrawablePdfViewManager)
class DrawablePdfViewManager: RCTViewManager {

    @objc
    override static func requiresMainQueueSetup() -> Bool {
        return true
    }

    override func view() -> UIView! {
        return DrawablePdfView()
    }

    @objc func clearStrokes(_ node: NSNumber) {
        guard let uiManager = bridge.uiManager else { return }
        uiManager.addUIBlock { (_, viewRegistry) in
            guard let viewRegistry,
                  let view = viewRegistry[node] as? DrawablePdfView else { return }
            view.clearStrokes()
        }
    }

    @objc func resetZoom(_ node: NSNumber) {
        guard let uiManager = bridge.uiManager else { return }
        uiManager.addUIBlock { (_, viewRegistry) in
            guard let viewRegistry,
                  let view = viewRegistry[node] as? DrawablePdfView else { return }
            view.resetZoom()
        }
    }
}
