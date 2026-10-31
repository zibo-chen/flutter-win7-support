[CmdletBinding()]
param([int]$Jobs = 4)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$root = Split-Path $PSScriptRoot -Parent
$config = Get-Content "$PSScriptRoot/build-config.json" -Raw | ConvertFrom-Json
$env:DEPOT_TOOLS_WIN_TOOLCHAIN = '0'
$env:DEPOT_TOOLS_UPDATE = '0'
$env:PYTHONUTF8 = '1'
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$env:CI = 'true'

function Checked([string]$Program, [string[]]$Arguments) {
  Write-Host "> $Program $($Arguments -join ' ')"
  & $Program @Arguments
  if ($LASTEXITCODE -ne 0) { throw "$Program exited $LASTEXITCODE" }
}

New-Item -ItemType Directory -Force "$root/win7/output" | Out-Null
# The Flutter CLI derives its semantic version from tags even on a fork.
# Fetch and verify the real upstream tag, rather than reporting an unknown SDK.
Checked git @('-C', $root, 'fetch', '--depth=1', 'https://github.com/flutter/flutter.git', "refs/tags/$($config.flutter_version):refs/tags/$($config.flutter_version)")
$baseRevision = (& git -C $root rev-parse "refs/tags/$($config.flutter_version)^{commit}").Trim()
if ($baseRevision -ne $config.flutter_base_revision) { throw "Unexpected Flutter base $baseRevision" }
$vswhere = "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
$vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$vs) { throw 'Visual Studio C++ toolchain not found' }
$env:GYP_MSVS_OVERRIDE_PATH = $vs
$env:GYP_MSVS_VERSION = '2022'
$env:WINDOWSSDKDIR = "${env:ProgramFiles(x86)}/Windows Kits/10"
Get-PSDrive -PSProvider FileSystem | Select-Object Name,Used,Free | Format-Table

