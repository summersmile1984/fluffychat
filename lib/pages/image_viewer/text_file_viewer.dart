import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:highlight/highlight.dart' show highlight;
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/code_highlight_theme.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/event_extension.dart';

class TextFileViewer extends StatelessWidget {
  final Event event;
  final BuildContext outerContext;

  const TextFileViewer(
    this.event, {
    required this.outerContext,
    super.key,
  });

  /// Map file extension to highlight.js language identifier.
  static String _languageFromFilename(String filename) {
    final ext = filename.contains('.')
        ? filename.split('.').last.toLowerCase()
        : '';
    return switch (ext) {
      'js' || 'mjs' || 'cjs' => 'javascript',
      'ts' || 'mts' || 'tsx' => 'typescript',
      'py' => 'python',
      'rb' => 'ruby',
      'rs' => 'rust',
      'go' => 'go',
      'java' => 'java',
      'c' || 'h' => 'c',
      'cpp' || 'cc' || 'cxx' || 'hpp' => 'cpp',
      'cs' => 'csharp',
      'dart' => 'dart',
      'swift' => 'swift',
      'kt' || 'kts' => 'kotlin',
      'php' => 'php',
      'sh' || 'bash' || 'zsh' => 'bash',
      'bat' || 'cmd' => 'dos',
      'sql' => 'sql',
      'html' || 'htm' => 'xml',
      'xml' || 'svg' || 'xsl' => 'xml',
      'css' || 'scss' || 'sass' => 'css',
      'json' => 'json',
      'yaml' || 'yml' => 'yaml',
      'toml' => 'ini',
      'ini' || 'cfg' || 'conf' => 'ini',
      'md' || 'markdown' => 'markdown',
      'r' => 'r',
      'lua' => 'lua',
      'perl' || 'pl' => 'perl',
      'dockerfile' => 'dockerfile',
      'makefile' => 'makefile',
      'csv' || 'tsv' => 'plaintext',
      'log' || 'txt' || 'text' => 'plaintext',
      'env' || 'properties' => 'properties',
      _ => 'plaintext',
    };
  }

  InlineSpan _renderCodeNode(dom.Node node) {
    if (node is! dom.Element) {
      return TextSpan(text: node.text);
    }
    final style =
        atomOneDarkTheme[node.className.split('-').last] ??
        atomOneDarkTheme['root'];
    return TextSpan(
      children: node.nodes.map(_renderCodeNode).toList(),
      style: style,
    );
  }

  @override
  Widget build(BuildContext context) {
    final filename = event.content.tryGet<String>('filename') ?? event.body;
    return Scaffold(
      appBar: AppBar(
        title: Text(filename),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () => event.shareFile(context),
            tooltip: L10n.of(context).share,
          ),
          IconButton(
            icon: const Icon(Icons.download_outlined),
            onPressed: () => event.saveFile(context),
            tooltip: L10n.of(context).downloadFile,
          ),
        ],
      ),
      body: FutureBuilder<MatrixFile>(
        future: event.downloadAndDecryptAttachment(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                L10n.of(context).oopsSomethingWentWrong,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }

          final text = utf8.decode(
            snapshot.data!.bytes,
            allowMalformed: true,
          );
          final lang = _languageFromFilename(filename);

          // Attempt syntax highlighting
          Widget content;
          try {
            final highlighted = highlight.parse(text, language: lang).toHtml();
            final element = parser.parse(highlighted).body;
            if (element != null) {
              content = SelectableText.rich(
                TextSpan(
                  children: [_renderCodeNode(element)],
                  style: atomOneDarkTheme['root'],
                ),
              );
            } else {
              content = SelectableText(
                text,
                style: atomOneDarkTheme['root'],
              );
            }
          } catch (_) {
            content = SelectableText(
              text,
              style: atomOneDarkTheme['root'],
            );
          }

          return Container(
            color: atomOneBackgroundColor,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              scrollDirection: Axis.vertical,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: content,
              ),
            ),
          );
        },
      ),
    );
  }
}
