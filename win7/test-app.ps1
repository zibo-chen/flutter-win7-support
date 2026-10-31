[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$BundleRoot,
  [Parameter(Mandatory=$true)][string]$ReportDirectory,
  [switch]$Interactive,
  [string]$RunId
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$BundleRoot = [IO.Path]::GetFullPath($BundleRoot)
$ReportDirectory = [IO.Path]::GetFullPath($ReportDirectory)
if (!(Test-Path "$BundleRoot/win7_smoke.exe") -or !(Test-Path "$BundleRoot/build-manifest.json")) {
  throw 'Expected a matched win7_smoke artifact and build manifest'
}
New-Item -ItemType Directory -Force $ReportDirectory | Out-Null

if (!$Interactive) {
  $RunId = [Guid]::NewGuid().ToString('N')
  $taskName = "MedivhFlutterWin7Smoke-$RunId"
  $marker = "$ReportDirectory/acceptance-$RunId.json"
  $service = New-Object -ComObject 'Schedule.Service'
  $service.Connect()
  $folder = $service.GetFolder('\')
  $definition = $service.NewTask(0)
  $definition.RegistrationInfo.Description = 'Temporary Flutter Windows 7 acceptance probe'
  $definition.Principal.UserId = "$env:USERDOMAIN\$env:USERNAME"
  $definition.Principal.LogonType = 3 # Existing interactive token; no stored password.
  $definition.Settings.Enabled = $true
  $definition.Settings.AllowDemandStart = $true
  $definition.Settings.DisallowStartIfOnBatteries = $false
  $definition.Settings.StopIfGoingOnBatteries = $false
  $definition.Settings.ExecutionTimeLimit = 'PT2M'
  $quote = { param($value) "'" + $value.Replace("'","''") + "'" }
  $command = '& ' + (& $quote $PSCommandPath) + ' -Interactive -RunId ' + (& $quote $RunId) +
    ' -BundleRoot ' + (& $quote $BundleRoot) + ' -ReportDirectory ' + (& $quote $ReportDirectory)
  $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
  $action = $definition.Actions.Create(0)
  $action.Path = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
  $action.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand $encoded"
  $action.WorkingDirectory = $BundleRoot
  $task = $folder.RegisterTaskDefinition($taskName,$definition,2,$definition.Principal.UserId,$null,3)
  try {
    [void]$task.Run($null)
    $deadline = [DateTime]::UtcNow.AddSeconds(50)
    while (!(Test-Path $marker) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 500 }
    if (!(Test-Path $marker)) { throw 'Interactive acceptance did not produce its report' }
    [Console]::OutputEncoding = [Text.Encoding]::UTF8
    Get-Content $marker -Raw -Encoding UTF8
  } finally {
    try { $task.Stop(0) } catch {}
    $folder.DeleteTask($taskName,0)
  }
  exit
}

if (!$RunId) { throw 'Interactive invocation requires a run ID' }
$runtimePath = "$ReportDirectory/runtime-$RunId.json"
$windowImage = "$ReportDirectory/window-$RunId.png"
$inputImage = "$ReportDirectory/input-$RunId.png"
$record = [ordered]@{ run_id=$RunId; runtime_report=$runtimePath; window_image=$null; input_image=$null; input_attempted=$false; process_exit_code=$null; forced_close=$false; error=$null }
$process = $null
try {
  Add-Type -AssemblyName System.Drawing
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -ReferencedAssemblies System.Drawing,System.Windows.Forms @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public static class FlutterWin7Window {
  [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left,Top,Right,Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct Point { public int X,Y; }
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h,int cmd);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h,out Rect r);
  [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr h,ref Point p);
  [DllImport("kernel32.dll")] public static extern uint SetErrorMode(uint mode);
  public static bool Capture(IntPtr window,string path) {
    if (GetForegroundWindow()!=window) return false;
    Rect r; Point p=new Point();
    if (!GetClientRect(window,out r) || !ClientToScreen(window,ref p)) return false;
    Rectangle area=Rectangle.Intersect(new Rectangle(p.X,p.Y,r.Right-r.Left,r.Bottom-r.Top),Screen.PrimaryScreen.Bounds);
    if (area.Width<=0 || area.Height<=0) return false;
    using (Bitmap image=new Bitmap(area.Width,area.Height))
    using (Graphics graphics=Graphics.FromImage(image)) {
      graphics.CopyFromScreen(area.Location,System.Drawing.Point.Empty,area.Size);
      image.Save(path,ImageFormat.Png);
    }
    return true;
  }
}
'@
  [void][FlutterWin7Window]::SetProcessDPIAware()
  [void][FlutterWin7Window]::SetErrorMode(0x8003)
  $process = New-Object Diagnostics.Process
  $process.StartInfo.FileName = "$BundleRoot/win7_smoke.exe"
  $process.StartInfo.WorkingDirectory = $BundleRoot
  $process.StartInfo.UseShellExecute = $false
  $process.StartInfo.RedirectStandardOutput = $true
  $process.StartInfo.RedirectStandardError = $true
  $process.StartInfo.EnvironmentVariables['MEDIVH_WIN7_REPORT'] = $runtimePath
  [void]$process.Start()
  $stdoutTask = $process.StandardOutput.ReadToEndAsync()
  $stderrTask = $process.StandardError.ReadToEndAsync()
  $deadline = [DateTime]::UtcNow.AddSeconds(30)
  while (!(Test-Path $runtimePath) -and !$process.HasExited -and [DateTime]::UtcNow -lt $deadline) {
    Start-Sleep -Milliseconds 250
    $process.Refresh()
  }
  $record.runtime_complete = Test-Path $runtimePath
  if ($record.runtime_complete) { $record.runtime = Get-Content $runtimePath -Raw -Encoding UTF8 | ConvertFrom-Json }
  if (!$process.HasExited) {
    $process.Refresh()
    $window = $process.MainWindowHandle
    if ($window -ne [IntPtr]::Zero) {
      [void][FlutterWin7Window]::ShowWindow($window,3)
      [void][FlutterWin7Window]::SetForegroundWindow($window)
      Start-Sleep -Milliseconds 700
      if ([FlutterWin7Window]::Capture($window,$windowImage)) { $record.window_image=$windowImage }
      # Never send input to another foreground application.
      if ([FlutterWin7Window]::GetForegroundWindow() -eq $window) {
        [Windows.Forms.SendKeys]::SendWait('{TAB}Win7-input-123{TAB} ')
        $record.input_attempted=$true
        Start-Sleep -Milliseconds 500
        if ([FlutterWin7Window]::Capture($window,$inputImage)) { $record.input_image=$inputImage }
      }
    }
  }
} catch {
  $record.error = $_.Exception.ToString()
} finally {
  if ($process) {
    try {
      if (!$process.HasExited) {
        [void]$process.CloseMainWindow()
        if (!$process.WaitForExit(5000)) { $record.forced_close=$true; $process.Kill(); $process.WaitForExit() }
      }
      $record.process_exit_code = $process.ExitCode
      if ($stdoutTask) { [IO.File]::WriteAllText("$ReportDirectory/stdout-$RunId.txt",$stdoutTask.Result) }
      if ($stderrTask) { [IO.File]::WriteAllText("$ReportDirectory/stderr-$RunId.txt",$stderrTask.Result) }
    } catch { $record.cleanup_error=$_.Exception.ToString() }
    $process.Dispose()
  }
  $record.passed = $record.runtime_complete -and $record.runtime.passed -and $record.window_image -and ($record.process_exit_code -eq 0) -and !$record.forced_close -and !$record.error
  $record | ConvertTo-Json -Depth 10 | Set-Content "$ReportDirectory/acceptance-$RunId.json" -Encoding UTF8
}
