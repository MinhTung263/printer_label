package com.example.printer_label.utils

import android.content.Context
import android.widget.Toast

object UIUtils {
    fun toast(context: Context,strRes: Int,) {
        Toast.makeText(context, strRes, Toast.LENGTH_SHORT).show()
    }

    fun toast(context: Context,str: String) {
        Toast.makeText( context, str, Toast.LENGTH_SHORT).show()
    }
}