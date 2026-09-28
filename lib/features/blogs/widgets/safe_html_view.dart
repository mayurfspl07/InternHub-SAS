import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/api/api_config.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';

class SafeHtmlView extends StatelessWidget {
  final String html;
  final TextStyle? baseStyle;

  const SafeHtmlView({
    super.key,
    required this.html,
    this.baseStyle,
  });

  @override
  Widget build(BuildContext context) {
    if (html.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final primaryTextColor = AppColors.ink;
    final secondaryTextColor = AppColors.textSecondary;
    final codeBg = AppColors.surfaceMuted;
    final quoteBorder = AppColors.info;

    // List items become their own blocks with a marker: "\u0001• " for <ul>, "\u0001N. " for <ol>.
    var raw = html.trim().replaceAllMapped(
      RegExp(r'<ol[^>]*>([\s\S]*?)</ol>', caseSensitive: false),
      (m) {
        var n = 0;
        return m.group(1)!.replaceAllMapped(RegExp(r'<li[^>]*>', caseSensitive: false), (_) => '\n\n\u0001${++n}. ');
      },
    );
    raw = raw.replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '\n\n\u0001• ');
    raw = raw.replaceAll(RegExp(r'</?(ul|ol)[^>]*>', caseSensitive: false), '\n\n');
    // Normalize newlines in pre/code or block tags
    raw = raw.replaceAll(RegExp(r'<\/(p|h1|h2|h3|h4|h5|h6|li|blockquote|pre)>', caseSensitive: false), '\n\n');
    raw = raw.replaceAll(RegExp(r'<(br|hr)[^>]*\/?>', caseSensitive: false), '\n');

    // Split into paragraphs/blocks
    final blocks = raw.split(RegExp(r'\n{2,}'));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks.map((block) {
        final trimmed = block.trim();
        if (trimmed.isEmpty) return const SizedBox.shrink();

        // Check if image tag
        final imgMatch = RegExp(r"""<img[^>]+src=["']([^"']+)["']""", caseSensitive: false).firstMatch(trimmed);
        if (imgMatch != null) {
          final src = imgMatch.group(1);
          if (src != null && src.isNotEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  ApiConfig.mediaUrl(src),
                  fit: BoxFit.cover,
                  width: double.infinity,
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 180,
                    color: codeBg,
                    child: Center(
                      child: Icon(Icons.broken_image_outlined, color: secondaryTextColor, size: 40),
                    ),
                  ),
                ),
              ),
            );
          }
        }

        // List item (marked above)
        if (trimmed.startsWith('\u0001')) {
          final body = trimmed.substring(1);
          final gap = body.indexOf(' ');
          final marker = gap > 0 ? body.substring(0, gap) : '•';
          final rest = gap > 0 ? body.substring(gap + 1) : body;
          return Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 24, child: Text(marker, style: AppTypography.body.copyWith(height: 1.7, color: primaryTextColor))),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: baseStyle ?? AppTypography.body.copyWith(height: 1.7, color: secondaryTextColor),
                      children: _parseInlineSpans(rest, context, primaryTextColor),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        // Headings h1-h6
        final heading = RegExp(r'<h([1-6])[^>]*>', caseSensitive: false).firstMatch(trimmed);
        if (heading != null) {
          final level = int.parse(heading.group(1)!);
          final style = switch (level) {
            1 => AppTypography.headline,
            2 => AppTypography.title,
            3 => AppTypography.section,
            _ => AppTypography.cardTitle,
          };
          return Padding(
            padding: EdgeInsets.only(top: level <= 2 ? 20 : 14, bottom: 8),
            child: Semantics(
              header: true,
              child: Text(
                _stripTags(trimmed),
                style: style.copyWith(fontWeight: FontWeight.w700, color: primaryTextColor, height: 1.3),
              ),
            ),
          );
        }

        // Check if blockquote
        final isQuote = RegExp(r'<blockquote[^>]*>', caseSensitive: false).hasMatch(trimmed);
        if (isQuote) {
          final cleanQuote = _stripTags(trimmed);
          return Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: quoteBorder, width: 4)),
              color: quoteBorder.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(8),
                bottomRight: Radius.circular(8),
              ),
            ),
            child: Text(
              cleanQuote,
              style: AppTypography.body.copyWith(fontStyle: FontStyle.italic, height: 1.6, color: primaryTextColor),
            ),
          );
        }

        // Check if pre / code block
        final isCode = RegExp(r'<(pre|code)[^>]*>', caseSensitive: false).hasMatch(trimmed);
        if (isCode) {
          final cleanCode = _stripTags(trimmed);
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(vertical: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: codeBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              cleanCode,
              style: AppTypography.mono.copyWith(
                fontSize: 12.5,
                height: 1.5,
                color: primaryTextColor,
              ),
            ),
          );
        }

        // Regular paragraph with rich inline text (bold, italic, links)
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text.rich(
            TextSpan(
              style: baseStyle ??
                  AppTypography.body.copyWith(height: 1.7, color: secondaryTextColor),
              children: _parseInlineSpans(trimmed, context, primaryTextColor),
            ),
          ),
        );
      }).toList(),
    );
  }

  static const _entities = {
    'nbsp': ' ', 'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'",
    'mdash': '—', 'ndash': '–', 'hellip': '…', 'rsquo': '’', 'lsquo': '‘', 'rdquo': '”', 'ldquo': '“',
    'copy': '©', 'reg': '®', 'trade': '™', 'bull': '•', 'middot': '·', 'rarr': '→', 'larr': '←',
  };

  /// Removes tags and decodes named and numeric (&#39; / &#x27;) entities.
  static String _stripTags(String input) {
    final noTags = input.replaceAll(RegExp(r'<[^>]*>'), '');
    return noTags.replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);'), (m) {
      final code = m.group(1)!;
      if (code.startsWith('#x') || code.startsWith('#X')) {
        final v = int.tryParse(code.substring(2), radix: 16);
        return v == null ? m.group(0)! : String.fromCharCode(v);
      }
      if (code.startsWith('#')) {
        final v = int.tryParse(code.substring(1));
        return v == null ? m.group(0)! : String.fromCharCode(v);
      }
      return _entities[code.toLowerCase()] ?? m.group(0)!;
    }).trim();
  }

  List<InlineSpan> _parseInlineSpans(String text, BuildContext context, Color primaryTextColor) {
    final spans = <InlineSpan>[];
    final tagRegex = RegExp(r'<(\/?)(strong|b|em|i|u|a|code)[^>]*>', caseSensitive: false);

    bool isBold = false;
    bool isItalic = false;
    bool isUnderline = false;
    bool isCode = false;
    String? linkUrl;

    int lastIndex = 0;

    for (final match in tagRegex.allMatches(text)) {
      if (match.start > lastIndex) {
        final content = _stripTags(text.substring(lastIndex, match.start));
        if (content.isNotEmpty) {
          spans.add(_createSpan(
            content,
            isBold: isBold,
            isItalic: isItalic,
            isUnderline: isUnderline,
            isCode: isCode,
            linkUrl: linkUrl,
            context: context,
            primaryTextColor: primaryTextColor,
          ));
        }
      }

      final isClosing = match.group(1) == '/';
      final rawTag = match.group(0) ?? '';
      final tagName = match.group(2)?.toLowerCase() ?? '';

      if (tagName == 'strong' || tagName == 'b') {
        isBold = !isClosing;
      } else if (tagName == 'em' || tagName == 'i') {
        isItalic = !isClosing;
      } else if (tagName == 'u') {
        isUnderline = !isClosing;
      } else if (tagName == 'code') {
        isCode = !isClosing;
      } else if (tagName == 'a') {
        if (isClosing) {
          linkUrl = null;
        } else {
          final hrefMatch = RegExp(r"""href=["']([^"']+)["']""", caseSensitive: false).firstMatch(rawTag);
          linkUrl = hrefMatch?.group(1);
        }
      }

      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      final content = _stripTags(text.substring(lastIndex));
      if (content.isNotEmpty) {
        spans.add(_createSpan(
          content,
          isBold: isBold,
          isItalic: isItalic,
          isUnderline: isUnderline,
          isCode: isCode,
          linkUrl: linkUrl,
          context: context,
          primaryTextColor: primaryTextColor,
        ));
      }
    }

    return spans;
  }

  InlineSpan _createSpan(
    String content, {
    required bool isBold,
    required bool isItalic,
    required bool isUnderline,
    required bool isCode,
    required String? linkUrl,
    required BuildContext context,
    required Color primaryTextColor,
  }) {
    if (linkUrl != null && linkUrl.isNotEmpty) {
      return TextSpan(
        text: content,
        style: const TextStyle(
          color: AppColors.infoInk,
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.underline,
        ),
        recognizer: TapGestureRecognizer()
          ..onTap = () async {
            final uri = Uri.tryParse(linkUrl);
            if (uri == null) return;
            try {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            } catch (_) {
              // No app can open this link; nothing else to do.
            }
          },
      );
    }

    TextStyle style = TextStyle(
      fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
      fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
      decoration: isUnderline ? TextDecoration.underline : TextDecoration.none,
      color: isBold ? primaryTextColor : null,
    );

    if (isCode) {
      style = style.copyWith(
        fontFamily: AppTypography.mono.copyWith().fontFamily,
        fontSize: 13,
        backgroundColor: AppColors.textTertiary.withValues(alpha: 0.15),
      );
    }

    return TextSpan(text: content, style: style);
  }
}
