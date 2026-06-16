import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release Dart copy does not contain demo/prototype language', () {
    final banned = <String, RegExp>{
      'demo': RegExp(r'\bdemo\b', caseSensitive: false),
      'prototype': RegExp(r'\bprototype\b', caseSensitive: false),
      'fake': RegExp(r'\bfake\b', caseSensitive: false),
      'lorem': RegExp(r'\blorem\b', caseSensitive: false),
      'no-op': RegExp(r'\bno[- ]op\b', caseSensitive: false),
      'Aryan seed data': RegExp(r'\bAryan\b', caseSensitive: false),
    };
    final failures = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index];
        if (_isCommentOnly(line)) {
          continue;
        }
        for (final entry in banned.entries) {
          if (entry.value.hasMatch(line)) {
            failures.add('${file.path}:${index + 1}: ${entry.key}');
          }
        }
      }
    }

    expect(
      failures,
      isEmpty,
      reason: 'Release-copy banned words found:\n${failures.join('\n')}',
    );
  });
}

bool _isCommentOnly(String line) {
  final trimmed = line.trimLeft();
  return trimmed.startsWith('//') ||
      trimmed.startsWith('///') ||
      trimmed.startsWith('*') ||
      trimmed.startsWith('/*');
}
