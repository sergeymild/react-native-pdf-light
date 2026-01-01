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
    ///   - completion: Callback with rendered image (called on main thread)
    static func renderPage(
        document: CGPDFDocument,
        pageIndex: Int,
        viewWidth: CGFloat,
        pdfPageWidth: CGFloat,
        pdfPageHeight: CGFloat,
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
            }

            DispatchQueue.main.async {
                completion(rendered)
            }
        }
    }
}