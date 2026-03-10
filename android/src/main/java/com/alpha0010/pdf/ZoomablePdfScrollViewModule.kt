package com.alpha0010.pdf

import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod

class ZoomablePdfScrollViewModule(reactContext: ReactApplicationContext) : ReactContextBaseJavaModule(reactContext) {

    override fun getName(): String = "RNZoomablePdfScrollView"

    @ReactMethod
    fun getAnnotations(viewTag: Int, promise: Promise) {
        PdfViewerConstants.getAnnotationsForTag(reactApplicationContext, viewTag, promise)
    }
}
