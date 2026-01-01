package com.alpha0010.pdf

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.pdf.PdfRenderer
import java.util.concurrent.locks.Lock
import kotlin.concurrent.withLock

const val SLICES = 4

enum class ResizeMode(val jsName: String) {
  CONTAIN("contain"),
  FIT_WIDTH("fitWidth")
}

/**
 * Shared PDF page rendering utility.
 */
object PdfPageRenderer {

    /**
     * Renders a PDF page to a Bitmap.
     * Must be called from a background thread.
     *
     * @param renderer The PdfRenderer instance
     * @param pdfMutex Lock for thread-safe PDF access
     * @param pageIndex Zero-based page index
     * @param viewWidth Width to render into
     * @param pageHeight Height to render into
     * @return Rendered bitmap or null on failure
     */
    fun renderPage(
        renderer: PdfRenderer,
        pdfMutex: Lock,
        pageIndex: Int,
        viewWidth: Int,
        pageHeight: Int
    ): Bitmap? {
        if (viewWidth <= 0 || pageHeight <= 0) return null

        return pdfMutex.withLock {
            try {
                val page = renderer.openPage(pageIndex)
                val bitmap = Bitmap.createBitmap(viewWidth, pageHeight, Bitmap.Config.ARGB_8888)
                bitmap.eraseColor(Color.WHITE)

                val matrix = Matrix()
                matrix.setScale(
                    viewWidth.toFloat() / page.width,
                    pageHeight.toFloat() / page.height
                )

                page.render(bitmap, null, matrix, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                page.close()
                bitmap
            } catch (e: Exception) {
                null
            }
        }
    }
}