package com.example.smart_auth_plus

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.util.Log
import com.google.android.gms.auth.api.credentials.Credential
import com.google.android.gms.auth.api.credentials.Credentials
import com.google.android.gms.auth.api.credentials.HintRequest
import com.google.android.gms.auth.api.phone.SmsRetriever
import com.google.android.gms.common.api.CommonStatusCodes
import com.google.android.gms.common.api.Status
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry

private const val TAG = "SmartAuthPlus"
private const val REQUEST_PHONE_HINT = 11012
private const val REQUEST_SMS_CONSENT = 11013

class SmartAuthPlusPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware,
    PluginRegistry.ActivityResultListener {

    // ─── Channel references ───────────────────────────────────────────────────

    private lateinit var methodChannel: MethodChannel
    private lateinit var smsEventChannel: EventChannel
    private lateinit var phoneHintEventChannel: EventChannel

    private lateinit var context: Context
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null

    // ─── Event sinks (one per channel) ───────────────────────────────────────

    private var smsSink: EventChannel.EventSink? = null
    private var phoneHintSink: EventChannel.EventSink? = null

    // ─── BroadcastReceiver for SMS ────────────────────────────────────────────

    /** Handles events from both SMS Retriever and SMS User Consent APIs. */
    private val smsBroadcastReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {

                // ── SMS Retriever (automatic, hash-based) ──────────────────
                SmsRetriever.SMS_RETRIEVED_ACTION -> {
                    val extras = intent.extras ?: return
                    val status = extras.get(SmsRetriever.EXTRA_STATUS) as? Status ?: return

                    when (status.statusCode) {
                        CommonStatusCodes.SUCCESS -> {
                            val message =
                                extras.getString(SmsRetriever.EXTRA_SMS_MESSAGE)
                            if (message != null) {
                                smsSink?.success(
                                    mapOf("type" to "received", "message" to message)
                                )
                            } else {
                                smsSink?.success(
                                    mapOf("type" to "error", "code" to "NULL_MESSAGE",
                                        "message" to "SMS message was null")
                                )
                            }
                        }
                        CommonStatusCodes.TIMEOUT -> {
                            smsSink?.success(
                                mapOf("type" to "canceled", "reason" to "timeout")
                            )
                        }
                        else -> {
                            smsSink?.success(
                                mapOf("type" to "error", "code" to "RETRIEVER_FAILED",
                                    "message" to "Status: ${status.statusCode}")
                            )
                        }
                    }
                    safeUnregister(this)
                    smsSink = null
                }

                // ── SMS User Consent (consent dialog, then intent) ─────────
                SmsRetriever.SMS_RETRIEVED_ACTION + "_CONSENT" -> {
                    // Not used – consent result comes via onActivityResult.
                }
            }
        }
    }

    // ─── FlutterPlugin ────────────────────────────────────────────────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext

        methodChannel = MethodChannel(binding.binaryMessenger, "smart_auth_plus")
        methodChannel.setMethodCallHandler(this)

        smsEventChannel = EventChannel(binding.binaryMessenger, "smart_auth_plus/sms_events")
        smsEventChannel.setStreamHandler(SmsStreamHandler())

        phoneHintEventChannel =
            EventChannel(binding.binaryMessenger, "smart_auth_plus/phone_hint_events")
        phoneHintEventChannel.setStreamHandler(PhoneHintStreamHandler())
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        smsEventChannel.setStreamHandler(null)
        phoneHintEventChannel.setStreamHandler(null)
    }

    // ─── ActivityAware ────────────────────────────────────────────────────────

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeActivityResultListener(this)
        activity = null
        activityBinding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    // ─── MethodCallHandler ────────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "startSmsUserConsent" -> {
                val sender = call.argument<String?>("senderPhoneNumber")
                startSmsUserConsent(sender, result)
            }
            "startSmsRetriever" -> startSmsRetriever(result)
            "cancelSmsListener" -> cancelSmsListener(result)
            "requestPhoneNumberHint" -> {
                val title = call.argument<String>("title") ?: "Select phone number"
                val subtitle = call.argument<String>("subtitle") ?: ""
                requestPhoneNumberHint(title, subtitle, result)
            }
            "getAppSignature" -> getAppSignature(result)
            else -> result.notImplemented()
        }
    }

    // ─── SMS User Consent ─────────────────────────────────────────────────────

    private fun startSmsUserConsent(senderPhoneNumber: String?, result: Result) {
        val act = activity ?: run {
            result.error("NO_ACTIVITY", "Activity is not attached", null)
            return
        }

        val client = SmsRetriever.getClient(act)
        val task = if (senderPhoneNumber != null)
            client.startSmsUserConsent(senderPhoneNumber)
        else
            client.startSmsUserConsent(null)

        task.addOnSuccessListener {
            Log.d(TAG, "startSmsUserConsent: listener registered")

            // Register broadcast receiver for the consent intent
            val intentFilter = IntentFilter(SmsRetriever.SMS_RETRIEVED_ACTION)
            val receiver = ConsentBroadcastReceiver(act)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.registerReceiver(receiver, intentFilter, Context.RECEIVER_EXPORTED)
            } else {
                context.registerReceiver(receiver, intentFilter)
            }
            result.success(null)
        }
        task.addOnFailureListener { e ->
            Log.e(TAG, "startSmsUserConsent failed: $e")
            result.error("SMS_CONSENT_FAILED", e.message, null)
        }
    }

    /**
     * Inner receiver that captures the SMS_RETRIEVED_ACTION broadcast during
     * the User Consent flow and starts the system consent activity.
     */
    private inner class ConsentBroadcastReceiver(private val act: Activity) :
        BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            if (intent.action == SmsRetriever.SMS_RETRIEVED_ACTION) {
                val extras = intent.extras ?: return
                val status = extras.get(SmsRetriever.EXTRA_STATUS) as? Status ?: return

                if (status.statusCode == CommonStatusCodes.SUCCESS) {
                    val consentIntent =
                        extras.getParcelable<Intent>(SmsRetriever.EXTRA_CONSENT_INTENT)
                    if (consentIntent != null) {
                        try {
                            act.startActivityForResult(consentIntent, REQUEST_SMS_CONSENT)
                        } catch (e: Exception) {
                            smsSink?.success(
                                mapOf("type" to "error", "code" to "CONSENT_INTENT_FAILED",
                                    "message" to (e.message ?: "Failed to start consent"))
                            )
                        }
                    } else {
                        smsSink?.success(
                            mapOf("type" to "error", "code" to "NO_CONSENT_INTENT",
                                "message" to "Consent intent was null")
                        )
                    }
                } else {
                    smsSink?.success(
                        mapOf("type" to "canceled", "reason" to "timeout_or_error")
                    )
                }
                safeUnregister(this)
            }
        }
    }

    // ─── SMS Retriever ────────────────────────────────────────────────────────

    private fun startSmsRetriever(result: Result) {
        val ctx = context
        val client = SmsRetriever.getClient(ctx)
        val task = client.startSmsRetriever()

        task.addOnSuccessListener {
            Log.d(TAG, "startSmsRetriever: listener registered")

            val intentFilter = IntentFilter(SmsRetriever.SMS_RETRIEVED_ACTION)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                ctx.registerReceiver(smsBroadcastReceiver, intentFilter, Context.RECEIVER_EXPORTED)
            } else {
                ctx.registerReceiver(smsBroadcastReceiver, intentFilter)
            }
            result.success(null)
        }
        task.addOnFailureListener { e ->
            Log.e(TAG, "startSmsRetriever failed: $e")
            result.error("SMS_RETRIEVER_FAILED", e.message, null)
        }
    }

    private fun cancelSmsListener(result: Result) {
        safeUnregister(smsBroadcastReceiver)
        smsSink?.success(mapOf("type" to "canceled", "reason" to "manually_canceled"))
        smsSink = null
        result.success(null)
    }

    // ─── Phone Number Hint ────────────────────────────────────────────────────

    private fun requestPhoneNumberHint(title: String, subtitle: String, result: Result) {
        val act = activity ?: run {
            result.error("NO_ACTIVITY", "Activity is not attached", null)
            return
        }

        val hintRequest = HintRequest.Builder()
            .setPhoneNumberIdentifierSupported(true)
            .build()

        val credentialsClient = Credentials.getClient(act)
        val intent = credentialsClient.getHintPickerIntent(hintRequest)

        try {
            act.startIntentSenderForResult(
                intent.intentSender,
                REQUEST_PHONE_HINT,
                null, 0, 0, 0
            )
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "requestPhoneNumberHint failed: $e")
            result.error("PHONE_HINT_FAILED", e.message, null)
        }
    }

    // ─── Activity Result ──────────────────────────────────────────────────────

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        when (requestCode) {

            REQUEST_SMS_CONSENT -> {
                if (resultCode == Activity.RESULT_OK && data != null) {
                    val message = data.getStringExtra(SmsRetriever.EXTRA_SMS_MESSAGE)
                    if (message != null) {
                        smsSink?.success(mapOf("type" to "received", "message" to message))
                    } else {
                        smsSink?.success(
                            mapOf("type" to "error", "code" to "NULL_MESSAGE",
                                "message" to "Consent returned null message")
                        )
                    }
                } else {
                    smsSink?.success(
                        mapOf("type" to "canceled", "reason" to "user_dismissed")
                    )
                }
                smsSink = null
                return true
            }

            REQUEST_PHONE_HINT -> {
                if (resultCode == Activity.RESULT_OK && data != null) {
                    val credential = data.getParcelableExtra<Credential>(
                        Credential.EXTRA_KEY
                    )
                    val phone = credential?.id
                    if (phone != null) {
                        phoneHintSink?.success(
                            mapOf("type" to "selected", "phoneNumber" to phone)
                        )
                    } else {
                        phoneHintSink?.success(
                            mapOf("type" to "error", "code" to "NULL_PHONE",
                                "message" to "Selected credential had no phone number")
                        )
                    }
                } else {
                    phoneHintSink?.success(
                        mapOf("type" to "canceled", "reason" to "user_dismissed")
                    )
                }
                phoneHintSink = null
                return true
            }
        }
        return false
    }

    // ─── App Signature ────────────────────────────────────────────────────────

    private fun getAppSignature(result: Result) {
        try {
            val helper = AppSignatureHelper(context)
            val signatures = helper.appSignatures
            result.success(signatures.firstOrNull())
        } catch (e: Exception) {
            Log.e(TAG, "getAppSignature error: $e")
            result.error("SIGNATURE_FAILED", e.message, null)
        }
    }

    // ─── Stream Handlers ──────────────────────────────────────────────────────

    inner class SmsStreamHandler : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            smsSink = events
        }
        override fun onCancel(arguments: Any?) {
            smsSink = null
        }
    }

    inner class PhoneHintStreamHandler : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            phoneHintSink = events
        }
        override fun onCancel(arguments: Any?) {
            phoneHintSink = null
        }
    }

    // ─── Utilities ────────────────────────────────────────────────────────────

    private fun safeUnregister(receiver: BroadcastReceiver) {
        try {
            context.unregisterReceiver(receiver)
        } catch (_: IllegalArgumentException) {
            // Already unregistered – safe to ignore.
        }
    }
}