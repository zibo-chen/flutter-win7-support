# Flutter 3.44.1 Windows 7 compatibility

This branch starts at official Flutter **3.44.1**, with the matched Dart
3.12.1 runtime/compiler built from source. A release-mode minimal application
has passed first-frame, runtime and keyboard/button acceptance on one Windows 7
SP1 x64 machine. This remains an experimental fork, not a general compatibility
release or business-app acceptance.

[中文使用说明](USAGE.zh-CN.md)

## Verified result

On Windows 7 Ultimate SP1 x64 / Intel HD Graphics 3000:

- The compatibility engine loads with PE subsystem 6.1.
- The real application renders its first frame and Chinese UI text.
- Hostname, Unicode file I/O, loopback HTTP/socket, isolate exception stacks,
  and native FFI probes pass.
- Keyboard text `Win7-input-123` appears and the button count changes from 0 to 1.
- The application closes normally with exit code 0. A second launch with the
  UTF-8 report reader also passes all runtime checks and closes normally.

[Runtime and visual evidence](evidence/2026-10-31-win7/acceptance.json),
[before input](evidence/2026-10-31-win7/before-input.png),
[after input](evidence/2026-10-31-win7/after-input.png).

The exact app is from [package run 41196428941](https://github.com/zibo-chen/flutter-win7-support/actions/runs/41196428941),
artifact `13040743327`. Its archive SHA-256 is
`88cbe9b960ccbee56c08c3a63de3ab91af92969723ba5e95eda8dce577d27830`.
The engine is from source run `41186401142`, commit
`7cb7b91d25a4376334ce186fbbc58bd92d4c743d`; the companion Dart revision is
`a6ed413da4b5690ec3e05f347af1400170d2a2f3`.

The unmodified Flutter 3.44.1 control fails on the same Win7 machine with
`0xC0000139`, no first frame and loader error 127. The native address-wait
component separately passes ten consecutive Win7 runs and Windows CI.
See [control records](evidence/2026-10-31-controls.json).

The same packaged app also passes first-frame/runtime checks and normal exit
on Windows Server 2022 in [runtime run 41197415312](https://github.com/zibo-chen/flutter-win7-support/actions/runs/41197415312).
See its [runtime report](evidence/2026-10-31-win7/modern-runtime.json).

## Source and build

`build-config.json` pins Flutter's base, the companion Dart commit and
`depot_tools`. gclient custom_deps selects the Dart fork while retaining the
other upstream dependency revisions. Source changes live on
`medivh/win7-3.44.1`; the default branch remains an upstream reference.

The companion Dart source is maintained at
<https://github.com/zibo-chen/dart-sdk-win7-support/tree/medivh/win7-flutter-3.44.1>.
It resolves newer Windows hostname, stack, unwind-table and PathCch APIs at
runtime and provides Win7 fallbacks. The opt-in GN argument
`flutter_win7_compatibility=true` sets PE subsystem 6.1 and provides native
address-wait fallbacks for static MSVC imports, including direct and import
pointer calls. Normal engine configuration is unchanged.

GitHub Actions builds on Windows 2022 / Visual Studio 2022 and preserves the
matched local-engine SDK before acceptance probes. Unknown build variants fail.
The saved manifest says `compiled_not_accepted`; acceptance evidence is recorded
separately for an exact artifact and machine. The official-Dart runtime probe,
native concurrency helper and stock smoke tests gate source compilation.

Source builds trigger on engine-source/config changes; `win7/ci-trigger.txt`
can request another. `win7-package.yml` reuses a saved SDK after validating its
source run/manifest. `package-request.json` chooses that run and full source
commit. The builder uses a short external app directory and static C++ runtime
for the minimal runner. New SDK archives include shader headers and optional
export/debug metadata. Older SDKs may recover shader headers only if their Git
tree matches the recorded source commit. Local-engine unpacking permits missing
`.exp`/`.pdb`; DLL/import-library inputs and downloaded SDK validation remain
strict, covered by targeted Flutter tools tests.

`win7-runtime.yml` runs the exact accepted app on a newer Windows CI host,
validates file hashes and records a first-frame/runtime report. That CI host is
Windows Server 2022; it does not replace physical Windows 10/11 acceptance.

## Acceptance limits

The legacy touch path registers the Flutter child view for Win7 `WM_TOUCH`
when `GetPointerInfo` is absent. It forwards down/move/up contacts with physical
coordinates and stable IDs, closes each consumed touch handle, and suppresses
duplicate promoted mouse events. If registration fails, promoted mouse input
remains available for basic taps. Windows 8+ retains `WM_POINTER`. Native
regression tests cover routing, multiple contacts, negative/fractional
coordinates, registration failure and handle ownership. On the Win7 device,
real finger input reached the native helper, and a bakery release app using the
rebuilt engine responded to finger taps and scrolling (user-confirmed). This
validates basic touch input; it does not establish business workflow or
long-running stability acceptance. See `evidence/2026-11-01-touch.json`.

The initial scope is Win7 SP1 **x64 release applications** built on newer
Windows. Win7 development tools and x86 are outside this scope. Chinese IME
composition, advanced touchpad gestures, long-running stability, physical
Windows 10/11, arbitrary plugins and camera/recognition/printer integration
remain separate acceptance work. Win7 logs that the DirectManipulation COM
manager is unavailable; the verified keyboard/button interaction still works.

Set `MEDIVH_WIN7_REPORT` to an absolute JSON path to record the first frame and
runtime probes. `test-app.ps1` uses an existing interactive session, captures
only the app window, sends input only while it is foreground, closes its own
process and removes its temporary task. Screenshots require visual inspection;
a PNG file or `input_attempted` flag alone is not proof of interaction.
