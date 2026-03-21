package ru.nekotyan2d.mirea_switcher

import android.os.Bundle
import android.webkit.CookieManager
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.PopupMenu
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import ru.nekotyan2d.mirea_switcher.data.model.Account
import ru.nekotyan2d.mirea_switcher.data.repository.AccountRepository
import ru.nekotyan2d.mirea_switcher.utils.CookieUtils

class MainActivity : AppCompatActivity() {
    private lateinit var repo: AccountRepository

    private var accountList: MutableList<Account> = mutableListOf()

    private lateinit var webView: WebView
    private lateinit var switchAccountBtn: Button

    private var currentToken: String = ""


    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContentView(R.layout.activity_main)
        ViewCompat.setOnApplyWindowInsetsListener(findViewById(R.id.main)) { v, insets ->
            val systemBars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            v.setPadding(systemBars.left, systemBars.top, systemBars.right, systemBars.bottom)
            insets
        }

        repo = AccountRepository(applicationContext)
        accountList = repo.getAll()

        initUi()

        webView.loadUrl("https://pulse.mirea.ru")
    }

    private fun initUi(){
        webView = findViewById<WebView>(R.id.webView)
        switchAccountBtn = findViewById<Button>(R.id.switch_account_btn)

        val settings = webView.settings

        settings.javaScriptEnabled = true
        settings.domStorageEnabled = true

        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true)

        switchAccountBtn.setOnClickListener { view ->
            val popup = PopupMenu(this, view)

            accountList.forEachIndexed { index, account ->
                popup.menu.add(0, index, index, account.name)
            }

            popup.menu.add(0, accountList.size, accountList.size, "Добавить")

            popup.setOnMenuItemClickListener {
                if(it.itemId == accountList.size){
                    currentToken = ""
                    CookieManager.getInstance().removeAllCookies {  }
                }else{
                    val selectedAccount = accountList[it.itemId]
                    currentToken = selectedAccount.token
                    CookieUtils.setAuthCookie(currentToken)
                }

                webView.reload()
                true
            }

            popup.show()
        }

        webView.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)

                val token = CookieUtils.getAuthToken("attendance.mirea.ru")

                if(token.isNullOrEmpty()) return;

                repo.addIfAbsent(token)
                accountList = repo.getAll()
            }
        }
    }
}