param([string]$Out = 'shot.png', [int]$Margin = 40)

Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class W32Cap {
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string cls, string name);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
'@ -ErrorAction SilentlyContinue

$h = [W32Cap]::FindWindow([NullString]::Value, 'DSH Deskpet')
if ($h -eq [IntPtr]::Zero) { Write-Error 'pet window not found'; exit 1 }
$r = New-Object W32Cap+RECT
[void][W32Cap]::GetWindowRect($h, [ref]$r)
$w = $r.Right - $r.Left
$hh = $r.Bottom - $r.Top
$x = $r.Left - $Margin
$y = $r.Top - $Margin
$cw = $w + 2 * $Margin
$ch = $hh + 2 * $Margin
"window=$($r.Left),$($r.Top) ${w}x${hh}"

$bmp = New-Object System.Drawing.Bitmap $cw, $ch
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($x, $y, 0, 0, (New-Object System.Drawing.Size $cw, $ch))
$dir = Split-Path -Parent $PSCommandPath
$path = Join-Path $dir $Out
$bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
"saved $path ($cw x $ch)"
