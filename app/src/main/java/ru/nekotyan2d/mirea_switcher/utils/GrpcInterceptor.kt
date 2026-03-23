package ru.nekotyan2d.mirea_switcher.utils

import android.util.Log
import android.webkit.JavascriptInterface

class GrpcInterceptor(
    private val onUserName: (String) -> Unit
) {

    @JavascriptInterface
    fun onGrpcResponse(url: String, base64Body: String) {
        try {
            val name = GrpcWebParser.parseFullNameFromBase64(base64Body)
            if (name != null) onUserName(name)
        } catch (e: Exception) {
            Log.e("gRPC", "Parse error: ${e::class.java.name}: ${e.message}")
        }
    }

    companion object {
        fun buildInterceptScript(): String = """
            (function() {
                if (window.__grpcIntercepted) return;
                window.__grpcIntercepted = true;

                function uint8ToBase64(bytes) {
                    let binary = '';
                    const chunkSize = 8192;
                    for (let i = 0; i < bytes.length; i += chunkSize) {
                        const chunk = bytes.subarray(i, i + chunkSize);
                        for (let j = 0; j < chunk.length; j++) {
                            binary += String.fromCharCode(chunk[j]);
                        }
                    }
                    return btoa(binary);
                }

                const originalFetch = window.fetch;
                window.fetch = async function(...args) {
                    const response = await originalFetch.apply(this, args);
                    const url = (typeof args[0] === 'string' ? args[0] : args[0]?.url) || '';

                    if (url.toLowerCase().includes('getme')) {
                        try {
                            const clone = response.clone();
                            const buffer = await clone.arrayBuffer();
                            const bytes = new Uint8Array(buffer);
                            AndroidBridge.onGrpcResponse(url, uint8ToBase64(bytes));
                        } catch(e) {
                            console.error('Intercept error:', e.message);
                        }
                    }
                    return response;
                };
            })();
        """.trimIndent()
    }
}