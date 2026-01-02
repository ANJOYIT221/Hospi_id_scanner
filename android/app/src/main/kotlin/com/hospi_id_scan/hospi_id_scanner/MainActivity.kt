package com.hospi_id_scan.hospi_id_scanner

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        const val NFC_CHANNEL = "com.hospi_id_scan.nfc"
        const val PAYMENT_CHANNEL = "com.hospi_id_scanner/payment"
        const val WATCHDOG_CHANNEL = "hospismart/watchdog"
        const val REQ_NFC = 1001
    }

    private var nfcPendingResult: MethodChannel.Result? = null
    private lateinit var paymentHandler: PaymentHandler

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        paymentHandler = PaymentHandler(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NFC_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "readTag" -> {
                        nfcPendingResult = result
                        startNfcActivity("read", null)
                    }
                    "writeTag" -> {
                        val text = call.argument<String>("text") ?: ""
                        nfcPendingResult = result
                        startNfcActivity("write", text)
                    }
                    "eraseTag" -> {
                        nfcPendingResult = result
                        startNfcActivity("erase", null)
                    }
                    "readAndEraseTag" -> {
                        nfcPendingResult = result
                        startNfcActivity("readAndErase", null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PAYMENT_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "initialize" -> {
                        paymentHandler.initialize(result)
                    }
                    "processPayment" -> {
                        val amount = call.argument<Double>("amount") ?: 0.0
                        val currency = call.argument<String>("currency") ?: "EUR"
                        val paymentMethod = call.argument<String>("paymentMethod") ?: "any"
                        paymentHandler.processPayment(amount, currency, paymentMethod, result)
                    }
                    "cancelPayment" -> {
                        paymentHandler.cancelPayment(result)
                    }
                    "printReceipt" -> {
                        val transactionId = call.argument<String>("transactionId") ?: ""
                        val amount = call.argument<Double>("amount") ?: 0.0
                        val currency = call.argument<String>("currency") ?: "EUR"
                        val cardType = call.argument<String>("cardType")
                        val cardNumber = call.argument<String>("cardNumber")
                        val merchantName = call.argument<String>("merchantName") ?: "HospiSmart Hotel"
                        val timestamp = call.argument<String>("timestamp") ?: ""
                        paymentHandler.printReceipt(transactionId, amount, currency, cardType, cardNumber, merchantName, timestamp, result)
                    }
                    "isReady" -> {
                        paymentHandler.isReady(result)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WATCHDOG_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "restartApp" -> {
                        result.success(true)
                        restartApp()
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun restartApp() {
        val intent = packageManager.getLaunchIntentForPackage(packageName)
        intent?.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
        finish()
        Runtime.getRuntime().exit(0)
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
                nfcPendingResult?.success(payload)
            else
                nfcPendingResult?.error("NFC_ERROR", payload, null)
            nfcPendingResult = null
        } else {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }
}