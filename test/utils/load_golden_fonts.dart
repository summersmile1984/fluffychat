import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The font family name used in golden tests.
///
/// All golden test widgets should use this as their fontFamily
/// so that real text is rendered instead of Ahem blocks.
const kGoldenFontFamily = 'GoldenFont';

/// Load real fonts for golden tests so text renders correctly
/// instead of the default Ahem font (which shows all glyphs as blocks).
///
/// Loads Arial Unicode from macOS system fonts, which covers
/// both Latin and CJK (Chinese/Japanese/Korean) characters.
///
/// Call this in `setUpAll()` before any golden test.
Future<void> loadGoldenFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Arial Unicode covers Latin + CJK in a single font file
  const arialUnicode = '/System/Library/Fonts/Supplemental/Arial Unicode.ttf';

  final file = File(arialUnicode);
  if (file.existsSync()) {
    final data = file.readAsBytesSync();
    final loader = FontLoader(kGoldenFontFamily)
      ..addFont(Future.value(ByteData.sublistView(data)));
    await loader.load();
  } else {
    // Fallback: try Roboto from Flutter SDK for Latin-only
    final robotoPath = _findRoboto();
    if (robotoPath != null) {
      final data = File(robotoPath).readAsBytesSync();
      final loader = FontLoader(kGoldenFontFamily)
        ..addFont(Future.value(ByteData.sublistView(data)));
      await loader.load();
    }
  }
}

/// Find Roboto-Regular.ttf in Flutter SDK cache.
String? _findRoboto() {
  final home = Platform.environment['HOME'] ?? '';
  final candidates = [
    '$home/flutter/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
    '/Users/macstudio/flutter/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
  ];
  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }
  return null;
}
