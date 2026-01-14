import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../../core/models/api_models.dart';

/// WebView page for displaying installed Docker apps
class AppWebViewPage extends ConsumerStatefulWidget {
  final DockerApp app;
  final String baseUrl;

  const AppWebViewPage({
    super.key,
    required this.app,
    required this.baseUrl,
  });

  @override
  ConsumerState<AppWebViewPage> createState() => _AppWebViewPageState();
}

class _AppWebViewPageState extends ConsumerState<AppWebViewPage> {
  WebViewController? _controller;
  bool _isLoading = true;
  bool _isInitializing = true;
  String? _error;
  double _loadingProgress = 0;
  String _currentUrl = '';
  bool _canGoBack = false;
  bool _canGoForward = false;
  Timer? _initTimer;

  @override
  void initState() {
    super.initState();
    // Delay initialization to ensure widget is fully mounted
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initWebView();
    });
  }

  @override
  void dispose() {
    _initTimer?.cancel();
    super.dispose();
  }

  String get _appUrl {
    // Get the first available port mapping
    if (widget.app.ports.isEmpty) {
      return widget.baseUrl;
    }
    final port = widget.app.ports.first.hostPort;
    // Extract host from baseUrl
    final uri = Uri.parse(widget.baseUrl);
    return '${uri.scheme}://${uri.host}:$port';
  }

  void _initWebView() {
    if (kIsWeb) {
      setState(() {
        _error =
            'WebView is not supported on web platform. Please open in browser.';
        _isLoading = false;
        _isInitializing = false;
      });
      return;
    }

    try {
      debugPrint('Initializing WebView for URL: $_appUrl');

      final controller = WebViewController();

      controller
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.white)
        ..enableZoom(true)
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (progress) {
              if (mounted) {
                setState(() {
                  _loadingProgress = progress / 100;
                });
              }
            },
            onPageStarted: (url) {
              debugPrint('Page started loading: $url');
              if (mounted) {
                setState(() {
                  _isLoading = true;
                  _currentUrl = url;
                  _error = null;
                });
              }
            },
            onPageFinished: (url) async {
              debugPrint('Page finished loading: $url');
              if (mounted) {
                setState(() {
                  _isLoading = false;
                  _isInitializing = false;
                  _currentUrl = url;
                });
                _updateNavigationState();
              }
            },
            onWebResourceError: (error) {
              debugPrint(
                  'WebView error: ${error.errorCode} - ${error.description}');
              // Only show error for main frame errors
              if ((error.isForMainFrame ?? false) && mounted) {
                setState(() {
                  _error = _getErrorMessage(error);
                  _isLoading = false;
                  _isInitializing = false;
                });
              }
            },
            onHttpError: (error) {
              debugPrint('HTTP error: ${error.response?.statusCode}');
              if (mounted && error.response?.statusCode == 404) {
                setState(() {
                  _error =
                      'App not responding (404). Make sure the app is running.';
                  _isLoading = false;
                  _isInitializing = false;
                });
              }
            },
            onNavigationRequest: (request) {
              debugPrint('Navigation request: ${request.url}');
              // Allow all navigation within the app
              return NavigationDecision.navigate;
            },
          ),
        );

      // Set user agent to avoid mobile detection issues
      controller.setUserAgent(
          'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.120 Mobile Safari/537.36');

      setState(() {
        _controller = controller;
      });

      // Load the URL
      controller.loadRequest(Uri.parse(_appUrl)).catchError((e) {
        debugPrint('Error loading URL: $e');
        if (mounted) {
          setState(() {
            _error = 'Failed to load: $e';
            _isLoading = false;
            _isInitializing = false;
          });
        }
      });

      // Set a timeout for initial load
      _initTimer = Timer(const Duration(seconds: 30), () {
        if (mounted && _isInitializing) {
          setState(() {
            _error =
                'Connection timeout. The app may not be running or is taking too long to respond.';
            _isLoading = false;
            _isInitializing = false;
          });
        }
      });
    } catch (e) {
      debugPrint('WebView initialization error: $e');
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
      case -2: // ERR_FAILED
        return 'Connection failed. Make sure the app is running and accessible.';
      case -6: // ERR_CONNECTION_REFUSED
        return 'Connection refused. The app may not be running on port ${widget.app.ports.isNotEmpty ? widget.app.ports.first.hostPort : "unknown"}.';
      case -7: // ERR_CONNECTION_TIMED_OUT
        return 'Connection timed out. The app is not responding.';
      case -105: // ERR_NAME_NOT_RESOLVED
        return 'Could not resolve host. Check your network connection.';
      case -106: // ERR_INTERNET_DISCONNECTED
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
      final canGoBack = await _controller!.canGoBack();
      final canGoForward = await _controller!.canGoForward();
      if (mounted) {
        setState(() {
          _canGoBack = canGoBack;
          _canGoForward = canGoForward;
        });
      }
    } catch (e) {
      debugPrint('Error updating navigation state: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            _AppIcon(iconUrl: widget.app.icon, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.app.displayName,
                    style: const TextStyle(fontSize: 16),
                  ),
                  Text(
                    _currentUrl.isNotEmpty ? _currentUrl : _appUrl,
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
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
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'home',
                child: Row(
                  children: [
                    Icon(Icons.home_rounded),
                    SizedBox(width: 12),
                    Text('Go to Home'),
                  ],
                ),
              ),
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
    if (_error != null) {
      return _buildErrorState();
    }

    if (kIsWeb) {
      return _buildWebPlatformMessage();
    }

    if (_isInitializing || _controller == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Connecting to ${widget.app.displayName}...',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _appUrl,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant
                    .withValues(alpha: 0.7),
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
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.error_outline_rounded,
                size: 44,
                color: colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Failed to load app',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'URL: $_appUrl',
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
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
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () => _openInBrowser(),
              icon: const Icon(Icons.open_in_browser_rounded),
              label: const Text('Open in Browser'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebPlatformMessage() {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.web_rounded,
                size: 44,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Open in New Tab',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'WebView is not available on web platform.\nClick below to open the app in a new browser tab.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _openInBrowser,
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text('Open ${widget.app.displayName}'),
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
                icon: Icon(
                  Icons.arrow_back_rounded,
                  color: _canGoBack
                      ? colorScheme.onSurface
                      : colorScheme.onSurface.withValues(alpha: 0.3),
                ),
                onPressed: _canGoBack ? () => _controller?.goBack() : null,
                tooltip: 'Back',
              ),
              IconButton(
                icon: Icon(
                  Icons.arrow_forward_rounded,
                  color: _canGoForward
                      ? colorScheme.onSurface
                      : colorScheme.onSurface.withValues(alpha: 0.3),
                ),
                onPressed:
                    _canGoForward ? () => _controller?.goForward() : null,
                tooltip: 'Forward',
              ),
              IconButton(
                icon: const Icon(Icons.home_rounded),
                onPressed: () => _controller?.loadRequest(Uri.parse(_appUrl)),
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
    final url = Uri.parse(_appUrl);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open browser')),
        );
      }
    }
  }

  void _handleMenuAction(String action) {
    switch (action) {
      case 'home':
        _controller?.loadRequest(Uri.parse(_appUrl));
        break;
      case 'open_browser':
        _openInBrowser();
        break;
      case 'copy_url':
        final url = _currentUrl.isNotEmpty ? _currentUrl : _appUrl;
        Clipboard.setData(ClipboardData(text: url));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('URL copied to clipboard')),
        );
        break;
    }
  }
}

class _AppIcon extends StatelessWidget {
  final String iconUrl;
  final double size;

  const _AppIcon({required this.iconUrl, this.size = 48});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primaryContainer,
            colorScheme.secondaryContainer,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.22),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: iconUrl.isNotEmpty
          ? Image.network(
              iconUrl,
              fit: BoxFit.cover,
              errorBuilder: (c, e, s) => _buildFallbackIcon(context),
            )
          : _buildFallbackIcon(context),
    );
  }

  Widget _buildFallbackIcon(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primary.withValues(alpha: 0.8),
            colorScheme.tertiary.withValues(alpha: 0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(
        Icons.apps_rounded,
        size: size * 0.5,
        color: Colors.white,
      ),
    );
  }
}
