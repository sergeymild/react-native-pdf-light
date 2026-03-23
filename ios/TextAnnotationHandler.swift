import UIKit

// MARK: - Protocol

protocol TextAnnotationHandlerDelegate: AnyObject {
    var textHandlerDrawingController: DrawingController { get }
    var textHandlerContentContainer: UIView { get }
    /// View for adding floating drag label
    var textHandlerHostView: UIView { get }
    var textHandlerZoomScale: CGFloat { get }

    func textHandlerContentRectForPage(_ page: Int) -> CGRect
    func textHandlerPageForPoint(_ pointInContent: CGPoint) -> Int
    func textHandlerRedrawOverlay()
}

// MARK: - TextAnnotationHandler

class TextAnnotationHandler: NSObject, UITextViewDelegate {

    weak var delegate: TextAnnotationHandlerDelegate?

    var textColor: String = "#0000FF"
    var textFontSize: CGFloat = 16.0

    // MARK: - Text Input State

    private var textInputView: UITextView?
    private var textInputPage: Int = 0
    private var textInputNormalizedPoint: CGPoint = .zero

    // MARK: - Text Drag State

    private(set) var isDraggingText: Bool = false
    private var draggingTextPage: Int = 0
    private var draggingLabel: UILabel?
    private var draggingTouchOffset: CGPoint = .zero
    private var draggingText: DrawingText?

    // Pending touch: tap vs multi-finger detection
    private var pendingText: DrawingText? // existing text hit
    private var pendingNewTextPoint: CGPoint? // new text tap (no hit)
    private var pendingTextPage: Int = 0
    private var pendingTouchStart: CGPoint = .zero
    private let dragThreshold: CGFloat = 8.0
    private var pendingWasMultiTouch = false

    // Editing existing text
    private var editingTextId: String?
    private var editingTextColor: String?

    var hasActiveTextInput: Bool {
        return textInputView != nil
    }

    var hasPendingText: Bool {
        return pendingText != nil || pendingNewTextPoint != nil
    }

    // MARK: - Touch Handling

    /// Handle touch began in text mode. Returns true if touch was consumed.
    func handleTouchBegan(_ touch: UITouch) -> Bool {
        guard let delegate = delegate else { return false }

        let contentContainer = delegate.textHandlerContentContainer

        // If there's a text input view, check if touch is outside it
        if let textView = textInputView {
            let touchInContent = touch.location(in: contentContainer)
            if !textView.frame.contains(touchInContent) {
                commitTextInput()
                return true // consume this touch (just committed)
            }
            return false // touch inside text view, let it handle
        }

        // Clear any stale pending state from previous gesture
        if hasPendingText { clearPending() }

        let location = touch.location(in: contentContainer)
        let page = delegate.textHandlerPageForPoint(location)
        let pageRect = delegate.textHandlerContentRectForPage(page)
        guard !pageRect.isEmpty else { return false }

        // Normalize to 0-1
        let normalizedX = location.x / pageRect.width
        let normalizedY = (location.y - pageRect.minY) / pageRect.height
        let normalizedPoint = CGPoint(x: normalizedX, y: normalizedY)

        // Check if touching an existing text annotation
        if let (textIndex, textAnnotation) = hitTestTextAnnotation(at: normalizedPoint, page: page) {
            // Don't start drag immediately — wait for movement to distinguish tap vs drag
            pendingText = textAnnotation
            pendingTextPage = page
            pendingTouchStart = touch.location(in: delegate.textHandlerHostView)
            return true
        }

        // No existing text — defer until touchEnded to avoid opening on multi-finger
        pendingNewTextPoint = normalizedPoint
        pendingTextPage = page
        pendingTouchStart = touch.location(in: delegate.textHandlerHostView)
        return true
    }

    func handleTouchMoved(_ touch: UITouch) {
        guard let delegate = delegate else { return }

        // If pending new text and finger moves, mark as moved (not a clean tap)
        if pendingNewTextPoint != nil {
            let location = touch.location(in: delegate.textHandlerHostView)
            let dist = hypot(location.x - pendingTouchStart.x, location.y - pendingTouchStart.y)
            if dist >= dragThreshold {
                pendingWasMultiTouch = true // finger moved = not a tap
                clearPending()
            }
            return
        }

        // If we have a pending text hit, check if finger moved enough to start drag
        if let text = pendingText {
            let location = touch.location(in: delegate.textHandlerHostView)
            let dist = hypot(location.x - pendingTouchStart.x, location.y - pendingTouchStart.y)
            if dist >= dragThreshold {
                startDraggingText(
                    textAnnotation: text,
                    textIndex: 0,
                    page: pendingTextPage,
                    touch: touch
                )
                clearPending()
            }
            return
        }

        guard isDraggingText else { return }
        let location = touch.location(in: delegate.textHandlerHostView)
        guard let label = draggingLabel else { return }
        label.frame.origin = CGPoint(
            x: location.x - draggingTouchOffset.x,
            y: location.y - draggingTouchOffset.y
        )
    }

