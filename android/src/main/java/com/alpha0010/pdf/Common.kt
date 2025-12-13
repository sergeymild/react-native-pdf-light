package com.alpha0010.pdf

const val SLICES = 4

enum class ResizeMode(val jsName: String) {
  CONTAIN("contain"),
  FIT_WIDTH("fitWidth")
}