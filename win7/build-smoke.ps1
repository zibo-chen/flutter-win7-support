[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$EngineOut,
  [Parameter(Mandatory=$true)][string]$OutputDirectory,
  [string]$FlutterRoot = (Split-Path $PSScriptRoot -Parent)
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$FlutterRoot = [IO.Path]::GetFullPath($FlutterRoot)
$EngineOut = [IO.Path]::GetFullPath($EngineOut)
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$config = Get-Content "$FlutterRoot/win7/build-config.json" -Raw | ConvertFrom-Json
$manifest = Get-Content "$EngineOut/build-manifest.json" -Raw | ConvertFrom-Json
if ($manifest.dart_commit -ne $config.dart_revision -or
    $manifest.flutter_base_commit -ne $config.flutter_base_revision -or
    $manifest.variant -ne $config.variant -or
    $manifest.target -ne $config.target) {
  throw 'Engine manifest does not match the pinned SDK configuration'
}
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'

function Checked([string]$Program, [string[]]$Arguments) {
  Write-Host "> $Program $($Arguments -join ' ')"
  & $Program @Arguments
  if ($LASTEXITCODE -ne 0) { throw "$Program exited $LASTEXITCODE" }
}

Checked git @('-C', $FlutterRoot, 'fetch', '--depth=1', 'https://github.com/flutter/flutter.git', "refs/tags/$($config.flutter_version):refs/tags/$($config.flutter_version)")
$baseRevision = (& git -C $FlutterRoot rev-parse "refs/tags/$($config.flutter_version)^{commit}").Trim()
if ($baseRevision -ne $config.flutter_base_revision) { throw 'Unexpected upstream Flutter tag' }
# Older retained SDKs omitted impellerc's source headers. Recover them only
# when the complete tracked directory is identical to the engine source commit.
if (!(Test-Path "$EngineOut/shader_lib/flutter/runtime_effect.glsl")) {
  $shaderRelative = 'engine/src/flutter/impeller/compiler/shader_lib'
  $sourceTree = (& git -C $FlutterRoot rev-parse "$($manifest.engine_source_commit):$shaderRelative").Trim()
  if ($LASTEXITCODE -ne 0) { throw 'Cannot verify the engine shader headers' }
  $checkoutTree = (& git -C $FlutterRoot rev-parse "HEAD:$shaderRelative").Trim()
  if ($LASTEXITCODE -ne 0 -or $sourceTree -ne $checkoutTree) {
    throw 'Shader headers do not match the compiled engine source'
  }
  Copy-Item "$FlutterRoot/$shaderRelative" "$EngineOut/shader_lib" -Recurse -Force
}
# The raw GN strong_platform target always writes flutter_patched_sdk, with
# dart.vm.product determined by flutter_runtime_mode. Official release archives
# publish that directory as flutter_patched_sdk_product; local artifacts expect
# the published name too. Never alias a debug/profile platform into Release.
if (!(Test-Path "$EngineOut/flutter_patched_sdk_product/platform_strong.dill")) {
  $gnArgs = Get-Content "$EngineOut/args.gn" -Raw
  if ($gnArgs -notmatch 'flutter_runtime_mode\s*=\s*"release"' -or
      !(Test-Path "$EngineOut/flutter_patched_sdk/platform_strong.dill")) {
    throw 'Missing matched Release platform kernel'
  }
  Copy-Item "$EngineOut/flutter_patched_sdk" "$EngineOut/flutter_patched_sdk_product" -Recurse
}
if ($config.variant -eq 'win7-experimental') {
  Checked "$EngineOut/dart-sdk/bin/dart.exe" @("$EngineOut/runtime-probe.dart")
}

# Flutter refuses to create applications anywhere inside its SDK checkout.
# Keep the source fixture in Git and create a disposable, short external path.
$volume = [IO.Path]::GetPathRoot($FlutterRoot)
$app = Join-Path $volume ('win7-smoke-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
Copy-Item "$FlutterRoot/win7/smoke" $app -Recurse
Checked "$FlutterRoot/bin/flutter.bat" @('config', '--no-analytics')
Checked "$FlutterRoot/bin/flutter.bat" @('--version')
Checked "$FlutterRoot/bin/flutter.bat" @('create', '--empty', '--platforms=windows', '--project-name=win7_smoke', '--no-pub', $app)
# Keep the minimal acceptance executable self-contained, like the engine.
# Production plugins must choose and validate their own CRT distribution.
$cmakePath = "$app/windows/CMakeLists.txt"
$cmake = [IO.File]::ReadAllText($cmakePath)
$projectLine = 'project(win7_smoke LANGUAGES CXX)'
if (!$cmake.Contains($projectLine)) { throw 'Unexpected Windows project template' }
$staticRuntime = @'
cmake_policy(SET CMP0091 NEW)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
project(win7_smoke LANGUAGES CXX)
'@
[IO.File]::WriteAllText($cmakePath, $cmake.Replace($projectLine, $staticRuntime))
Set-Location $app
Checked "$FlutterRoot/bin/flutter.bat" @('pub', 'get')
$engineSource = Split-Path (Split-Path $EngineOut -Parent) -Parent
$engineName = Split-Path $EngineOut -Leaf
Checked "$FlutterRoot/bin/flutter.bat" @('--verbose', '--local-engine-src-path', $engineSource, '--local-engine', $engineName, '--local-engine-host', $engineName, 'build', 'windows', '--release')
New-Item -ItemType Directory -Force (Split-Path $OutputDirectory -Parent) | Out-Null
Copy-Item 'build/windows/x64/runner/Release' $OutputDirectory -Recurse
[ordered]@{
  variant = $manifest.variant
  flutter_version = $manifest.flutter_version
  engine_source_commit = $manifest.engine_source_commit
  framework_checkout_commit = (& git -C $FlutterRoot rev-parse HEAD).Trim()
  dart_commit = $manifest.dart_commit
  target = $manifest.target
  runner_crt = 'static'
  compatibility_status = 'unverified'
  build_utc = [DateTime]::UtcNow.ToString('o')
} | ConvertTo-Json | Set-Content "$OutputDirectory/build-manifest.json" -Encoding utf8
Get-ChildItem $OutputDirectory -Recurse -File | ForEach-Object {
  @{ file = $_.FullName.Substring($OutputDirectory.Length).TrimStart([char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)); sha256 = (Get-FileHash $_.FullName -Algorithm SHA256).Hash }
} | ConvertTo-Json | Set-Content "$OutputDirectory/SHA256SUMS.json" -Encoding utf8
