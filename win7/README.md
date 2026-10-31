# Flutter 3.44.1 Windows 7 compatibility

This branch starts at official Flutter `3.44.1`. Windows 7 compatibility is
experimental and **not yet validated**. The initial baseline builds an
unmodified engine control. The current config builds the first compatibility
candidate; it is not a supported compatibility release.

Scope: Windows 7 SP1 **x64**, release-mode applications. Build on Windows 10/11
with Visual Studio 2022. Windows 7 development tooling, x86, and other platforms
are outside the initial acceptance scope.

`build-config.json` pins Flutter's base, a companion Dart commit and depot_tools.
The Dart checkout is overridden through gclient custom_deps; the rest of the
upstream dependency revisions are retained. GitHub Actions builds the engine
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

The companion Dart source is maintained at
<https://github.com/zibo-chen/dart-sdk-win7-support/tree/medivh/win7-flutter-3.44.1>.
The opt-in GN argument `flutter_win7_compatibility=true` sets PE subsystem 6.1
and supplies native address-wait fallbacks for static MSVC library imports.
The normal engine configuration is unchanged. The standalone native test
exercises fallback timeouts, sizes, eight waiting threads and STL atomic wait.

Unknown build variants fail. Manifests label compatibility as `unverified`
until actual Win7 acceptance. Never relabel a stock engine as a compatible one.

## Recorded control result (2026-10-31)

The stock Flutter 3.44.1 x64 smoke app, built by Actions run `41178761812`,
fails to launch on Windows 7 SP1 x64 / Intel HD Graphics 3000. The process exits
with `0xC0000139` and no first-frame/runtime report. The engine DLL advertises
PE subsystem 10.0 and LoadLibrary reports error 127.

Comparing its named imports with exports available on that machine identified:
`GetHostNameW`, PathCch APIs, growable function tables,
`GetCurrentThreadStackLimits`, `WaitOnAddress`, and `WakeByAddressSingle`.
Ordinal imports were excluded from this comparison. This establishes the
negative control only; source-build and patched-engine results are pending.

The native address-wait executable from run `41180227958` passes on Windows
2022 CI and on the Win7 machine for 10 consecutive runs, all with exit code 0.
This validates that component only; the full Flutter engine remains pending.
See [recorded controls](evidence/2026-10-31-controls.json) for hashes and limits.

## Source build and runtime probe

Run `41180227958` completes all 6611 compilation/link steps for the patched
engine and source-built Dart. Its later relative-link probe fails with errno
123. Official Dart control run `41186016069` reproduces this for `../中文` and
passes for the native Windows target `..\中文`; the test fixture is corrected.

The build now saves `output/local-engine/host_release` before acceptance probes,
including the matched Dart SDK, patched platform SDK, compiler, headers and
wrapper. Artifacts are retained even if a later check fails, and carry
`compiled_not_accepted` metadata. Runtime acceptance remains mandatory.

Before compiling, the pipeline runs the same probe with official Dart and
checks the native concurrency helper. The upstream Flutter tag is fetched and
verified so the fork CLI can derive a valid semantic version.
