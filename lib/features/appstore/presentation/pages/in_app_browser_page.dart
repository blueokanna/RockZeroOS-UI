import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 通用内置浏览器页面 —— 用于在应用内打开外部 URL（Steam / Epic / WASM 等）
///
/// 支持 Android / iOS / macOS / Windows / Linux 的 WebView。
/// Web 平台自动回退到 url_launcher。
class InAppBrowserPage extends StatefulWidget {
  final String url;
  final String? initialUrl;
  final String title;
  final String? iconUrl;
  /// 嵌入模式：不显示 Scaffold / AppBar，仅显示 WebView 内容
  final bool embedded;

  const InAppBrowserPage({
    super.key,
    this.url = '',
    this.initialUrl,
    this.title = '',
    this.iconUrl,
    this.embedded = false,
  });

  /// 便捷方法：push 一个 InAppBrowserPage
  static Future<void> open(
    BuildContext context, {
    required String url,
    String title = '',
    String? iconUrl,
  }) async {
    if (kIsWeb) {
      // Web 平台直接用 url_launcher
      final uri = Uri.tryParse(url);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InAppBrowserPage(
          url: url,
          title: title,
          iconUrl: iconUrl,
        ),
      ),
    );
  }

  @override
  State<InAppBrowserPage> createState() => _InAppBrowserPageState();
}

class _InAppBrowserPageState extends State<InAppBrowserPage> {
  WebViewController? _controller;
  bool _isLoading = true;
  bool _isInitializing = true;
  String? _error;
  double _loadingProgress = 0;
  String _currentUrl = '';
  String _pageTitle = '';
  bool _canGoBack = false;
  bool _canGoForward = false;
  Timer? _initTimer;

