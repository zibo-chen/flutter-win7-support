import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  if (!Platform.isWindows) throw StateError('Windows control required');
  final root = await Directory.systemTemp.createTemp('dart-link-control-');
  final results = <String, Object?>{};
  try {
    final target = await Directory('${root.path}/中文').create();
    await File('${target.path}/probe.txt').writeAsString('link-control-ok');
    for (final entry in {'forward_slash': '../中文', 'backslash': '..\\中文'}.entries) {
      final child = await Directory('${root.path}/${entry.key}').create();
      try {
        final link = await Link('${child.path}/relative').create(entry.value);
        final result = await File('${link.path}/probe.txt').readAsString();
        results[entry.key] = {'passed': result == 'link-control-ok', 'target': await link.target()};
      } catch (error) {
        results[entry.key] = {'passed': false, 'error': '$error'};
      }
    }
    stdout.writeln(jsonEncode({'dart': Platform.version, 'results': results}));
    if ((results['backslash']! as Map)['passed'] != true) {
      throw StateError('Native Windows separator control failed');
    }
  } finally {
    await root.delete(recursive: true);
  }
}
