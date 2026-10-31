# Flutter 3.44.1 Windows 7 compatibility

This branch starts at official Flutter `3.44.1`. Windows 7 compatibility is
experimental and **not yet validated**. The initial build is an unmodified
engine control, not a compatibility release.

Scope: Windows 7 SP1 **x64**, release-mode applications. Build on Windows 10/11
with Visual Studio 2022. Windows 7 development tooling, x86, and other platforms
are outside the initial acceptance scope.

`build-config.json` pins Dart and depot_tools. GitHub Actions builds the engine
and Dart from source and creates a smoke app using that same engine. The stock
Flutter artifact is an independent negative control. Source changes are kept on
`medivh/win7-3.44.1`; the fork's default branch remains an upstream reference.

## Initial acceptance

1. Build the original engine and smoke app on Windows 2022 CI.
2. Record stock and source-build behavior on Win7.
3. Add independently reviewable compatibility changes to Flutter and Dart.
4. Verify window rendering, input, Unicode file I/O, hostname, socket/HTTP,
   isolates/exceptions, and native FFI on Win7, then regress Win10/11.
5. Integrate Medivh native libraries and real camera/recognition paths separately.

Set `MEDIVH_WIN7_REPORT` to an absolute JSON output path before launching
`win7_smoke.exe`. A report is written only after a first-frame callback and the
runtime probes complete. The window remains open for visual/input acceptance.
The report does not prove keyboard/IME, printer, camera, or recognition acceptance.

The baseline config deliberately fails if changed to a patched variant without
implementing its pinned Dart patch checkout. Never relabel a stock engine as a
Win7-compatible build.
