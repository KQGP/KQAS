import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:zlib/zlib.dart';

/// Minimal PDF text extractor (best-effort). Extracts text from content streams.
class PdfTextExtractor {
  static Future<String> extract(String path) async {
    final bytes = await File(path).readAsBytes();
    final raw = latin1.decode(bytes, allowInvalid: true);
    final buffer = StringBuffer();

    // Find stream objects
    final streamRegex = RegExp(r'stream\r?\n([\s\S]*?)endstream', multiLine: true);
    for (final m in streamRegex.allMatches(raw)) {
      var data = m.group(1)!;
      // Try flate decode
      Uint8List? decoded;
      try {
        decoded = zlib.decode(data.codeUnits) as Uint8List?;
      } catch (_) {
        try {
          decoded = ZLibDecoder().convert(data.codeUnits) as Uint8List?;
        } catch (_) {
          decoded = null;
        }
      }
      final text = decoded != null ? utf8.decode(decoded, allowMalformed: true) : data;
      // Extract text from Tj / TJ
      final tjRegex = RegExp(r'\(([^)]*)\)\s*Tj', multiLine: true);
      for (final t in tjRegex.allMatches(text)) {
        buffer.write(_unescape(t.group(1)!));
        buffer.write(' ');
      }
      final tjArrayRegex = RegExp(r'\[([^\]]*)\]\s*TJ', multiLine: true);
      for (final t in tjArrayRegex.allMatches(text)) {
        final inner = t.group(1)!;
        final strRegex = RegExp(r'\(([^)]*)\)');
        for (final s in strRegex.allMatches(inner)) {
          buffer.write(_unescape(s.group(1)!));
        }
        buffer.write(' ');
      }
      buffer.write('\n');
    }
    if (buffer.isEmpty) {
      // Fallback: extract any parenthesized strings
      final fallback = RegExp(r'\(([^)]{3,})\)');
      for (final m in fallback.allMatches(raw)) {
        buffer.write(_unescape(m.group(1)!));
        buffer.write(' ');
      }
    }
    return buffer.toString();
  }

  static String _unescape(String s) {
    return s
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\r', '\r')
        .replaceAll(r'\t', '\t')
        .replaceAll(r'\(', '(')
        .replaceAll(r'\)', ')')
        .replaceAll(r'\\', '\\');
  }
}
