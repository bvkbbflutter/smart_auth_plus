package com.example.smart_auth_plus

import android.content.Context
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.os.Build
import android.util.Base64
import android.util.Log
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.security.NoSuchAlgorithmException
import java.util.Arrays
import java.util.TreeSet

/**
 * Generates the 11-character app signature hash required by the SMS Retriever API.
 *
 * Add this hash at the END of your OTP SMS, e.g.:
 *   "Your OTP is 123456\n\nFA+9qCX9VSu"   ← the last bit is the hash
 *
 * Usage (in debug/dev only – never call in production):
 *   val hash = AppSignatureHelper(context).appSignatures.firstOrNull()
 *
 * Reference: https://developers.google.com/identity/sms-retriever/verify#computing_your_apps_hash_string
 */
class AppSignatureHelper(private val context: Context) {

    companion object {
        private const val TAG = "AppSignatureHelper"
        private const val HASH_TYPE = "SHA-256"
        private const val NUM_HASHED_BYTES = 9
        private const val NUM_BASE64_CHAR = 11
    }

    /**
     * Returns a list of 11-character hashes, one per signing certificate.
     * Most apps have exactly one (the debug or release keystore hash).
     */
    val appSignatures: ArrayList<String>
        get() {
            val appCodes = ArrayList<String>()
            try {
                val packageName = context.packageName
                val packageManager = context.packageManager

                val signatures: Array<Signature> = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    val info = packageManager.getPackageInfo(
                        packageName,
                        PackageManager.GET_SIGNING_CERTIFICATES
                    )
                    info.signingInfo?.apkContentsSigners ?: emptyArray()
                } else {
                    @Suppress("DEPRECATION")
                    val info = packageManager.getPackageInfo(
                        packageName,
                        PackageManager.GET_SIGNATURES
                    )
                    info.signatures ?: emptyArray()
                }

                for (signature in signatures) {
                    val hash = hash(packageName, signature.toCharsString())
                    if (hash != null) {
                        appCodes.add(String.format("%s", hash))
                    }
                }
            } catch (e: PackageManager.NameNotFoundException) {
                Log.e(TAG, "Unable to find package: ${e.message}")
            }
            return appCodes
        }

    private fun hash(packageName: String, signature: String): String? {
        val appInfo = "$packageName $signature"
        return try {
            val messageDigest = MessageDigest.getInstance(HASH_TYPE)
            messageDigest.update(appInfo.toByteArray(StandardCharsets.UTF_8))
            val hashSignature = messageDigest.digest()

            // Truncate to NUM_HASHED_BYTES bytes
            val truncated = Arrays.copyOfRange(hashSignature, 0, NUM_HASHED_BYTES)

            // Base64 encode and take the first 11 characters
            val encoded = Base64.encodeToString(truncated, Base64.NO_PADDING or Base64.NO_WRAP)
            encoded.substring(0, NUM_BASE64_CHAR)
        } catch (e: NoSuchAlgorithmException) {
            Log.e(TAG, "Algorithm not found: ${e.message}")
            null
        } catch (e: Exception) {
            Log.e(TAG, "Hashing failed: ${e.message}")
            null
        }
    }
}
