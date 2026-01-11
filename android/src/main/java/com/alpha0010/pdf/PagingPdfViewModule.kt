package com.alpha0010.pdf

import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.bridge.UIManager

class PagingPdfViewModule(reactContext: ReactApplicationContext) : ReactContextBaseJavaModule(reactContext) {

    override fun getName(): String = "RNPagingPdfView"

    @ReactMethod
    fun getAnnotations(viewTag: Int, promise: Promise) {
        val context = reactApplicationContext

        context.runOnUiQueueThread {
            try {
                val view = context.currentActivity?.findViewById<android.view.View>(android.R.id.content)?.let { rootView ->
                    findViewByTag(rootView, viewTag)
                } as? PagingPdfView

                if (view != null) {
                    val annotations = view.getAnnotations()
                    promise.resolve(annotations)
                } else {
                    promise.reject("E_VIEW_NOT_FOUND", "PagingPdfView not found for tag $viewTag")
                }
            } catch (e: Exception) {
                promise.reject("E_UNKNOWN", e.message)
            }
        }
    }

    private fun findViewByTag(view: android.view.View, tag: Int): android.view.View? {
        if (view.id == tag) return view

        if (view is android.view.ViewGroup) {
            for (i in 0 until view.childCount) {
                val result = findViewByTag(view.getChildAt(i), tag)
                if (result != null) return result
            }
        }
        return null
    }
}
