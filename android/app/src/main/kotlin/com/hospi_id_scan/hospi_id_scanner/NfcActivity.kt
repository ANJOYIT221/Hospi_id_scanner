package com.hospi_id_scan.hospi_id_scanner

import android.app.Activity
import android.app.PendingIntent
import android.content.Intent
import android.nfc.*
import android.nfc.tech.Ndef
import android.nfc.tech.NdefFormatable
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.widget.Toast

class NfcActivity : Activity() {

    private var nfcAdapter: NfcAdapter? = null
    private lateinit var pendingIntent: PendingIntent
    private var mode: String? = null
    private var writeText: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_nfc)

        mode = intent.getStringExtra("mode")
        writeText = intent.getStringExtra("text")

        nfcAdapter = NfcAdapter.getDefaultAdapter(this)
        if (nfcAdapter == null) {
            Toast.makeText(this, "NFC non supporté", Toast.LENGTH_LONG).show()
            finishWithError("NFC not supported")
            return
        }

        if (!nfcAdapter!!.isEnabled) {
            Toast.makeText(this, "Veuillez activer le NFC", Toast.LENGTH_LONG).show()
            startActivity(Intent(Settings.ACTION_NFC_SETTINGS))
        }

        pendingIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, javaClass).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                PendingIntent.FLAG_MUTABLE else 0
        )
    }

    override fun onResume() {
        super.onResume()
        nfcAdapter?.enableForegroundDispatch(this, pendingIntent, null, null)
    }

    override fun onPause() {
        super.onPause()
        nfcAdapter?.disableForegroundDispatch(this)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        intent.getParcelableExtra<Tag>(NfcAdapter.EXTRA_TAG)?.let { tag ->
            when (mode) {
                "read" -> performRead(tag)
                "write" -> performWrite(tag, writeText ?: "")
                "erase" -> performErase(tag)
            }
        }
    }

    private fun performRead(tag: Tag) {
        try {
            val ndef = Ndef.get(tag) ?: run {
                finishWithError("NDEF not supported")
                return
            }
            ndef.connect()
            val msg = ndef.cachedNdefMessage
            val text = msg.records.joinToString("\n") { String(it.payload.drop(3).toByteArray()) }
            ndef.close()
            finishWithSuccess(text)
        } catch (e: Exception) {
            finishWithError("Read error: ${e.localizedMessage}")
        }
    }

    private fun performWrite(tag: Tag, text: String) {
        val record = NdefRecord.createTextRecord("en", text)
        val message = NdefMessage(arrayOf(record))
        try {
            val ndef = Ndef.get(tag)
            if (ndef != null) {
                ndef.connect()
                ndef.writeNdefMessage(message)
                ndef.close()
                finishWithSuccess("Write success")
            } else {
                val formatable = NdefFormatable.get(tag)
                formatable?.let {
                    it.connect()
                    it.format(message)
                    it.close()
                    finishWithSuccess("Write success")
                } ?: finishWithError("Format not supported")
            }
        } catch (e: Exception) {
            finishWithError("Write error: ${e.localizedMessage}")
        }
    }

    private fun performErase(tag: Tag) {
        try {
            val ndef = Ndef.get(tag)
            if (ndef != null) {
                ndef.connect()
                val emptyRecord = NdefRecord(NdefRecord.TNF_EMPTY, null, null, null)
                val emptyMessage = NdefMessage(arrayOf(emptyRecord))
                ndef.writeNdefMessage(emptyMessage)
                ndef.close()
                finishWithSuccess("Tag effacé avec succès")
            } else {
                val formatable = NdefFormatable.get(tag)
                formatable?.let {
                    it.connect()
                    it.format(NdefMessage(arrayOf()))
                    it.close()
                    finishWithSuccess("Tag formaté et effacé")
                } ?: finishWithError("Effacement non supporté sur ce tag")
            }
        } catch (e: Exception) {
            finishWithError("Erase error: ${e.localizedMessage}")
        }
    }

    private fun finishWithSuccess(result: String) {
        setResult(Activity.RESULT_OK, Intent().putExtra("nfc_result", result))
        finish()
    }

    private fun finishWithError(error: String) {
        setResult(Activity.RESULT_CANCELED, Intent().putExtra("nfc_result", error))
        finish()
    }
}
