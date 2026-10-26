# shot.ps1 <hwnd-file> <out.png>: a picture of one window of ours (PrintWindow, by the hwnd the
# preview wrote), so nothing else on the screen is captured. DPI aware (150% scaling cropped it).
param([string]$log, [string]$out)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class PW { [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint f);
 [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
 public struct RECT { public int L, T, R, B; } }
"@
[PW]::SetProcessDPIAware() | Out-Null
for ($i = 0; $i -lt 150 -and -not (Test-Path $log); $i++) { Start-Sleep -Milliseconds 200 }
if (-not (Test-Path $log)) { "no hwnd written to $log"; exit 1 }
Start-Sleep -Milliseconds 300
$h = [IntPtr][long](Get-Content $log)
$r = New-Object PW+RECT; [PW]::GetWindowRect($h, [ref]$r) | Out-Null
if ($r.R -le $r.L) { "window $h has no size (gone or hidden)"; exit 1 }
$bmp = New-Object System.Drawing.Bitmap ($r.R - $r.L), ($r.B - $r.T)
$g = [System.Drawing.Graphics]::FromImage($bmp); $dc = $g.GetHdc()
[PW]::PrintWindow($h, $dc, 2) | Out-Null
$g.ReleaseHdc($dc); $bmp.Save($out)
"saved $out"
