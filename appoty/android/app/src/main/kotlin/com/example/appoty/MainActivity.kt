package com.example.appoty

import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.telecom.TelecomManager
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.example.appoty/sim"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSimCards" -> result.success(getSimCards())
                    "callWithSim" -> {
                        val number = call.argument<String>("number") ?: ""
                        val subscriptionId = call.argument<Int>("subscriptionId") ?: -1
                        callWithSim(number, subscriptionId)
                        result.success(null)
                    }
                    "callWithUssdFallback" -> {
                        val cardCode = call.argument<String>("code") ?: ""
                        val subscriptionId = call.argument<Int>("subscriptionId") ?: -1
                        sendUssdWithFallback(cardCode, subscriptionId, result)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun getSimCards(): List<Map<String, Any>> {
        return try {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP_MR1) return emptyList()
            val sm = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as SubscriptionManager
            val subs = sm.activeSubscriptionInfoList ?: return emptyList()
            subs.map { sub ->
                mapOf(
                    "subscriptionId" to sub.subscriptionId,
                    "displayName"    to (sub.displayName?.toString() ?: "SIM ${sub.simSlotIndex + 1}"),
                    "carrierName"    to (sub.carrierName?.toString() ?: ""),
                    "slotIndex"      to sub.simSlotIndex,
                    "phoneNumber"    to getPhoneNumber(sm, sub.subscriptionId, sub.simSlotIndex)
                )
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    private fun getPhoneNumber(sm: SubscriptionManager, subscriptionId: Int, slotIndex: Int): String {
        return try {
            // Method 1: Android 13+ dedicated API (requires READ_PHONE_NUMBERS)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val n = sm.getPhoneNumber(subscriptionId)
                if (!n.isNullOrBlank()) return n
            }
            // Method 2: Legacy SubscriptionInfo.number
            val sub = sm.getActiveSubscriptionInfo(subscriptionId)
            val legacy = try { sub?.number } catch (e: Exception) { null }
            if (!legacy.isNullOrBlank()) return legacy
            // Method 3: TelephonyManager.getLine1Number per slot
            val tm = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
            val tmSub = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                tm.createForSubscriptionId(subscriptionId)
            } else tm
            val line1 = try { tmSub.line1Number } catch (e: Exception) { null }
            line1?.takeIf { it.isNotBlank() } ?: ""
        } catch (e: Exception) {
            ""
        }
    }

    private fun sendUssdWithFallback(cardCode: String, subscriptionId: Int, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            callWithSim("*100*$cardCode%23", subscriptionId)
            result.success("fallback")
            return
        }
        val telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        val tm = try {
            telephonyManager.createForSubscriptionId(subscriptionId)
        } catch (e: Exception) {
            callWithSim("*100*$cardCode%23", subscriptionId)
            result.success("fallback")
            return
        }
        val handler = Handler(Looper.getMainLooper())
        var done = false
        fun finish(value: String) { if (!done) { done = true; result.success(value) } }

        fun tryMethod2() {
            try {
                tm.sendUssdRequest("*123*2*1*$cardCode#",
                    object : TelephonyManager.UssdResponseCallback() {
                        override fun onReceiveUssdResponse(t: TelephonyManager, req: String, resp: CharSequence) {
                            finish("ok:$resp")
                        }
                        override fun onReceiveUssdResponseFailed(t: TelephonyManager, req: String, failCode: Int) {
                            callWithSim("*100*$cardCode%23", subscriptionId)
                            finish("fallback")
                        }
                    }, handler)
            } catch (e: Exception) {
                callWithSim("*100*$cardCode%23", subscriptionId)
                finish("fallback")
            }
        }

        try {
            tm.sendUssdRequest("*100*$cardCode#",
                object : TelephonyManager.UssdResponseCallback() {
                    override fun onReceiveUssdResponse(t: TelephonyManager, req: String, resp: CharSequence) {
                        finish("ok:$resp")
                    }
                    override fun onReceiveUssdResponseFailed(t: TelephonyManager, req: String, failCode: Int) {
                        tryMethod2()
                    }
                }, handler)
        } catch (e: Exception) {
            callWithSim("*100*$cardCode%23", subscriptionId)
            finish("fallback")
        }
    }

    private fun callWithSim(number: String, subscriptionId: Int) {
        try {
            val telecom = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
            val accounts = telecom.callCapablePhoneAccounts

            val handle = accounts.firstOrNull { h ->
                h.id.contains(subscriptionId.toString())
            } ?: run {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                    val sm = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as SubscriptionManager
                    val slotIndex = sm.getActiveSubscriptionInfo(subscriptionId)?.simSlotIndex ?: -1
                    if (slotIndex in accounts.indices) accounts[slotIndex] else accounts.firstOrNull()
                } else {
                    accounts.firstOrNull()
                }
            }

            val extras = android.os.Bundle()
            if (handle != null) {
                extras.putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, handle)
            }
            telecom.placeCall(Uri.parse("tel:$number"), extras)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}
