package com.hospi_id_scan.hospi_id_scanner

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        const val CHANNEL = "com.hospi_id_scan.nfc"
        const val REQ_NFC = 1001
    }

    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "readTag" -> {
                        pendingResult = result
                        startNfcActivity("read", null)
                    }
                    "writeTag" -> {
                        val text = call.argument<String>("text") ?: ""
                        pendingResult = result
                        startNfcActivity("write", text)
                    }
                    "eraseTag" -> {
                        pendingResult = result
                        startNfcActivity("erase", null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun startNfcActivity(mode: String, text: String?) {
        val intent = Intent(this, NfcActivity::class.java)
        intent.putExtra("mode", mode)
        text?.let { intent.putExtra("text", it) }
        startActivityForResult(intent, REQ_NFC)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQ_NFC) {
            val payload = data?.getStringExtra("nfc_result") ?: ""
            if (resultCode == Activity.RESULT_OK)
                pendingResult?.success(payload)
            else
                pendingResult?.error("NFC_ERROR", payload, null)
            pendingResult = null
        } else {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }
}
