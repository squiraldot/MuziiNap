import 'package:flutter/material.dart';
import '../../../services/constant.dart';
import 'package:get/get.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:convert';
import 'dart:async';

import 'package:hive/hive.dart';
import '../../../services/music_service.dart';
import '../Home/home_screen_controller.dart';
import '../Library/library_controller.dart';
import '../../../utils/youtube_login_utils.dart';
import '../../../utils/youtube_auth.dart';

class YoutubeLoginScreen extends StatefulWidget {
  const YoutubeLoginScreen({super.key});

  @override
  State<YoutubeLoginScreen> createState() => _YoutubeLoginScreenState();
}

class _YoutubeLoginScreenState extends State<YoutubeLoginScreen> {
  late final WebViewController _webViewController;
  final WebViewCookieManager _cookieManager = WebViewCookieManager();
  bool _isLoading = true;
  bool _loginCompleting = false;
  Timer? _sessionPoller;

  @override
  void initState() {
    super.initState();
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
            });
          },
          onPageFinished: (String url) async {
            if (!mounted) return;
            setState(() {
              _isLoading = false;
            });
            await _checkAndExtractSession();
          },
          onWebResourceError: (WebResourceError error) {
            // SetSID may transiently reset while Google completes the
            // redirect. Keep polling the WebView cookies instead of reloading.
            if (error.isForMainFrame != true) return;
            if (error.url?.contains('accounts.youtube.com/accounts/SetSID') ?? false) {
              // Google may reset the SetSID connection after a successful
              // sign-in. Auth cookies are often already committed, so recover
              // by returning to YouTube instead of leaving the user on the
              // WebView network-error page.
              Future<void>.delayed(const Duration(milliseconds: 350), () async {
                if (!mounted || _loginCompleting) return;
                await _webViewController.loadRequest(
                  Uri.parse('https://music.youtube.com/'),
                );
                await _checkAndExtractSession();
              });
              return;
            }
            if (mounted) {
              Get.snackbar(
                'YouTube Login',
                'The YouTube login page reported a network error. You can continue or tap refresh.',
                snackPosition: SnackPosition.BOTTOM,
              );
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(buildYouTubeLoginUrl()));
    _sessionPoller = Timer.periodic(const Duration(seconds: 2), (_) {
      _checkAndExtractSession();
    });
  }

  Future<void> _checkAndExtractSession() async {
    if (_loginCompleting) return;

    try {
      final rawContext = await _webViewController.runJavaScriptReturningResult(
        '''
          (function () {
            var c = window.ytcfg;
            var y = window.yt && window.yt.config_;
            var get = c && c.get ? c.get.bind(c) : null;
            return JSON.stringify({
              visitorData: (get && get('VISITOR_DATA')) || (y && y.VISITOR_DATA) || null,
              dataSyncId: (get && get('DATASYNC_ID')) || (y && y.DATASYNC_ID) || null,
              authUser: String((get && get('SESSION_INDEX')) || (y && y.SESSION_INDEX) || 0),
              identityToken: (get && get('ID_TOKEN')) || (y && y.ID_TOKEN) || null
            });
          })()
        ''',
      );
      final contextText = rawContext is String ? rawContext : rawContext.toString();
      dynamic decoded = contextText;
      try {
        decoded = jsonDecode(contextText);
      } catch (_) {}
      if (decoded is String) {
        try {
          decoded = jsonDecode(decoded);
        } catch (_) {}
      }
      final sessionContext = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};

      final merged = <String, String>{};
      for (final uri in const [
        'https://music.youtube.com',
        'https://www.youtube.com',
        'https://youtube.com',
      ]) {
        final cookies = await _cookieManager.getCookies(domain: Uri.parse(uri));
        for (final cookie in cookies) {
          if (cookie.name.isNotEmpty && cookie.value.isNotEmpty) {
            merged[cookie.name] = cookie.value;
          }
        }
      }

      final cookies = merged.entries
          .map((entry) => '${entry.key}=${entry.value}')
          .join('; ');
      final hasSapIsid = merged.containsKey('SAPISID') ||
          merged.containsKey('__Secure-3PAPISID') ||
          merged.containsKey('__Secure-1PAPISID');
      final hasSessionCookie = merged.containsKey('SID') ||
          merged.containsKey('__Secure-3PSID') ||
          merged.containsKey('__Secure-3PSIDTS');

      if (!hasSapIsid || !hasSessionCookie || cookies.isEmpty) return;

      final musicServices = Get.isRegistered<MusicServices>()
          ? Get.find<MusicServices>()
          : null;
      if (musicServices == null) return;

      _loginCompleting = true;
      final authReady = await musicServices.updateAuthCookies(
        cookies,
        visitorData: sessionContext['visitorData']?.toString(),
        dataSyncId: sessionContext['dataSyncId']?.toString(),
        authUser: sessionContext['authUser']?.toString(),
        identityToken: sessionContext['identityToken']?.toString(),
      );
      if (!authReady) {
        _loginCompleting = false;
        return;
      }

      final sessionValid = await musicServices.validateYouTubeSession();
      if (!sessionValid) {
        musicServices.clearAuthCookies();
        _loginCompleting = false;
        if (mounted) {
          Get.snackbar(
            "YouTube Login",
            "The YouTube session could not be verified. Please finish signing in and try again.",
            snackPosition: SnackPosition.BOTTOM,
          );
        }
        return;
      }

      final box = Hive.box(appPrefsBoxName);
      Map<String, String?> accountInfo = {};
      try {
        accountInfo = await musicServices.getYouTubeAccountInfo();
      } catch (_) {
        // Profile metadata is cosmetic; a verified session is still valid.
      }

      final identity = YouTubeSessionIdentity.fromDataSyncId(
        sessionContext['dataSyncId']?.toString(),
        authUser: sessionContext['authUser']?.toString(),
      );
      final accounts = <String, dynamic>{};
      final storedAccounts = box.get('yt_accounts');
      if (storedAccounts is Map) {
        accounts.addAll(
          storedAccounts.map(
            (key, value) => MapEntry(key.toString(), value),
          ),
        );
      }
      accounts[identity.accountKey] = {
        'cookies': cookies,
        'visitorData': sessionContext['visitorData']?.toString(),
        'dataSyncId': sessionContext['dataSyncId']?.toString(),
        'authUser': identity.authUser,
        'identityToken': sessionContext['identityToken']?.toString(),
        'accountName': accountInfo['accountName'],
        'channelHandle': accountInfo['channelHandle'],
        'accountPhotoUrl': accountInfo['accountPhotoUrl'],
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      };
      await box.put('yt_accounts', accounts);
      await box.put('yt_active_account_key', identity.accountKey);
      await box.put('yt_cookies', cookies);
      await box.put('yt_logged_in', true);

      final accountName = accountInfo['accountName']?.toString().trim() ?? '';
      final accountPhoto = accountInfo['accountPhotoUrl']?.toString().trim() ?? '';
      if (accountName.isNotEmpty) {
        await box.put('AccountName', accountName);
      }
      if (accountPhoto.isNotEmpty) {
        await box.put('AccountThumbUrl', accountPhoto);
      }
      if (sessionContext['visitorData']?.toString().trim().isNotEmpty == true) {
        await box.put('yt_visitor_data', sessionContext['visitorData'].toString());
      }
      if (sessionContext['dataSyncId']?.toString().trim().isNotEmpty == true) {
        await box.put('yt_data_sync_id', sessionContext['dataSyncId'].toString());
      }
      await box.put('yt_auth_user', sessionContext['authUser']?.toString() ?? '0');
      if (sessionContext['identityToken']?.toString().trim().isNotEmpty == true) {
        await box.put('yt_identity_token', sessionContext['identityToken'].toString());
      }

      try {
        if (Get.isRegistered<HomeScreenController>()) {
          await Get.find<HomeScreenController>().refreshHome();
        }
        if (Get.isRegistered<LibraryPlaylistsController>()) {
          Get.find<LibraryPlaylistsController>().refreshLib();
        }
      } catch (_) {
        // Authentication is already verified; UI refresh can retry on the next screen load.
      }

      if (mounted) {
        Get.back(result: true);
        Get.snackbar(
          "YouTube Login",
          "YouTube account connected and verified.",
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.grey[900],
          colorText: Colors.white,
        );
      }
    } catch (_) {
      _loginCompleting = false;
    }
  }

  @override
  void dispose() {
    _sessionPoller?.cancel();
    _sessionPoller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Sign in to YouTube"),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _webViewController.reload(),
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _webViewController),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
        ],
      ),
    );
  }
}