  @override
  void initState() {
    super.initState();
    _pageTitle = widget.title;
    _currentUrl = widget.initialUrl ?? widget.url;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initWebView();
    });
  }

  @override
  void dispose() {
    _initTimer?.cancel();
    super.dispose();
  }

  void _initWebView() {
    if (kIsWeb) {
      setState(() {
        _error = 'WebView is not supported on web. Please use the browser.';
        _isLoading = false;
        _isInitializing = false;
      });
      return;
    }

    try {
      final controller = WebViewController();

      controller
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.white)
        ..enableZoom(true)
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (progress) {
              if (mounted) {
                setState(() => _loadingProgress = progress / 100);
              }
            },
            onPageStarted: (url) {
              if (mounted) {
                setState(() {
                  _isLoading = true;
                  _currentUrl = url;
                  _error = null;
                });
              }
            },
            onPageFinished: (url) async {
              if (mounted) {
                setState(() {
                  _isLoading = false;
                  _isInitializing = false;
                  _currentUrl = url;
                });
                _updateNavigationState();
                // 获取页面标题
                try {
                  final title = await _controller?.getTitle();
                  if (mounted && title != null && title.isNotEmpty) {
                    setState(() => _pageTitle = title);
                  }
                } catch (_) {}
              }
            },
            onWebResourceError: (error) {
              if ((error.isForMainFrame ?? false) && mounted) {
                setState(() {
                  _error = _getErrorMessage(error);
                  _isLoading = false;
                  _isInitializing = false;
                });
              }
            },
            onHttpError: (error) {
              if (mounted && error.response?.statusCode == 404) {
                setState(() {
                  _error = 'Page not found (404).';
                  _isLoading = false;
                  _isInitializing = false;
                });
              }
            },
            onNavigationRequest: (request) {
              // 拦截 steam:// 或 com.epicgames.launcher:// 等 scheme
              final uri = Uri.tryParse(request.url);
              if (uri != null &&
                  !['http', 'https', 'about', 'data']
                      .contains(uri.scheme.toLowerCase())) {
                // 用 url_launcher 处理自定义 scheme
                launchUrl(uri, mode: LaunchMode.externalApplication);
                return NavigationDecision.prevent;
              }
              return NavigationDecision.navigate;
            },
          ),
        );

      // Mobile-friendly user agent
      controller.setUserAgent(
        'Mozilla/5.0 (Linux; Android 14) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/122.0.0.0 Mobile Safari/537.36',
      );

      setState(() => _controller = controller);

      controller.loadRequest(Uri.parse(widget.initialUrl ?? widget.url)).catchError((e) {
        if (mounted) {
          setState(() {
            _error = 'Failed to load: $e';
            _isLoading = false;
            _isInitializing = false;
          });
        }
      });

      _initTimer = Timer(const Duration(seconds: 30), () {
        if (mounted && _isInitializing) {
          setState(() {
            _error = 'Connection timeout.';
            _isLoading = false;
            _isInitializing = false;
          });
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to initialize WebView: $e';
          _isLoading = false;
          _isInitializing = false;
        });
      }
    }
  }

  String _getErrorMessage(WebResourceError error) {
    switch (error.errorCode) {
      case -2:
        return 'Connection failed.';
      case -6:
        return 'Connection refused.';
      case -7:
        return 'Connection timed out.';
      case -105:
        return 'Could not resolve host.';
      case -106:
        return 'No internet connection.';
      default:
        final desc = error.description;
        return desc.isNotEmpty
            ? desc
            : 'Unknown error (code: ${error.errorCode})';
    }
  }

  Future<void> _updateNavigationState() async {
    if (_controller == null) return;
    try {
      final back = await _controller!.canGoBack();
      final fwd = await _controller!.canGoForward();
      if (mounted) {
        setState(() {
          _canGoBack = back;
          _canGoForward = fwd;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // 嵌入模式：只显示 WebView 内容 + 底部导航栏（不含 Scaffold / AppBar）
    if (widget.embedded) {
      return Column(
        children: [
          // 加载进度条
          if (_isLoading)
            LinearProgressIndicator(
              value: _loadingProgress > 0 ? _loadingProgress : null,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation(colorScheme.primary),
              minHeight: 2,
            ),
          // 主体内容
          Expanded(child: _buildBody()),
          // 底部导航栏
          _buildBottomBar(colorScheme),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _pageTitle.isNotEmpty ? _pageTitle : widget.title,
              style: const TextStyle(fontSize: 16),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              _currentUrl,
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed:
                _error != null ? _initWebView : () => _controller?.reload(),
            tooltip: 'Refresh',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: _handleMenuAction,
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'open_browser',
                child: Row(
                  children: [
                    Icon(Icons.open_in_browser_rounded),
                    SizedBox(width: 12),
                    Text('Open in Browser'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'copy_url',
                child: Row(
                  children: [
                    Icon(Icons.copy_rounded),
                    SizedBox(width: 12),
                    Text('Copy URL'),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: _isLoading
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(
                  value: _loadingProgress > 0 ? _loadingProgress : null,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation(colorScheme.primary),
                ),
              )
            : null,
      ),
      body: _buildBody(),
      bottomNavigationBar: _buildBottomBar(colorScheme),
    );
  }

  Widget _buildBody() {
    if (_error != null) return _buildErrorState();

    if (_isInitializing || _controller == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Loading...',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return WebViewWidget(controller: _controller!);
  }

  Widget _buildErrorState() {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded,
                size: 64, color: colorScheme.error),
            const SizedBox(height: 16),
            Text(_error ?? 'Unknown error',
                textAlign: TextAlign.center,
                style: TextStyle(color: colorScheme.onSurfaceVariant)),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Go Back'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      _error = null;
                      _isLoading = true;
                      _isInitializing = true;
                    });
                    _initWebView();
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _openInBrowser,
              icon: const Icon(Icons.open_in_browser_rounded),
              label: const Text('Open in Browser'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_rounded,
                    color: _canGoBack
                        ? colorScheme.onSurface
                        : colorScheme.onSurface.withValues(alpha: 0.3)),
                onPressed: _canGoBack ? () => _controller?.goBack() : null,
                tooltip: 'Back',
              ),
              IconButton(
                icon: Icon(Icons.arrow_forward_rounded,
                    color: _canGoForward
                        ? colorScheme.onSurface
                        : colorScheme.onSurface.withValues(alpha: 0.3)),
                onPressed:
                    _canGoForward ? () => _controller?.goForward() : null,
                tooltip: 'Forward',
              ),
              IconButton(
                icon: const Icon(Icons.home_rounded),
                onPressed: () => _controller?.loadRequest(
                    Uri.parse(widget.initialUrl ?? widget.url)),
                tooltip: 'Home',
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: () => _controller?.reload(),
                tooltip: 'Refresh',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openInBrowser() async {
    final uri = Uri.tryParse(_currentUrl.isNotEmpty ? _currentUrl : widget.url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _handleMenuAction(String action) {
    switch (action) {
      case 'open_browser':
        _openInBrowser();
        break;
      case 'copy_url':
        final url = _currentUrl.isNotEmpty ? _currentUrl : widget.url;
        Clipboard.setData(ClipboardData(text: url));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('URL copied to clipboard')),
        );
        break;
    }
  }
}
