package com.alpha0010.pdf

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.pdf.PdfRenderer
import org.json.JSONArray
import java.util.concurrent.locks.Lock
import kotlin.concurrent.withLock

const val SLICES = 4

enum class ResizeMode(val jsName: String) {
  CONTAIN("contain"),
  FIT_WIDTH("fitWidth")
}

// --- Annotation Data Classes ---



/**
 * Parses annotations JSON string to list of AnnotationPage.
 */
fun parseAnnotations(json: String?): List<AnnotationPage> {
    if (json.isNullOrEmpty()) return emptyList()

    return try {
        val jsonArray = JSONArray(json)
        val result = mutableListOf<AnnotationPage>()

        for (i in 0 until jsonArray.length()) {
            val pageObj = jsonArray.getJSONObject(i)

            val strokesArray = pageObj.getJSONArray("strokes")
            val strokes = mutableListOf<Stroke>()
            for (j in 0 until strokesArray.length()) {
                val strokeObj = strokesArray.getJSONObject(j)
                val pathArray = strokeObj.getJSONArray("path")
                val path = mutableListOf<List<Float>>()
                for (k in 0 until pathArray.length()) {
                    val pointArray = pathArray.getJSONArray(k)
                    path.add(listOf(
                        pointArray.getDouble(0).toFloat(),
                        pointArray.getDouble(1).toFloat()
                    ))
                }
                strokes.add(Stroke(
                    color = strokeObj.getString("color"),
                    width = strokeObj.getDouble("width").toFloat(),
                    path = path
                ))
            }

            val textArray = pageObj.getJSONArray("text")
            val texts = mutableListOf<PositionedText>()
            for (j in 0 until textArray.length()) {
                val textObj = textArray.getJSONObject(j)
                val pointArray = textObj.getJSONArray("point")
                texts.add(PositionedText(
                    color = textObj.getString("color"),
                    fontSize = textObj.getDouble("fontSize").toFloat(),
                    point = listOf(
                        pointArray.getDouble(0).toFloat(),
                        pointArray.getDouble(1).toFloat()
                    ),
                    str = textObj.getString("str")
                ))
            }

            result.add(AnnotationPage(strokes, texts))
        }
        result
    } catch (e: Exception) {
        emptyList()
    }
}

/**
 * Parses hex color string to Android Color int.
 */
fun parseColor(hexColor: String): Int {
    return try {
        Color.parseColor(hexColor)
    } catch (e: Exception) {
        Color.BLACK
    }
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
     * @param annotation Optional annotation for this page
     * @return Rendered bitmap or null on failure
     */
    fun renderPage(
        renderer: PdfRenderer,
        pdfMutex: Lock,
        pageIndex: Int,
        viewWidth: Int,
        pageHeight: Int,
        annotation: AnnotationPage? = null
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

                // Draw annotations if present
                if (annotation != null) {
                    val canvas = Canvas(bitmap)

                    // Draw strokes
                    for (stroke in annotation.strokes) {
                        if (stroke.path.size < 2) continue

                        val paint = Paint().apply {
                            color = parseColor(stroke.color)
                            strokeWidth = stroke.width * 2 // Scale for density
                            style = Paint.Style.STROKE
                            strokeCap = Paint.Cap.ROUND
                            strokeJoin = Paint.Join.ROUND
                            isAntiAlias = true
                        }

                        val path = Path()
                        stroke.path.forEachIndexed { index, point ->
                            if (point.size >= 2) {
                                val x = point[0] * viewWidth
                                val y = point[1] * pageHeight
                                if (index == 0) {
                                    path.moveTo(x, y)
                                } else {
                                    path.lineTo(x, y)
                                }
                            }
                        }
                        canvas.drawPath(path, paint)
                    }

                    // Draw text annotations
                    for (text in annotation.text) {
                        if (text.point.size < 2) continue

                        val paint = Paint().apply {
                            color = parseColor(text.color)
                            textSize = text.fontSize * 2 // Scale for density
                            isAntiAlias = true
                        }

                        val x = text.point[0] * viewWidth
                        val y = text.point[1] * pageHeight + paint.textSize // Adjust for baseline
                        canvas.drawText(text.str, x, y, paint)
                    }
                }

                bitmap
            } catch (e: Exception) {
                null
            }
        }
    }
}
