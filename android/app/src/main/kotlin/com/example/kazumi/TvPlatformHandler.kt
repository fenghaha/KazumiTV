package com.example.kazumi

import android.app.Activity
import android.app.AlertDialog
import android.app.Application
import android.app.UiModeManager
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Color
import android.os.Bundle
import android.text.InputFilter
import android.text.InputType
import android.view.KeyEvent
import android.view.View
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.LinearLayout
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Native text editing is isolated from Flutter's D-pad traversal. The EditText
 * owns a real InputConnection while the dialog is open; no global key handler
 * steals arrows or OK from the television IME.
 */
class TvPlatformHandler private constructor(
    private val activity: Activity,
    flutterEngine: FlutterEngine,
) : Application.ActivityLifecycleCallbacks {
    private val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kazumi/tv")
    private var dialog: AlertDialog? = null
    private var pendingResult: MethodChannel.Result? = null
    private var editor: EditText? = null
    private var previousFocus: View? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isTv" -> {
                    val manager = activity.getSystemService(Context.UI_MODE_SERVICE) as UiModeManager
                    result.success(
                        manager.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION ||
                            activity.packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
                    )
                }
                "editText" -> openEditor(call, result)
                else -> result.notImplemented()
            }
        }
        activity.application.registerActivityLifecycleCallbacks(this)
    }

    private fun openEditor(call: MethodCall, result: MethodChannel.Result) {
        if (activity.isFinishing || activity.isDestroyed) {
            result.success(null)
            return
        }
        if (pendingResult != null) {
            result.error("INPUT_BUSY", "A text editor is already open", null)
            return
        }
        previousFocus = activity.currentFocus
        val obscure = call.argument<Boolean>("obscureText") ?: false
        val multiline = call.argument<Boolean>("multiline") ?: false
        val maxLength = call.argument<Int>("maxLength")?.coerceIn(1, MAX_INPUT_LENGTH) ?: 4096
        val density = activity.resources.displayMetrics.density
        val padding = (24 * density).toInt()
        val input = EditText(activity).apply {
            setTextColor(Color.rgb(245, 241, 232))
            setHintTextColor(Color.rgb(170, 185, 203))
            setBackgroundColor(Color.rgb(28, 44, 65))
            textSize = 22f
            setPadding(padding / 2, padding / 2, padding / 2, padding / 2)
            inputType = when {
                obscure -> InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
                multiline -> InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE
                else -> InputType.TYPE_CLASS_TEXT
            }
            setSingleLine(!multiline)
            if (multiline) {
                minLines = 3
                maxLines = 6
            }
            imeOptions = EditorInfo.IME_ACTION_DONE or EditorInfo.IME_FLAG_NO_EXTRACT_UI
            setText(call.argument<String>("text") ?: "")
            setSelection(text.length)
            // Load the entire existing value BEFORE installing the filter. A
            // LengthFilter would otherwise silently truncate old rule JSON.
            filters = arrayOf(InputFilter { _, start, end, dest, dstart, dend ->
                val nextLength = dest.length - (dend - dstart) + (end - start)
                if (nextLength > maxLength && nextLength >= dest.length) {
                    error = "内容过长，最多支持 $maxLength 字符。原内容已保留。"
                    // Reject the whole replacement rather than retaining a
                    // partial paste which could corrupt a JSON document.
                    dest.subSequence(dstart, dend)
                } else {
                    error = if (nextLength > maxLength) {
                        "内容过长，最多支持 $maxLength 字符。请缩短后重试。"
                    } else null
                    null
                }
            })
            if (text.length > maxLength) {
                error = "内容过长，最多支持 $maxLength 字符。请缩短后重试。"
            }
            isFocusableInTouchMode = true
        }
        editor = input
        pendingResult = result
        val content = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(padding, padding / 2, padding, padding / 2)
            addView(input, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ))
        }
        val editorDialog = AlertDialog.Builder(activity)
            .setTitle(call.argument<String>("title") ?: "输入文字")
            .setView(content)
            .setNegativeButton("取消") { _, _ -> finish(null) }
            .setPositiveButton("完成", null)
            .create()
        dialog = editorDialog
        input.setOnEditorActionListener { _, actionId, event ->
            val doneAction = actionId == EditorInfo.IME_ACTION_DONE ||
                actionId == EditorInfo.IME_ACTION_SEARCH ||
                actionId == EditorInfo.IME_ACTION_SEND ||
                actionId == EditorInfo.IME_ACTION_GO
            val enter = !multiline && event?.action == KeyEvent.ACTION_DOWN &&
                event?.keyCode == KeyEvent.KEYCODE_ENTER
            if (doneAction || enter) {
                submitEditor(maxLength)
                true
            } else {
                false
            }
        }
        editorDialog.setOnCancelListener { finish(null) }
        editorDialog.setOnDismissListener { finish(null) }
        editorDialog.setOnShowListener {
            // Override the default listener so invalid input does not dismiss
            // the dialog or replace the caller's controller value.
            editorDialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                submitEditor(maxLength)
            }
            editorDialog.window?.setSoftInputMode(
                WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE or
                    WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_VISIBLE
            )
            input.requestFocus()
            input.post {
                if (pendingResult != null && input.hasFocus()) {
                    val ime = activity.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
                    ime.showSoftInput(input, InputMethodManager.SHOW_IMPLICIT)
                }
            }
        }
        editorDialog.show()
    }

    private fun submitEditor(maxLength: Int) {
        val input = editor ?: return
        if (input.text.length > maxLength) {
            input.error = "内容过长，最多支持 $maxLength 字符。请缩短后重试。"
            input.requestFocus()
            return
        }
        finish(input.text.toString())
    }

    private fun finish(value: String?) {
        val result = pendingResult ?: return
        pendingResult = null
        val ime = activity.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        editor?.windowToken?.let { ime.hideSoftInputFromWindow(it, 0) }
        editor = null
        val closing = dialog
        dialog = null
        closing?.dismiss()
        previousFocus?.requestFocus()
        previousFocus = null
        result.success(value)
    }

    override fun onActivityDestroyed(destroyed: Activity) {
        if (destroyed != activity) return
        finish(null)
        channel.setMethodCallHandler(null)
        activity.application.unregisterActivityLifecycleCallbacks(this)
    }

    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}
    override fun onActivityStarted(activity: Activity) {}
    override fun onActivityResumed(activity: Activity) {}
    override fun onActivityPaused(activity: Activity) {}
    override fun onActivityStopped(activity: Activity) {}
    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}

    companion object {
        // Keep in sync with lib/tv/input/tv_input_limits.dart.
        private const val MAX_INPUT_LENGTH = 131072
        fun register(activity: Activity, flutterEngine: FlutterEngine) {
            TvPlatformHandler(activity, flutterEngine)
        }
    }
}
