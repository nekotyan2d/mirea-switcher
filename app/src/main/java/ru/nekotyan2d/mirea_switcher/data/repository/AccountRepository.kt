package ru.nekotyan2d.mirea_switcher.data.repository

import android.content.Context
import androidx.core.content.edit
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import ru.nekotyan2d.mirea_switcher.data.model.Account

class AccountRepository(ctx: Context) {
    private val prefs = ctx.getSharedPreferences("accounts", Context.MODE_PRIVATE)
    private val gson = Gson()
    private val type = object : TypeToken<MutableList<Account>>() {}.type

    fun getAll(): MutableList<Account> {
        return gson.fromJson(prefs.getString("accounts", "[]"), type)
    }

    fun save(accounts: List<Account>) {
        prefs.edit { putString("accounts", gson.toJson(accounts)) }
    }

    fun addIfAbsent(token: String): Boolean {
        val accounts = getAll()
        if (accounts.any { it.token == token }) return false
        accounts.add(Account("Account ${accounts.size + 1}", token))
        save(accounts)
        return true
    }
}