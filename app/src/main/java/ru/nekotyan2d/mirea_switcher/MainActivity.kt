package ru.nekotyan2d.mirea_switcher

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.os.Bundle
import android.webkit.CookieManager
import android.webkit.PermissionRequest
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.PopupMenu
import android.widget.TextView
import android.widget.Toast
import androidx.activity.OnBackPressedCallback
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import ru.nekotyan2d.mirea_switcher.data.model.Account
import ru.nekotyan2d.mirea_switcher.data.repository.AccountRepository
import ru.nekotyan2d.mirea_switcher.utils.CookieUtils
import ru.nekotyan2d.mirea_switcher.utils.GrpcInterceptor

class MainActivity : AppCompatActivity() {
    private lateinit var repo: AccountRepository

    private var accountList: MutableList<Account> = mutableListOf()

    private lateinit var webView: WebView
    private lateinit var switchAccountBtn: Button
    private lateinit var pageTitle: TextView

    private var currentToken: String = ""
    private var currentUserName: String = ""
    private lateinit var grpcInterceptor: GrpcInterceptor
    private var checkedAccounts = false


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
        checkAndRequestPermissions()

        val callback = object : OnBackPressedCallback(true){
            override fun handleOnBackPressed() {
                webView.goBack()
            }
        }

        onBackPressedDispatcher.addCallback(this, callback)
    }

    private fun initUi(){
        switchAccountBtn = findViewById<Button>(R.id.switch_account_btn)
        switchAccountBtn.setOnClickListener { view ->
            val popup = PopupMenu(this, view)

            accountList.forEachIndexed { index, account ->
                popup.menu.add(0, index, index, account.name)
            }

            popup.menu.add(0, accountList.size, accountList.size, "Добавить")

            popup.setOnMenuItemClickListener {
                if(it.itemId == accountList.size){
                    currentToken = ""
                    currentUserName = ""
                    switchAccountBtn.text = getString(R.string.switch_account_btn)
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

        pageTitle = findViewById<TextView>(R.id.page_title)

        initWebView()
    }

    private fun initWebView(){
        webView = findViewById<WebView>(R.id.webView)

        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
        }

        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true)


        webView.webViewClient = object : WebViewClient() {
            override fun onPageStarted(view: WebView?, url: String, favicon: Bitmap?) {
                super.onPageStarted(view, url, favicon)

                view?.evaluateJavascript(GrpcInterceptor.buildInterceptScript(), null)
                view?.evaluateJavascript(GrpcInterceptor.buildHistoryInterceptScript(), null)
                grpcInterceptor.hideHeader(webView)
            }
            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)

                grpcInterceptor.hideHeader(webView)

                val token = CookieUtils.getAuthToken("https://attendance.mirea.ru")

                if(token.isNullOrEmpty()) return

                currentToken = token

                if(checkedAccounts) return

                for(account in accountList){
                    grpcInterceptor.checkToken(webView, account.token)
                }

                checkedAccounts = true
            }
        }

        webView.webChromeClient = object : WebChromeClient(){
            override fun onPermissionRequest(request: PermissionRequest) {
                val requestedResources = request.resources

                val allowedResources = requestedResources.filter {
                    it == PermissionRequest.RESOURCE_VIDEO_CAPTURE
                }

                if(allowedResources.isNotEmpty()){
                    request.grant(allowedResources.toTypedArray())
                }else{
                    request.deny()
                }
            }
        }

        grpcInterceptor = GrpcInterceptor(
            onUserName = {
                name ->
                currentUserName = name
                runOnUiThread { onUserNameReceived(name) }
            },
            onTokenValidated = {
                token, valid ->
                runOnUiThread { onTokenValidated(token, valid) }
            },
            onUrlChanged = {
                url ->
                grpcInterceptor.getTitle(webView, {
                    title ->
                    grpcInterceptor.hideHeader(webView)
                    runOnUiThread { pageTitle.text = title.replace("\"", "")}
                })

            }
        )

        webView.addJavascriptInterface(grpcInterceptor, "AndroidBridge")

        webView.loadUrl("https://pulse.mirea.ru")
    }

    private val requestPermissionLauncher = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        permissions ->
        val cameraGranted = permissions[Manifest.permission.CAMERA] ?: false

        if(cameraGranted){
            initWebView()
        }else{
            Toast.makeText(applicationContext, "Требуется разрешение на использование камеры",
                Toast.LENGTH_SHORT).show()
        }
    }

    private fun checkAndRequestPermissions(){
        val permissionsNeeded = mutableListOf<String>()

        if(ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED){
            permissionsNeeded.add(Manifest.permission.CAMERA)
        }

        if(permissionsNeeded.isNotEmpty()){
            requestPermissionLauncher.launch(permissionsNeeded.toTypedArray())
        }else{
            initWebView()
        }
    }

    private fun onUserNameReceived(name: String) {
        currentUserName = name
        switchAccountBtn.text = currentUserName
        repo.addIfAbsent(currentUserName, currentToken)
        accountList = repo.getAll()
    }

    private fun onTokenValidated(token: String, valid: Boolean){
        if(!valid) repo.remove(token)
        accountList = repo.getAll()
    }
}