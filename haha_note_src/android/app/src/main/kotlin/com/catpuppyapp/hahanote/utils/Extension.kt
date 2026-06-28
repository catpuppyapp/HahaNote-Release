package com.catpuppyapp.hahanote.utils

import android.content.Intent
import android.os.Build

fun <T : CharSequence> T.takeIfNotBlank(): T? = if (isNotBlank()) this else null

fun <T : CharSequence> T.takeIfNotEmpty(): T? = if (isNotEmpty()) this else null


// used to indicate a copy is called by a cut action
fun String.appendCutSuffix() = "$this (CUT)"

fun String.countSub(sub: String) = this.split(sub).size - 1

// used to calculate indent
fun String.pairClosed(openSign: String, closeSign:String) = (this.countSub(openSign).let { open ->
    this.countSub(closeSign).let { close ->
        if(open == 0) {
            true
        }else if(close == 0) {
            false
        }else if(closeSign.contains(openSign)) {
            // e.g. in html, openSign is "<", closeSign is "</", then the closeSign included openSign
            // open 是 close 的2倍，代表关闭了
            open == close || open / close == 2
        }else {
            open == close
        }
    }
})


fun Intent.removeFlagsCompat(flags: Int) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        removeFlags(flags)
    } else {
        setFlags(this.flags andInv flags)
    }
}


fun Intent.withChooser(title: CharSequence? = null, vararg initialIntents: Intent): Intent =
    Intent.createChooser(this, title).apply {
        putExtra(Intent.EXTRA_INITIAL_INTENTS, initialIntents)
    }

fun Intent.withChooser(vararg initialIntents: Intent) = withChooser(null, *initialIntents)


fun Int.hasBits(bits: Int): Boolean = this and bits == bits

infix fun Int.andInv(other: Int): Int = this and other.inv()

