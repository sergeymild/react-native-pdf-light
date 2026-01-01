import Foundation
import UIKit

enum ResizeMode: String {
    case CONTAIN = "contain"
    case FIT_WIDTH = "fitWidth"
}

// MARK: - PdfPageRenderer

class PdfPageRenderer {

    /// Renders a PDF page to UIImage asynchronously
    /// - Parameters:
    ///   - document: The PDF document
    ///   - pageIndex: Zero-based page index
    ///   - viewWidth: Width of the view to render into
    ///   - pdfPageWidth: Width of the PDF page (from first page dimensions)
    ///   - pdfPageHeight: Height of the PDF page (from first page dimensions)
    ///   - annotation: Optional annotation for this page
    ///   - completion: Callback with rendered image (called on main thread)
    static func renderPage(
        document: CGPDFDocument,
        pageIndex: Int,
        viewWidth: CGFloat,
        pdfPageWidth: CGFloat,
        pdfPageHeight: CGFloat,
        annotation: AnnotationPage? = nil,
        completion: @escaping (UIImage?) -> Void
    ) {
        let pageHeight = viewWidth * (pdfPageHeight / pdfPageWidth)

        // Guard against zero size
        guard viewWidth > 0, pageHeight > 0 else {
            completion(nil)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            guard let pdfPage = document.page(at: pageIndex + 1) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let pageBounds = pdfPage.getBoxRect(.cropBox)
            let pdfWidth: CGFloat
            let pdfHeight: CGFloat

            if pdfPage.rotationAngle % 180 == 90 {
                pdfWidth = pageBounds.height
                pdfHeight = pageBounds.width
            } else {
                pdfWidth = pageBounds.width
                pdfHeight = pageBounds.height
            }

            // Render at 2x for retina
            let scale: CGFloat = 2.0
            let renderSize = CGSize(width: viewWidth * scale, height: pageHeight * scale)

            let renderer = UIGraphicsImageRenderer(size: renderSize)
            let rendered = renderer.image { context in
                let ctx = context.cgContext

                // Fill with white
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: renderSize))

                // Save state before PDF transforms
                ctx.saveGState()

                // Scale and flip for PDF rendering
                ctx.translateBy(x: 0, y: renderSize.height)
                ctx.scaleBy(x: renderSize.width / pdfWidth, y: -renderSize.height / pdfHeight)

                ctx.concatenate(pdfPage.getDrawingTransform(
                    .cropBox,
                    rect: CGRect(x: 0, y: 0, width: pdfWidth, height: pdfHeight),
                    rotate: 0,
                    preserveAspectRatio: false
                ))

                ctx.interpolationQuality = .high
                ctx.setRenderingIntent(.defaultIntent)
                ctx.drawPDFPage(pdfPage)

                // Restore state to draw annotations in normal coordinates
                ctx.restoreGState()

                // Draw annotations if present
                if let annotation = annotation {

                    // Draw strokes
                    for stroke in annotation.strokes {
                        guard stroke.path.count >= 2 else { continue }

                        let color = UIColor(hexString: stroke.color) ?? .black
                        ctx.setStrokeColor(color.cgColor)
                        ctx.setLineWidth(stroke.width * scale)
                        ctx.setLineCap(.round)
                        ctx.setLineJoin(.round)

                        let path = CGMutablePath()
                        for (index, point) in stroke.path.enumerated() {
                            guard point.count >= 2 else { continue }
                            // Convert normalized coordinates (0-1) to render coordinates
                            let x = point[0] * renderSize.width
                            let y = point[1] * renderSize.height
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                        ctx.addPath(path)
                        ctx.strokePath()
                    }

                    // Draw text annotations
                    for textAnnotation in annotation.text {
                        guard textAnnotation.point.count >= 2 else { continue }

                        let color = UIColor(hexString: textAnnotation.color) ?? .black
                        let fontSize = textAnnotation.fontSize * scale
                        let x = textAnnotation.point[0] * renderSize.width
                        let y = textAnnotation.point[1] * renderSize.height

                        let attributes: [NSAttributedString.Key: Any] = [
                            .font: UIFont.systemFont(ofSize: fontSize),
                            .foregroundColor: color
                        ]

                        let attributedString = NSAttributedString(string: textAnnotation.str, attributes: attributes)
                        attributedString.draw(at: CGPoint(x: x, y: y))
                    }
                }
            }

            DispatchQueue.main.async {
                completion(rendered)
            }
        }
    }
}

// MARK: - UIColor Hex Extension

extension UIColor {
    convenience init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") {
            hex.removeFirst()
        }

        guard hex.count == 6 || hex.count == 8 else { return nil }

        var rgbValue: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgbValue)

        if hex.count == 6 {
            self.init(
                red: CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0,
                green: CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0,
                blue: CGFloat(rgbValue & 0x0000FF) / 255.0,
                alpha: 1.0
            )
        } else {
            self.init(
                red: CGFloat((rgbValue & 0xFF000000) >> 24) / 255.0,
                green: CGFloat((rgbValue & 0x00FF0000) >> 16) / 255.0,
                blue: CGFloat((rgbValue & 0x0000FF00) >> 8) / 255.0,
                alpha: CGFloat(rgbValue & 0x000000FF) / 255.0
            )
        }
    }
}