    func handleTouchEnded(_ touch: UITouch) {
        // If pending existing text and no drag started — this is a tap → edit
        if let text = pendingText {
            editExistingText(text, page: pendingTextPage)
            clearPending()
            return
        }

        // If pending new text — this is a tap → show input
        if let point = pendingNewTextPoint {
            showTextInput(at: point, page: pendingTextPage)
            clearPending()
            return
        }

        guard isDraggingText, let _ = delegate else { return }
        finishDraggingText(touch: touch)
    }

    func handleMultiTouchDetected() {
        // Called by callers when 2+ fingers detected — ensures pending new text won't open
        pendingWasMultiTouch = true
        clearPending()
    }

    func handleTouchCancelled() {
        // If pending existing text (finger didn't move enough to drag), treat cancel as tap → edit
        if let text = pendingText {
            editExistingText(text, page: pendingTextPage)
            clearPending()
            return
        }
        // If pending new text: open input only if it wasn't a multi-touch/move gesture
        if let point = pendingNewTextPoint {
            if pendingWasMultiTouch {
                // multi-touch: don't open text input
            } else {
                showTextInput(at: point, page: pendingTextPage)
            }
            clearPending()
            return
        }
        guard isDraggingText else { return }
        // Restore text at original position on cancel
        if let text = draggingText, let delegate = delegate {
            delegate.textHandlerDrawingController.addText(text, toPage: draggingTextPage)
            delegate.textHandlerRedrawOverlay()
        }
        cancelDraggingText()
    }

    private func clearPending() {
        pendingText = nil
        pendingNewTextPoint = nil
        pendingWasMultiTouch = false
    }

    // MARK: - Edit Existing Text

    private func editExistingText(_ text: DrawingText, page: Int) {
        guard let delegate = delegate else { return }

        // Remove text from model so it doesn't render while editing
        delegate.textHandlerDrawingController.removeText(withId: text.id, onPage: page)
        delegate.textHandlerRedrawOverlay()

        // Show input at the text's position with its content
        let normalizedPoint = CGPoint(x: CGFloat(text.point[0]), y: CGFloat(text.point[1]))
        editingTextId = text.id
        editingTextColor = text.color
        showTextInput(at: normalizedPoint, page: page, existingText: text.str, color: text.color, fontSize: text.fontSize)
    }

    // MARK: - Text Input

