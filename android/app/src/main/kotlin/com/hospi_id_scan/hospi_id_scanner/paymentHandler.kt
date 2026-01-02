package com.hospi_id_scan.hospi_id_scanner

import android.content.Context
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import java.text.SimpleDateFormat
import java.util.*

class PaymentHandler(private val context: Context) {

    companion object {
        private const val TAG = "PaymentHandler"
    }

    private var isInitialized = false

    fun initialize(result: MethodChannel.Result) {
        try {
            Log.d(TAG, "🔧 Initialisation du terminal de paiement Sunmi...")

            isInitialized = true

            Log.d(TAG, "✅ Terminal initialisé avec succès")
            result.success(true)

        } catch (e: Exception) {
            Log.e(TAG, "❌ Erreur initialisation: ${e.message}", e)
            isInitialized = false
            result.success(false)
        }
    }

    fun processPayment(
        amount: Double,
        currency: String,
        paymentMethod: String,
        result: MethodChannel.Result
    ) {
        if (!isInitialized) {
            Log.e(TAG, "❌ Terminal non initialisé")
            result.error("NOT_INITIALIZED", "Terminal non initialisé", null)
            return
        }

        try {
            Log.d(TAG, "💳 ========== DÉBUT PAIEMENT ==========")
            Log.d(TAG, "💰 Montant: $amount $currency")
            Log.d(TAG, "📱 Méthode: $paymentMethod")

            val transactionId = generateTransactionId()
            val cardType = "VISA"
            val cardNumber = "************1234"

            val response = hashMapOf(
                "status" to "success",
                "transactionId" to transactionId,
                "amount" to amount,
                "currency" to currency,
                "cardType" to cardType,
                "cardNumber" to cardNumber,
                "paymentMethod" to paymentMethod,
                "timestamp" to SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.getDefault()).format(Date()),
                "receiptPrinted" to false
            )

            Log.d(TAG, "✅ Paiement simulé réussi")
            Log.d(TAG, "📝 Transaction: $transactionId")
            Log.d(TAG, "==========================================")

            result.success(response)

        } catch (e: Exception) {
            Log.e(TAG, "❌ Erreur paiement: ${e.message}", e)
            val errorResponse = hashMapOf(
                "status" to "error",
                "message" to (e.message ?: "Erreur inconnue")
            )
            result.success(errorResponse)
        }
    }

    fun cancelPayment(result: MethodChannel.Result) {
        try {
            Log.d(TAG, "🚫 Annulation du paiement...")

            Log.d(TAG, "✅ Paiement annulé")
            result.success(true)

        } catch (e: Exception) {
            Log.e(TAG, "❌ Erreur annulation: ${e.message}", e)
            result.success(false)
        }
    }

    fun printReceipt(
        transactionId: String,
        amount: Double,
        currency: String,
        cardType: String?,
        cardNumber: String?,
        merchantName: String,
        timestamp: String,
        result: MethodChannel.Result
    ) {
        try {
            Log.d(TAG, "🖨️ Impression du reçu...")
            Log.d(TAG, "📝 Transaction: $transactionId")
            Log.d(TAG, "💰 Montant: $amount $currency")
            Log.d(TAG, "🏪 Marchand: $merchantName")

            Log.d(TAG, "✅ Reçu simulé imprimé")
            result.success(true)

        } catch (e: Exception) {
            Log.e(TAG, "❌ Erreur impression: ${e.message}", e)
            result.success(false)
        }
    }

    fun isReady(result: MethodChannel.Result) {
        result.success(isInitialized)
    }

    private fun generateTransactionId(): String {
        val timestamp = System.currentTimeMillis()
        val random = (timestamp % 10000).toString().padStart(4, '0')
        return "TXN$timestamp$random"
    }
}