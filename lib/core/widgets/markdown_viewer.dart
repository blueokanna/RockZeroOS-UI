import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

class MarkdownViewer extends StatelessWidget {
  final String data;
  final bool selectable;
  final EdgeInsets? padding;
  final ScrollPhysics? physics;
  final bool shrinkWrap;
  final String? baseUrl;

  const MarkdownViewer({
    super.key,
    required this.data,
    this.selectable = true,
    this.padding,
    this.physics,
    this.shrinkWrap = false,
    this.baseUrl,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final styleSheet = MarkdownStyleSheet(
      h1: textTheme.headlineLarge?.copyWith(
        fontWeight: FontWeight.bold,
        color: colorScheme.onSurface,
      ),
      h2: textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: colorScheme.onSurface,
      ),
      h3: textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
      ),
      h4: textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
      ),
      h5: textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
      ),
      h6: textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
      ),
      p: textTheme.bodyMedium?.copyWith(
        color: colorScheme.onSurface,
        height: 1.6,
      ),
      code: textTheme.bodySmall?.copyWith(
        fontFamily: 'monospace',
        backgroundColor: colorScheme.surfaceContainerHighest,
        color: colorScheme.primary,
      ),
      codeblockDecoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant,
          width: 1,
        ),
      ),
      codeblockPadding: const EdgeInsets.all(16),
      blockquote: textTheme.bodyMedium?.copyWith(
        color: colorScheme.onSurfaceVariant,
        fontStyle: FontStyle.italic,
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: colorScheme.primary,
            width: 4,
          ),
        ),
      ),
      blockquotePadding: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
      listBullet: textTheme.bodyMedium?.copyWith(
        color: colorScheme.primary,
      ),
      tableHead: textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: colorScheme.onSurface,
      ),
      tableBody: textTheme.bodyMedium?.copyWith(
        color: colorScheme.onSurface,
      ),
      tableBorder: TableBorder.all(
        color: colorScheme.outlineVariant,
        width: 1,
      ),
      tableHeadAlign: TextAlign.center,
      tableCellsPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      a: textTheme.bodyMedium?.copyWith(
        color: colorScheme.primary,
        decoration: TextDecoration.underline,
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant,
            width: 1,
          ),
        ),
      ),
      img: textTheme.bodyMedium,
      strong: textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: colorScheme.onSurface,
      ),
      em: textTheme.bodyMedium?.copyWith(
        fontStyle: FontStyle.italic,
        color: colorScheme.onSurface,
      ),
      del: textTheme.bodyMedium?.copyWith(
        decoration: TextDecoration.lineThrough,
        color: colorScheme.onSurfaceVariant,
      ),
    );

    if (selectable) {
      return Markdown(
        data: data,
        selectable: true,
        padding: padding ?? const EdgeInsets.all(16),
        physics: physics,
        shrinkWrap: shrinkWrap,
        styleSheet: styleSheet,
        onTapLink: (text, href, title) => _onTapLink(context, href),
        sizedImageBuilder: (config) =>
            _buildImage(context, config.uri, config.title, config.alt),
      );
    }

    return Markdown(
      data: data,
      padding: padding ?? const EdgeInsets.all(16),
      physics: physics,
      shrinkWrap: shrinkWrap,
      styleSheet: styleSheet,
      onTapLink: (text, href, title) => _onTapLink(context, href),
      sizedImageBuilder: (config) =>
          _buildImage(context, config.uri, config.title, config.alt),
    );
  }

  void _onTapLink(BuildContext context, String? href) async {
    if (href == null || href.isEmpty) return;

    final uri = Uri.tryParse(href);
    if (uri == null) return;

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('无法打开链接: $href'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('打开链接失败: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _buildImage(
      BuildContext context, Uri uri, String? title, String? alt) {
    final colorScheme = Theme.of(context).colorScheme;

    String imageUrl = uri.toString();
    if (baseUrl != null && !imageUrl.startsWith('http')) {
      imageUrl = '$baseUrl/$imageUrl';
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          imageUrl,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            if (uri.toString().contains('RockZero.png') ||
                uri.toString().contains('assets/images')) {
              return Image.asset(
                'assets/images/RockZero.png',
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.broken_image, color: colorScheme.error),
                        const SizedBox(width: 8),
                        Text(
                          alt ?? '图片加载失败',
                          style: TextStyle(color: colorScheme.error),
                        ),
                      ],
                    ),
                  );
                },
              );
            }
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.broken_image, color: colorScheme.error),
                  const SizedBox(width: 8),
                  Text(
                    alt ?? '图片加载失败',
                    style: TextStyle(color: colorScheme.error),
                  ),
                ],
              ),
            );
          },
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Container(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: CircularProgressIndicator(
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                      : null,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class MarkdownViewerPage extends StatefulWidget {
  final String? filePath;
  final String? content;
  final String? title;
  final String? baseUrl;

  const MarkdownViewerPage({
    super.key,
    this.filePath,
    this.content,
    this.title,
    this.baseUrl,
  }) : assert(filePath != null || content != null,
            'Either filePath or content must be provided');

  @override
  State<MarkdownViewerPage> createState() => _MarkdownViewerPageState();
}

class _MarkdownViewerPageState extends State<MarkdownViewerPage> {
  String? _content;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  Future<void> _loadContent() async {
    if (widget.content != null) {
      setState(() {
        _content = widget.content;
        _isLoading = false;
      });
      return;
    }

    if (widget.filePath != null) {
      try {
        if (widget.filePath!.startsWith('http')) {
          setState(() {
            _error = '网络文件加载暂不支持';
            _isLoading = false;
          });
        } else {
          setState(() {
            _error = '本地文件加载暂不支持';
            _isLoading = false;
          });
        }
      } catch (e) {
        setState(() {
          _error = '加载失败: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? 'Markdown'),
        actions: [
          if (_content != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _error = null;
                });
                _loadContent();
              },
            ),
        ],
      ),
      body: _buildBody(colorScheme),
    );
  }

  Widget _buildBody(ColorScheme colorScheme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: colorScheme.error),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: colorScheme.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _error = null;
                });
                _loadContent();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_content == null) {
      return const Center(child: Text('无内容'));
    }

    return MarkdownViewer(
      data: _content!,
      baseUrl: widget.baseUrl,
    );
  }
}
