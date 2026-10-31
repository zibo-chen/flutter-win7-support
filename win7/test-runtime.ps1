[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$BundleRoot,
  [Parameter(Mandatory=$true)][string]$ReportDirectory
)
$ErrorActionPreference = 'Stop'
$BundleRoot = [IO.Path]::GetFullPath($BundleRoot)
New-Item -ItemType Directory -Force $ReportDirectory | Out-Null
$reportPath = Join-Path ([IO.Path]::GetFullPath($ReportDirectory)) ('runtime-' + [Guid]::NewGuid().ToString('N') + '.json')
$process = New-Object Diagnostics.Process
$process.StartInfo.FileName = "$BundleRoot/win7_smoke.exe"
$process.StartInfo.WorkingDirectory = $BundleRoot
$process.StartInfo.UseShellExecute = $false
$process.StartInfo.RedirectStandardOutput = $true
$process.StartInfo.RedirectStandardError = $true
$process.StartInfo.EnvironmentVariables['MEDIVH_WIN7_REPORT'] = $reportPath
try {
  [void]$process.Start()
  $stdout = $process.StandardOutput.ReadToEndAsync()
  $stderr = $process.StandardError.ReadToEndAsync()
  $deadline = [DateTime]::UtcNow.AddSeconds(40)
  while (!(Test-Path $reportPath) -and !$process.HasExited -and [DateTime]::UtcNow -lt $deadline) {
    Start-Sleep -Milliseconds 250
  }
  if (!(Test-Path $reportPath)) { throw 'Application did not produce its first-frame/runtime report' }
  $report = Get-Content $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
  if (!$report.first_frame -or !$report.passed) { throw 'Application runtime probe failed' }
  [void]$process.CloseMainWindow()
  if (!$process.WaitForExit(5000)) { throw 'Application did not close normally' }
  if ($process.ExitCode -ne 0) { throw "Application exited $($process.ExitCode)" }
  Get-Content $reportPath -Raw -Encoding UTF8
} finally {
  if (!$process.HasExited) { $process.Kill(); $process.WaitForExit() }
  if ($stdout) { [IO.File]::WriteAllText("$ReportDirectory/stdout.txt", $stdout.Result) }
  if ($stderr) { [IO.File]::WriteAllText("$ReportDirectory/stderr.txt", $stderr.Result) }
  $process.Dispose()
}