    private func showTextInput(at normalizedPoint: CGPoint, page: Int, existingText: String? = nil, color: String? = nil, fontSize: CGFloat? = nil) {
        guard let delegate = delegate else { return }

        textInputPage = page
        textInputNormalizedPoint = normalizedPoint

        let pageRect = delegate.textHandlerContentRectForPage(page)
        let contentContainer = delegate.textHandlerContentContainer

        // Position in content container coordinates (unzoomed)
        let contentX = normalizedPoint.x * pageRect.width
        let contentY = pageRect.minY + normalizedPoint.y * pageRect.height
        let maxWidthInContent = pageRect.width - contentX

        let useFontSize = fontSize ?? textFontSize
        let useColor = color ?? textColor

        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.font = UIFont.systemFont(ofSize: useFontSize)
        textView.textColor = UIColor(hexString: useColor) ?? .blue
        if let existingText = existingText {
            textView.text = existingText
        }
        textView.isScrollEnabled = true
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = false
        textView.textContainer.size = CGSize(width: 100000, height: 100000)
        textView.returnKeyType = .default
        textView.delegate = self

        let textViewWidth = max(60, maxWidthInContent)
        textView.frame = CGRect(x: contentX, y: contentY, width: textViewWidth, height: useFontSize + 8)
        textView.autoresizingMask = []

        contentContainer.addSubview(textView)

        // Resize to fit existing content (for multi-line text editing)
        if existingText != nil {
            let fitSize = textView.sizeThatFits(CGSize(width: textView.frame.width, height: CGFloat.greatestFiniteMagnitude))
            textView.frame.size.height = max(fitSize.height, useFontSize + 8)
        }

        textView.becomeFirstResponder()

        textInputView = textView

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textInputDidChange(_:)),
            name: UITextView.textDidChangeNotification,
            object: textView
        )
    }

    @objc private func textInputDidChange(_ notification: Notification) {
        guard let textView = notification.object as? UITextView,
              textView === textInputView else { return }

        let newSize = textView.sizeThatFits(CGSize(width: textView.frame.width, height: CGFloat.greatestFiniteMagnitude))
        textView.frame.size.height = max(newSize.height, (textView.font?.pointSize ?? textFontSize) + 8)
    }

    func commitTextInput() {
        guard let textView = textInputView, let delegate = delegate else { return }

        NotificationCenter.default.removeObserver(self, name: UITextView.textDidChangeNotification, object: textView)

        let text = textView.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let inputFontSize = textView.font?.pointSize ?? textFontSize

        textView.resignFirstResponder()
        textView.removeFromSuperview()
        textInputView = nil

        let existingId = editingTextId
        let existingColor = editingTextColor ?? textColor
        editingTextId = nil
        editingTextColor = nil

        guard !text.isEmpty else { return }

        let drawingText = DrawingText(
            id: existingId ?? UUID().uuidString,
            color: existingId != nil ? existingColor : textColor,
            fontSize: inputFontSize,
            point: [textInputNormalizedPoint.x, textInputNormalizedPoint.y],
            str: text
        )
        delegate.textHandlerDrawingController.addTextWithUndo(drawingText, toPage: textInputPage)
        delegate.textHandlerRedrawOverlay()
    }

    // MARK: - UITextViewDelegate

    // MARK: - Hit Test

    private func hitTestTextAnnotation(at normalizedPoint: CGPoint, page: Int) -> (Int, DrawingText)? {
        guard let delegate = delegate else { return nil }

        let texts = delegate.textHandlerDrawingController.getTexts(forPage: page)
        let pageRect = delegate.textHandlerContentRectForPage(page)
        guard !pageRect.isEmpty else { return nil }

        for (index, text) in texts.enumerated() {
            guard text.point.count >= 2 else { continue }

            let textX = text.point[0]
            let textY = text.point[1]

            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: text.fontSize)
            ]
            let attrStr = NSAttributedString(string: text.str, attributes: attributes)
            let textSize = attrStr.boundingRect(
                with: CGSize(width: 100000, height: 100000),
                options: [.usesLineFragmentOrigin],
                context: nil
            ).size

            let normalizedWidth = textSize.width / pageRect.width
            let normalizedHeight = textSize.height / pageRect.height

            let padding: CGFloat = 0.02
            let hitRect = CGRect(
                x: textX - padding,
                y: textY - padding,
                width: normalizedWidth + padding * 2,
                height: normalizedHeight + padding * 2
            )

            if hitRect.contains(normalizedPoint) {
                return (index, text)
            }
        }
        return nil
    }

    // MARK: - Text Dragging

    private func startDraggingText(textAnnotation: DrawingText, textIndex: Int, page: Int, touch: UITouch) {
        guard let delegate = delegate else { return }

        isDraggingText = true
        draggingTextPage = page

        // Remove text from controller so overlay doesn't draw it
        draggingText = textAnnotation
        delegate.textHandlerDrawingController.removeText(withId: textAnnotation.id, onPage: page)
        delegate.textHandlerRedrawOverlay()

        let zoomScale = delegate.textHandlerZoomScale
        let pageRect = delegate.textHandlerContentRectForPage(page)
        let hostView = delegate.textHandlerHostView
        let touchInHost = touch.location(in: hostView)

        // Create floating label
        let label = UILabel()
        label.text = textAnnotation.str
        label.font = UIFont.systemFont(ofSize: textAnnotation.fontSize * zoomScale)
        label.textColor = (UIColor(hexString: textAnnotation.color) ?? .blue).withAlphaComponent(0.7)
        label.numberOfLines = 0
        label.lineBreakMode = .byClipping
        label.backgroundColor = .clear
        label.sizeToFit()

        // Convert text position from content to host view coordinates
        let contentContainer = delegate.textHandlerContentContainer
        let contentPt = CGPoint(
            x: textAnnotation.point[0] * pageRect.width,
            y: pageRect.minY + textAnnotation.point[1] * pageRect.height
        )
        let screenPt = contentContainer.convert(contentPt, to: hostView)
        label.frame.origin = screenPt

        // Store offset between touch and label origin in host view coordinates (for label movement)
        draggingTouchOffset = CGPoint(x: touchInHost.x - screenPt.x, y: touchInHost.y - screenPt.y)

        hostView.addSubview(label)
        draggingLabel = label
    }

    private func finishDraggingText(touch: UITouch) {
        guard isDraggingText, let text = draggingText, let delegate = delegate else {
            cancelDraggingText()
            return
        }

        // Use touch location in content container directly — avoids contentOffset dependency
        let contentContainer = delegate.textHandlerContentContainer
        let locationInContent = touch.location(in: contentContainer)

        let pageRect = delegate.textHandlerContentRectForPage(draggingTextPage)

        // Apply the touch offset in content coordinates
        let zoomScale = delegate.textHandlerZoomScale
        let contentOffsetX = draggingTouchOffset.x / zoomScale
        let contentOffsetY = draggingTouchOffset.y / zoomScale

        let contentX = locationInContent.x - contentOffsetX
        let contentY = locationInContent.y - contentOffsetY

        let normalizedX = contentX / pageRect.width
        let normalizedY = (contentY - pageRect.minY) / pageRect.height

        let newPoint: [CGFloat] = [normalizedX, normalizedY]
        // Re-add the text at original position first (it was removed during drag start)
        delegate.textHandlerDrawingController.addText(text, toPage: draggingTextPage)
        // Then record the move as a single undoable action
        delegate.textHandlerDrawingController.moveTextWithUndo(withId: text.id, fromPoint: text.point, toPoint: newPoint, onPage: draggingTextPage)
        cancelDraggingText()
        delegate.textHandlerRedrawOverlay()
    }

    private func cancelDraggingText() {
        draggingLabel?.removeFromSuperview()
        draggingLabel = nil
        isDraggingText = false
        draggingText = nil
    }
}
