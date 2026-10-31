[CmdletBinding()]
param([int]$Jobs = 3)
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
$vswhere = "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
$vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$vs) { throw 'Visual Studio C++ toolchain not found' }
$env:GYP_MSVS_OVERRIDE_PATH = $vs
$env:GYP_MSVS_VERSION = '2022'
$env:WINDOWSSDKDIR = "${env:ProgramFiles(x86)}/Windows Kits/10"
Get-PSDrive -PSProvider FileSystem | Select-Object Name,Used,Free | Format-Table

$depot = 'C:/win7-depot-tools'
if (!(Test-Path "$depot/.git")) {
  Checked git @('init', $depot)
  Checked git @('-C', $depot, 'remote', 'add', 'origin', 'https://chromium.googlesource.com/chromium/tools/depot_tools.git')
}
Checked git @('-C', $depot, 'fetch', '--depth=1', 'origin', $config.depot_tools_revision)
Checked git @('-C', $depot, 'checkout', '--detach', 'FETCH_HEAD')
$env:PATH = "$depot;$env:PATH"
Set-Location $root
Copy-Item 'engine/scripts/standard.gclient' '.gclient'
# gclient sync must leave our pinned Flutter checkout untouched.
Checked 'gclient.bat' @('sync', '--no-history', '--shallow', '--jobs', '4')
$dart = "$root/engine/src/flutter/third_party/dart"
$dartRevision = (& git -C $dart rev-parse HEAD).Trim()
if ($dartRevision -ne $config.dart_revision) { throw "Unexpected Dart revision $dartRevision" }
if ($config.variant -ne 'baseline') {
  throw 'Patched builds require a pinned compatibility patch set; no silent baseline fallback.'
}

Set-Location "$root/engine/src"
Checked python @('flutter/tools/gn', '--runtime-mode=release', '--no-prebuilt-dart-sdk', '--no-lto', '--no-enable-unittests', '--no-build-embedder-examples', '--no-build-glfw-shell')
# Build the desktop SDK and compiler, excluding unrelated engine test/tool targets.
Checked ninja @('-C', 'out/host_release', '-j', "$Jobs", 'flutter/shell/platform/windows:windows', 'flutter/lib/snapshot:generate_snapshot_bins', 'flutter/build/dart:dart_sdk', 'flutter/flutter_frontend_server:frontend_server')
$out = "$root/engine/src/out/host_release"
foreach ($required in @('flutter_windows.dll', 'flutter_windows.dll.lib', 'flutter_windows.h', 'gen_snapshot.exe', 'icudtl.dat')) {
  if (!(Test-Path "$out/$required")) { throw "Missing engine output: $required" }
}

Set-Location $root
Checked "$root/bin/flutter.bat" @('config', '--no-analytics')
Checked "$root/bin/flutter.bat" @('--version')
Checked "$root/bin/flutter.bat" @('create', '--empty', '--platforms=windows', '--project-name=win7_smoke', '--no-pub', 'win7/smoke')
Set-Location "$root/win7/smoke"
Checked "$root/bin/flutter.bat" @('pub', 'get')
Checked "$root/bin/flutter.bat" @('--local-engine-src-path', "$root/engine/src", '--local-engine', 'host_release', '--local-engine-host', 'host_release', 'build', 'windows', '--release')
$bundle = "$root/win7/output/$($config.variant)-smoke"
Copy-Item 'build/windows/x64/runner/Release' $bundle -Recurse
$manifest = [ordered]@{
  variant = $config.variant
  flutter_version = $config.flutter_version
  flutter_commit = (& git -C $root rev-parse HEAD).Trim()
  dart_commit = $dartRevision
  depot_tools_commit = $config.depot_tools_revision
  target = $config.target
  compatibility_status = 'unverified'
  build_utc = [DateTime]::UtcNow.ToString('o')
}
$manifest | ConvertTo-Json | Set-Content "$bundle/build-manifest.json" -Encoding utf8
Get-ChildItem $bundle -Recurse -File | Get-FileHash -Algorithm SHA256 | Select-Object Path,Hash | ConvertTo-Json | Set-Content "$bundle/SHA256SUMS.json" -Encoding utf8
Copy-Item "$root/engine/src/out/host_release/args.gn" "$root/win7/output/args.gn"
$engineBundle = "$root/win7/output/$($config.variant)-engine"
New-Item -ItemType Directory -Force $engineBundle | Out-Null
foreach ($pattern in @('flutter_windows.*', 'flutter_export.h', 'flutter_messenger.h', 'flutter_plugin_registrar.h', 'flutter_texture_registrar.h', 'gen_snapshot.exe', 'icudtl.dat', 'license*.md')) {
  Get-ChildItem "$out/$pattern" -File | Copy-Item -Destination $engineBundle
}
Copy-Item "$bundle/build-manifest.json" $engineBundle
