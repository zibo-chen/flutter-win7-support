import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';

typedef _Uint32Native = Uint32 Function();
typedef _Uint32Dart = int Function();

Future<Map<String, Object?>> runRuntimeChecks({
  Directory? workingDirectory,
}) async {
  final checks = <String, Object?>{};
  Future<void> check(String name, FutureOr<Object?> Function() probe) async {
    try {
      final detail = await Future<Object?>.sync(
        probe,
      ).timeout(const Duration(seconds: 10));
      checks[name] = {'status': 'passed', 'detail': detail};
    } catch (error, stack) {
      checks[name] = {
        'status': 'failed',
        'detail': '$error',
        'stack': '$stack',
      };
    }
  }

  await check('hostname', () {
    final hostname = Platform.localHostname;
    if (hostname.isEmpty) throw StateError('Empty hostname');
    return hostname;
  });
  await check('filesystem', () async {
    final parent = workingDirectory ?? Directory.systemTemp;
    final temp = await parent.createTemp('flutter-win7-');
    try {
      final file = File('${temp.path}${Platform.pathSeparator}中文-烘培.txt');
      const content = '烘培、小碗菜、商超 UTF-8';
      await file.writeAsString(content, flush: true);
      if (await file.readAsString() != content)
        throw StateError('File content mismatch');
      return '中文读写通过';
    } finally {
      await temp.delete(recursive: true);
    }
  });
  await check('loopback_http', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    server.listen((request) {
      request.response.write('win7-network-ok');
      unawaited(request.response.close());
    });
    try {
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/'),
      );
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      if (body != 'win7-network-ok') throw StateError('HTTP body mismatch');
      return 'HTTP/socket/event loop passed';
    } finally {
      client.close(force: true);
      await server.close(force: true);
    }
  });
  await check('isolate_unwind', () async {
    final result = await Isolate.run(() {
      try {
        throw StateError('win7-unwind-probe');
      } catch (error, stack) {
        return '$error'.contains('win7-unwind-probe') && '$stack'.isNotEmpty;
      }
    });
    if (!result) throw StateError('Isolate exception/stack failed');
    return 'isolate/exception/stack passed';
  });
  if (Platform.isWindows) {
    await check('ffi', () {
      final kernel = DynamicLibrary.open('kernel32.dll');
      final getPid = kernel.lookupFunction<_Uint32Native, _Uint32Dart>(
        'GetCurrentProcessId',
      );
      final getTicks = kernel.lookupFunction<_Uint32Native, _Uint32Dart>(
        'GetTickCount',
      );
      if (getPid() != pid) throw StateError('FFI process ID mismatch');
      return {'pid': getPid(), 'ticks': getTicks()};
    });
  } else {
    checks['ffi'] = {'status': 'skipped', 'detail': 'Windows-only probe'};
  }
  return {
    'passed': checks.values.every(
      (entry) => (entry! as Map)['status'] != 'failed',
    ),
    'checks': checks,
    'os': Platform.operatingSystemVersion,
    'dart': Platform.version,
  };
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final firstFrame = Completer<void>();
  WidgetsBinding.instance.addPostFrameCallback((_) => firstFrame.complete());
  runApp(const SmokeApp());
  await firstFrame.future;
  final report = await runRuntimeChecks();
  report['first_frame'] = true;
  report['completed_utc'] = DateTime.now().toUtc().toIso8601String();
  final destination = Platform.environment['MEDIVH_WIN7_REPORT'];
  if (destination != null && destination.isNotEmpty) {
    await File(destination).writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
      flush: true,
    );
  }
  runApp(SmokeApp(report: report));
}

class SmokeApp extends StatelessWidget {
  const SmokeApp({super.key, this.report});
  final Map<String, Object?>? report;

  @override
  Widget build(BuildContext context) {
    final passed = report?['passed'] == true;
    final checks = report?['checks'] as Map<String, Object?>? ?? {};
    return MaterialApp(
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: Scaffold(
        appBar: AppBar(title: const Text('Flutter 3.44.1 / Windows 7 x64')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: ListView(
            children: [
              Text(
                report == null ? 'RUNNING' : (passed ? 'PASS' : 'FAIL'),
                style: TextStyle(
                  fontSize: 48,
                  color: passed ? Colors.green : Colors.orange,
                ),
              ),
              const Text('烘培 · 小碗菜 · 商超', style: TextStyle(fontSize: 24)),
              const SizedBox(height: 16),
              for (final entry in checks.entries)
                Text(
                  '${entry.key}: ${entry.value}',
                  style: const TextStyle(fontSize: 16),
                ),
              const SizedBox(height: 20),
              const TextField(
                decoration: InputDecoration(labelText: '键盘与中文输入测试'),
              ),
              const SizedBox(height: 12),
              const _Counter(),
            ],
          ),
        ),
      ),
    );
  }
}

class _Counter extends StatefulWidget {
  const _Counter();
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int count = 0;
  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: () => setState(() => count++),
    child: Text('点击测试 / Clicks: $count'),
  );
}
