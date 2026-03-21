package ru.nekotyan2d.mirea_switcher.utils

import android.webkit.CookieManager

object CookieUtils {
    fun parseCookies(cookieString: String?): Map<String, String> {
        if (cookieString.isNullOrBlank()) return emptyMap()
        return cookieString.split(";")
            .map { it.trim() }
            .mapNotNull {
                val parts = it.split("=", limit = 2)
                if (parts.size == 2) parts[0] to parts[1] else null
            }
            .toMap()
    }

    fun setAuthCookie(token: String) {
        CookieManager.getInstance().apply {
            setCookie(
                "https://pulse.mirea.ru",
                ".AspNetCore.Cookies=$token; Domain=.mirea.ru; Path=/; SameSite=None; Secure"
            )
            flush()
        }
    }

    fun getAuthToken(domain: String): String? {
        val cookies = CookieManager.getInstance().getCookie(domain)
        return parseCookies(cookies)[".AspNetCore.Cookies"]
    }
}