$depot = 'C:/win7-depot-tools'
$gitExe = (Get-Command git.exe).Source
if (!(Test-Path "$depot/.git")) {
  Checked git @('init', $depot)
  Checked git @('-C', $depot, 'remote', 'add', 'origin', 'https://chromium.googlesource.com/chromium/tools/depot_tools.git')
}
Checked git @('-C', $depot, 'fetch', '--depth=1', 'origin', $config.depot_tools_revision)
Checked git @('-C', $depot, 'checkout', '--detach', 'FETCH_HEAD')
# This pinned depot_tools calls git.bat. With self-update disabled its Git
# bootstrap does not create that wrapper, so explicitly use the runner's Git.
if (!(Test-Path "$depot/git.bat")) {
  [IO.File]::WriteAllText("$depot/git.bat", "@`"$gitExe`" %*`r`n", [Text.Encoding]::ASCII)
}
$env:PATH = "$depot;$env:PATH"
Set-Location $root
Copy-Item 'engine/scripts/standard.gclient' '.gclient'
if ($config.variant -eq 'win7-experimental') {
  $gclient = Get-Content '.gclient' -Raw
  $dependency = '"custom_deps": {"engine/src/flutter/third_party/dart": "' + $config.dart_repository + '@' + $config.dart_revision + '"}'
  $gclient.Replace('"custom_deps": {}', $dependency) | Set-Content '.gclient' -Encoding utf8
} elseif ($config.variant -ne 'baseline') {
  throw "Unknown build variant: $($config.variant)"
}
# gclient sync must leave our pinned Flutter checkout untouched.
Checked 'gclient.bat' @('sync', '--no-history', '--shallow', '--jobs', '4')
$dart = "$root/engine/src/flutter/third_party/dart"
$dartRevision = (& git -C $dart rev-parse HEAD).Trim()
if ($dartRevision -ne $config.dart_revision) { throw "Unexpected Dart revision $dartRevision" }

Set-Location "$root/engine/src"
$gnArguments = @('flutter/tools/gn', '--runtime-mode=release', '--no-prebuilt-dart-sdk', '--no-lto', '--no-enable-unittests', '--no-build-embedder-examples', '--no-build-glfw-shell')
if ($config.variant -eq 'win7-experimental') {
  $gnArguments += '--gn-args=flutter_win7_compatibility=true'
}
Checked python $gnArguments
# Build the desktop SDK and compiler, excluding unrelated engine test/tool targets.
Checked ninja @('-C', 'out/host_release', '-j', "$Jobs", 'flutter/shell/platform/windows:windows', 'flutter/lib/snapshot:generate_snapshot_bins', 'flutter/build/dart:dart_sdk', 'flutter/flutter_frontend_server:frontend_server', 'flutter/tools/font_subset', 'flutter/tools/const_finder')
$out = "$root/engine/src/out/host_release"
foreach ($required in @('flutter_windows.dll', 'flutter_windows.dll.lib', 'flutter_windows.h', 'gen_snapshot.exe', 'icudtl.dat')) {
  if (!(Test-Path "$out/$required")) { throw "Missing engine output: $required" }
}
# Preserve the matched local engine SDK before runtime or application probes.
# A failed acceptance test must not discard an hour of successful compilation.
$sdkStage = "$root/win7/output/local-engine/host_release"
New-Item -ItemType Directory -Force $sdkStage | Out-Null
foreach ($directory in @('dart-sdk', 'flutter_patched_sdk', 'flutter_patched_sdk_product', 'cpp_client_wrapper', 'shader_lib', 'gen')) {
  if (Test-Path "$out/$directory") {
    Copy-Item "$out/$directory" $sdkStage -Recurse
  }
}
foreach ($pattern in @('*.exe', '*.snapshot', '*.dll', '*.dll.lib', '*.dll.exp', '*.dll.pdb', '*.h', '*.dat', 'license*.md', 'args.gn')) {
  Get-ChildItem "$out/$pattern" -File | Copy-Item -Destination $sdkStage
}
$engineManifest = [ordered]@{
  variant = $config.variant
  flutter_version = $config.flutter_version
  flutter_base_commit = $config.flutter_base_revision
  engine_source_commit = (& git -C $root rev-parse HEAD).Trim()
  dart_commit = $dartRevision
  dart_base_commit = $config.dart_base_revision
  depot_tools_commit = $config.depot_tools_revision
  target = $config.target
  stage = 'compiled_not_accepted'
}
$engineManifest | ConvertTo-Json | Set-Content "$sdkStage/build-manifest.json" -Encoding utf8
Copy-Item "$root/LICENSE" "$sdkStage/FLUTTER_LICENSE"
if (Test-Path "$dart/tests/standalone/io/windows_7_compatibility_test.dart") {
  Copy-Item "$dart/tests/standalone/io/windows_7_compatibility_test.dart" "$sdkStage/runtime-probe.dart"
}
Copy-Item "$sdkStage/build-manifest.json" $out
if (Test-Path "$sdkStage/runtime-probe.dart") { Copy-Item "$sdkStage/runtime-probe.dart" $out }
$bundle = "$root/win7/output/$($config.variant)-smoke"
& "$PSScriptRoot/build-smoke.ps1" -FlutterRoot $root -EngineOut $out -OutputDirectory $bundle
Copy-Item "$root/engine/src/out/host_release/args.gn" "$root/win7/output/args.gn"
$engineBundle = "$root/win7/output/$($config.variant)-engine"
New-Item -ItemType Directory -Force $engineBundle | Out-Null
foreach ($pattern in @('flutter_windows.*', 'flutter_export.h', 'flutter_messenger.h', 'flutter_plugin_registrar.h', 'flutter_texture_registrar.h', 'gen_snapshot.exe', 'icudtl.dat', 'license*.md')) {
  Get-ChildItem "$out/$pattern" -File | Copy-Item -Destination $engineBundle
}
Copy-Item "$bundle/build-manifest.json" $engineBundle
