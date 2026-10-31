import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win7_smoke/main.dart';

void main() {
  testWidgets('shows runtime failures as failures', (tester) async {
    await tester.pumpWidget(
      const SmokeApp(
        report: {
          'passed': false,
          'checks': {
            'isolate': {'status': 'failed', 'detail': 'probe failure'},
          },
        },
      ),
    );
    expect(find.text('FAIL'), findsOneWidget);
    expect(find.textContaining('probe failure'), findsOneWidget);
  });

  testWidgets('renders a successful result and Chinese text', (tester) async {
    await tester.pumpWidget(
      const SmokeApp(
        report: {
          'passed': true,
          'checks': {
            'filesystem': {'status': 'passed', 'detail': '中文读写通过'},
          },
        },
      ),
    );
    expect(find.text('PASS'), findsOneWidget);
    expect(find.textContaining('中文读写通过'), findsOneWidget);
  });

  test('runtime probes complete and clean up their temporary files', () async {
    final temp = Directory.systemTemp.createTempSync('win7-smoke-test-');
    try {
      final report = await HttpOverrides.runWithHttpOverrides(
        () => runRuntimeChecks(workingDirectory: temp),
        _RealHttpOverrides(),
      );
      expect(report['passed'], isTrue);
      final checks = report['checks']! as Map<String, Object?>;
      expect(
        checks.keys,
        containsAll([
          'hostname',
          'filesystem',
          'loopback_http',
          'isolate_unwind',
          'ffi',
        ]),
      );
      expect(temp.listSync(), isEmpty);
      final ffi = checks['ffi']! as Map<String, Object?>;
      expect(ffi['status'], Platform.isWindows ? 'passed' : 'skipped');
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

  testWidgets('button and text entry remain interactive', (tester) async {
    await tester.pumpWidget(const SmokeApp());
    await tester.tap(find.text('点击测试 / Clicks: 0'));
    await tester.pump();
    expect(find.text('点击测试 / Clicks: 1'), findsOneWidget);
    await tester.enterText(find.byType(EditableText), 'Win7 中文');
    expect(find.text('Win7 中文'), findsOneWidget);
  });

  test('a failed filesystem probe does not hide the other results', () async {
    final report = await HttpOverrides.runWithHttpOverrides(
      () => runRuntimeChecks(
        workingDirectory: Directory('/nonexistent/win7-smoke-test'),
      ),
      _RealHttpOverrides(),
    );
    expect(report['passed'], isFalse);
    final checks = report['checks']! as Map<String, Object?>;
    expect((checks['filesystem']! as Map)['status'], 'failed');
    expect((checks['loopback_http']! as Map)['status'], 'passed');
  });
}

class _RealHttpOverrides extends HttpOverrides {}
