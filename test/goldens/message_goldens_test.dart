import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/a2ui/widgets/a2ui_message_bubble.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/chat/events/streaming_message_content.dart';
import '../utils/fake_event_factory.dart';
import '../utils/load_golden_fonts.dart';

/// Golden tests for message rendering.
///
/// These tests capture screenshots of different message types
/// and compare them against reference images to detect visual regressions.
///
/// First run: `flutter test --update-goldens test/goldens/`
/// Subsequent runs: `flutter test test/goldens/`
void main() {
  late FakeEventFactory factory;

  setUpAll(() async {
    // Load real fonts (Arial Unicode for Latin+CJK) instead of Ahem blocks
    await loadGoldenFonts();

    // AppSettings.store requires SharedPreferences to be initialized
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);

    factory = FakeEventFactory();
    await factory.init();
  });

  tearDownAll(() => factory.dispose());

  /// Build a ThemeData that uses our golden font for all text.
  ThemeData goldenTheme({Brightness brightness = Brightness.light}) {
    final base = brightness == Brightness.light
        ? ThemeData.light()
        : ThemeData.dark();
    return base.copyWith(
      textTheme: base.textTheme.apply(fontFamily: kGoldenFontFamily),
      primaryTextTheme:
          base.primaryTextTheme.apply(fontFamily: kGoldenFontFamily),
    );
  }

  // ── Markdown Goldens ──

  Widget buildMarkdownGolden(
    String body, {
    Brightness brightness = Brightness.light,
    double width = 400,
  }) {
    final isDark = brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final bgColor = isDark ? const Color(0xFF1A1A2E) : Colors.white;

    const ff = kGoldenFontFamily;

    return MaterialApp(
      theme: goldenTheme(brightness: brightness),
      home: Scaffold(
        backgroundColor: bgColor,
        body: SizedBox(
          width: width,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: MarkdownBody(
              data: body,
              styleSheet: MarkdownStyleSheet(
                p: TextStyle(
                  fontFamily: ff,
                  color: textColor,
                  fontSize: 14,
                ),
                h1: TextStyle(
                  fontFamily: ff,
                  color: textColor,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
                h2: TextStyle(
                  fontFamily: ff,
                  color: textColor,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                h3: TextStyle(
                  fontFamily: ff,
                  color: textColor,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
                code: TextStyle(
                  fontFamily: ff,
                  color: textColor,
                  backgroundColor: textColor.withAlpha(20),
                  fontSize: 13,
                ),
                codeblockDecoration: BoxDecoration(
                  color: textColor.withAlpha(15),
                  borderRadius: BorderRadius.circular(4),
                ),
                a: TextStyle(
                  fontFamily: ff,
                  color: isDark ? Colors.lightBlue : Colors.blue,
                  decoration: TextDecoration.underline,
                ),
                listBullet: TextStyle(
                  fontFamily: ff,
                  color: textColor,
                  fontSize: 14,
                ),
                tableBorder: TableBorder.all(
                  color: textColor.withAlpha(80),
                ),
                tableHead: TextStyle(
                  fontFamily: ff,
                  fontWeight: FontWeight.bold,
                ),
                tableBody: TextStyle(fontFamily: ff),
                blockquote: TextStyle(fontFamily: ff, color: textColor),
              ),
            ),
          ),
        ),
      ),
    );
  }

  const sampleMarkdown = '''## 三种编程语言

| 语言 | 特点 |
|:-----|:-----|
| **Python** | 简洁优雅、生态丰富 |
| **Rust** | 内存安全、零成本抽象 |
| **TypeScript** | 类型安全、前后端通吃 |

### 代码示例

```python
def hello():
    print("Hello, World!")
```

> 编程是一种**艺术**，也是一种*科学*。
''';

  group('Markdown Goldens', () {
    testWidgets('markdown_light_400', (tester) async {
      await tester.pumpWidget(buildMarkdownGolden(sampleMarkdown));
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/markdown_light_400.png'),
      );
    });

    testWidgets('markdown_dark_400', (tester) async {
      await tester.pumpWidget(buildMarkdownGolden(
        sampleMarkdown,
        brightness: Brightness.dark,
      ));
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/markdown_dark_400.png'),
      );
    });

    testWidgets('markdown_light_800', (tester) async {
      await tester.pumpWidget(buildMarkdownGolden(
        sampleMarkdown,
        width: 800,
      ));
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/markdown_light_800.png'),
      );
    });
  });

  // ── Streaming Goldens ──

  group('Streaming Goldens', () {
    testWidgets('streaming_active_light', (tester) async {
      final event = factory.makeStreamingInitialEvent(
        '## 人工智能简介\n\n**人工智能** 是计算机科学的一个重要分支...',
      );
      await tester.pumpWidget(MaterialApp(
        theme: goldenTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: StreamingMessageContent(
              event: event,
              timeline: _FakeTimeline(),
              textColor: Colors.black,
              linkColor: Colors.blue,
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 300));

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/streaming_active_light.png'),
      );
    });

    testWidgets('streaming_done_light', (tester) async {
      final event = factory.makeEvent(content: {
        'msgtype': 'm.text',
        'body':
            '## 人工智能简介\n\n**人工智能** 是计算机科学的一个重要分支，致力于开发能够模拟人类智能的系统。',
        'format': 'org.matrix.custom.markdown',
        'streaming': false,
      });
      await tester.pumpWidget(MaterialApp(
        theme: goldenTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: StreamingMessageContent(
              event: event,
              timeline: _FakeTimeline(),
              textColor: Colors.black,
              linkColor: Colors.blue,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/streaming_done_light.png'),
      );
    });
  });

  // ── A2UI Goldens ──

  group('A2UI Goldens', () {
    testWidgets('a2ui_card_light', (tester) async {
      final event = factory.makeA2uiEvent(
        '测试表单卡片',
        FakeEventFactory.sampleA2uiContent(),
      );
      await tester.pumpWidget(MaterialApp(
        theme: goldenTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: A2uiMessageBubble(
              event: event,
              textColor: Colors.black,
              linkColor: Colors.blue,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/a2ui_card_light.png'),
      );
    });

    testWidgets('a2ui_fallback_light', (tester) async {
      final event = factory.makeA2uiEventFromJsonString(
        'A2UI 解析失败，显示降级文本',
        'invalid json',
      );
      await tester.pumpWidget(MaterialApp(
        theme: goldenTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: A2uiMessageBubble(
              event: event,
              textColor: Colors.black,
              linkColor: Colors.blue,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/a2ui_fallback_light.png'),
      );
    });
  });
}

/// Fake Timeline that satisfies the Timeline type contract.
class _FakeTimeline implements Timeline {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
