# =====================================================================
#  pet-actions.ps1 · 点一下桌宠拉出的功能面板（功能层）
#  由 pet.ps1 在 Say-Random 之后 dot-source 引入：
#      . (Join-Path $script:Dir 'pet-actions.ps1')
#  只负责“能干什么”，视觉（颜色/圆角/字体）可以单独替换。
# =====================================================================

$script:actWin       = $win
$script:actRoot      = $root
$script:actWorkspace = Split-Path -Parent $script:Dir
$script:actConfig    = Join-Path $script:Dir 'pet-config.json'
$script:actPopup     = $null
$script:actBorder    = $null
$script:actTt        = $null
$script:actPanelH    = 300
$script:actChecks    = @{}

function Act-Brush([string]$hex, [double]$op = 1.0) {
    $c = [System.Windows.Media.ColorConverter]::ConvertFromString($hex)
    $b = New-Object System.Windows.Media.SolidColorBrush($c)
    $b.Opacity = $op
    return $b
}

$script:actHoverBrush = Act-Brush '#E8EFFF' 1.0

# ---------- 功能表（想加功能就在这里加一行，再在 Invoke-PetAction 里补分支） ----------
$script:actItems = @(
    @{ id = 'dsh';      icon = '🐋'; label = '打开 DSH' }
    @{ id = 'chat';     icon = '💭'; label = '和小鲸聊天' }
    @{ id = 'review';   icon = '✅'; label = '查看完成任务' }
    @{ id = 'folder';   icon = '📁'; label = '打开工作区' }
    @{ id = 'terminal'; icon = '⌨';  label = '打开终端' }
    @{ id = 'shot';     icon = '📸'; label = '截个屏' }
    @{ id = 'copy';     icon = '📋'; label = '复制工作区路径' }
    @{ id = 'say';      icon = '💬'; label = '说句话'; sep = $true }
    @{ id = 'wander';   icon = '🌀'; label = '四处游动' }
    @{ id = 'config';   icon = '⚙';  label = '打开配置'; sep = $true }
    @{ id = 'quit';     icon = '⏻';  label = '退出' }
)

# ---------- 窗口工具 ----------
if (-not ('PetAct.Win' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
namespace PetAct {
  public class Win {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool f);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  }
}
'@
}

function Find-DshWindow {
    $script:actDshHwnd = [IntPtr]::Zero
    $cb = [PetAct.Win+EnumProc]{
        param($h, $l)
        if ([PetAct.Win]::IsWindowVisible($h)) {
            $sb = New-Object System.Text.StringBuilder 512
            [void][PetAct.Win]::GetWindowText($h, $sb, 512)
            if ($sb.ToString() -like '*DeepSeek Harness*') {
                $script:actDshHwnd = $h
                return $false
            }
        }
        return $true
    }
    [void][PetAct.Win]::EnumWindows($cb, [IntPtr]::Zero)
    return $script:actDshHwnd
}

function Show-DshWindow {
    $h = Find-DshWindow
    if ($h -eq [IntPtr]::Zero) {
        $exe = Join-Path $env:LOCALAPPDATA 'Programs\DeepSeek Harness\DeepSeek Harness.exe'
        if (Test-Path $exe) {
            Start-Process $exe
            Show-Say 'DSH 没开着，帮你启动一个 🐋' 3
        } else {
            Show-Say '没找到 DSH 窗口…' 3
        }
        return
    }
    [void][PetAct.Win]::ShowWindow($h, 9)   # SW_RESTORE
    $fgPid = 0
    $fgTid = [PetAct.Win]::GetWindowThreadProcessId([PetAct.Win]::GetForegroundWindow(), [ref]$fgPid)
    $myTid = [PetAct.Win]::GetCurrentThreadId()
    [void][PetAct.Win]::AttachThreadInput($fgTid, $myTid, $true)
    [void][PetAct.Win]::SetForegroundWindow($h)
    [void][PetAct.Win]::AttachThreadInput($fgTid, $myTid, $false)
}

function Save-PetShot {
    try {
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing -ErrorAction Stop
        $dir = Join-Path $script:actWorkspace 'shots'
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $name = 'shot-{0:yyyyMMdd-HHmmss}.png' -f (Get-Date)
        $path = Join-Path $dir $name

        Close-PetActions
        $script:actWin.Hide()
        Start-Sleep -Milliseconds 220
        $vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
        $bmp = New-Object System.Drawing.Bitmap $vs.Width, $vs.Height
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen($vs.Left, $vs.Top, 0, 0, $bmp.Size)
        $g.Dispose()
        $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        $script:actWin.Show()
        Show-Say ('截图放到 shots\' + $name + ' 📸') 4
    } catch {
        try { $script:actWin.Show() } catch { }
        Show-Say ('截图失败：' + $_.Exception.Message) 4
    }
}

function Open-PetTerminal {
    $wt = Get-Command wt.exe -ErrorAction SilentlyContinue
    try {
        if ($wt) {
            Start-Process -FilePath $wt.Source -ArgumentList ('-d "' + $script:actWorkspace + '"')
        } else {
            Start-Process -FilePath 'powershell.exe' -ArgumentList ('-NoExit -Command "Set-Location -LiteralPath ''{0}''"' -f $script:actWorkspace)
        }
    } catch {
        Show-Say ('终端没打开：' + $_.Exception.Message) 4
    }
}

# ---------- 执行 ----------
function Invoke-PetAction([string]$id) {
    switch ($id) {
        'dsh'      { Show-DshWindow }
        'chat'     { if (Get-Command Show-PetChat -ErrorAction SilentlyContinue) { Show-PetChat } }
        'folder'   { Start-Process -FilePath 'explorer.exe' -ArgumentList ('"' + $script:actWorkspace + '"') }
        'terminal' { Open-PetTerminal }
        'shot'     { Save-PetShot }
        'copy'     {
            try {
                [System.Windows.Clipboard]::SetText($script:actWorkspace)
                Show-Say '工作区路径已复制 📋' 3
            } catch { Show-Say '剪贴板被占用了，再试一次？' 3 }
        }
        'review'   {
            Show-DshWindow
            $script:doneCount = 0
            if ($script:bubbleKind -eq 'review') { $script:bubbleUntil = $script:t }
        }
        'say'      { Say-Random }
        'wander'   {
            $script:wanderOn = -not $script:wanderOn
            if ($script:wanderOn) { Show-Say '好，我去逛逛 🌀' 2.5 } else { Show-Say '那我就在这儿待着。' 2.5 }
        }
        'config'   { Start-Process -FilePath 'notepad.exe' -ArgumentList ('"' + $script:actConfig + '"') }
        'quit'     { $script:actWin.Close() }
    }
}

# ---------- 面板 ----------
function Update-PetActionChecks {
    $chk = $script:actChecks['wander']
    if ($chk) {
        if ($script:wanderOn) { $chk.Text = '✓' } else { $chk.Text = '' }
    }
    $r = $script:actChecks['review']
    if ($r) {
        if ($script:doneCount -gt 0) { $r.Text = [string]$script:doneCount } else { $r.Text = '' }
    }
}

function Initialize-PetActions {
    if ($script:actPopup) { return }

    $border = New-Object System.Windows.Controls.Border
    $border.Width = 236
    $border.CornerRadius = [System.Windows.CornerRadius]::new(14)
    $border.Background = Act-Brush '#FCFEFF' 0.985
    $border.BorderBrush = Act-Brush '#C9D8FF' 0.95
    $border.BorderThickness = [System.Windows.Thickness]::new(1)
    $border.Padding = [System.Windows.Thickness]::new(6, 6, 6, 6)

    $sh = New-Object System.Windows.Media.Effects.DropShadowEffect
    $sh.BlurRadius = 20
    $sh.ShadowDepth = 4
    $sh.Opacity = 0.24
    $sh.Color = [System.Windows.Media.ColorConverter]::ConvertFromString('#2A43D8')
    $border.Effect = $sh

    $stack = New-Object System.Windows.Controls.StackPanel
    $border.Child = $stack

    $iconFont = New-Object System.Windows.Media.FontFamily('Segoe UI Emoji, Segoe UI Symbol, Segoe UI')
    $uiFont = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI, Segoe UI')

    foreach ($it in $script:actItems) {
        if ($it.sep) {
            $line = New-Object System.Windows.Controls.Border
            $line.Height = 1
            $line.Margin = [System.Windows.Thickness]::new(10, 4, 10, 4)
            $line.Background = Act-Brush '#DCE5FA' 1.0
            $stack.Children.Add($line) | Out-Null
        }

        $row = New-Object System.Windows.Controls.Border
        $row.Height = 25
        $row.CornerRadius = [System.Windows.CornerRadius]::new(8)
        $row.Padding = [System.Windows.Thickness]::new(8, 2, 8, 2)
        $row.Margin = [System.Windows.Thickness]::new(0, 0, 0, 0)
        $row.Background = [System.Windows.Media.Brushes]::Transparent
        $row.Tag = $it.id
        $row.Cursor = [System.Windows.Input.Cursors]::Hand

        $dp = New-Object System.Windows.Controls.DockPanel

        $ico = New-Object System.Windows.Controls.TextBlock
        $ico.Text = $it.icon
        $ico.Width = 24
        $ico.FontSize = 12.5
        $ico.FontFamily = $iconFont
        $ico.TextAlignment = 'Center'
        $ico.VerticalAlignment = 'Center'
        [System.Windows.Controls.DockPanel]::SetDock($ico, 'Left')

        $lbl = New-Object System.Windows.Controls.TextBlock
        $lbl.Text = $it.label
        $lbl.FontSize = 12.5
        $lbl.FontFamily = $uiFont
        $lbl.Foreground = Act-Brush '#16306B' 1.0
        $lbl.VerticalAlignment = 'Center'
        $lbl.TextTrimming = 'CharacterEllipsis'

        $chk = New-Object System.Windows.Controls.TextBlock
        $chk.Width = 34
        $chk.FontSize = 10.5
        $chk.Foreground = Act-Brush '#7C89B3' 1.0
        $chk.TextAlignment = 'Right'
        $chk.VerticalAlignment = 'Center'
        [System.Windows.Controls.DockPanel]::SetDock($chk, 'Right')

        $dp.Children.Add($ico) | Out-Null
        $dp.Children.Add($chk) | Out-Null
        $dp.Children.Add($lbl) | Out-Null
        $row.Child = $dp

        $row.Add_MouseEnter({ param($s, $e) $s.Background = $script:actHoverBrush })
        $row.Add_MouseLeave({ param($s, $e) $s.Background = [System.Windows.Media.Brushes]::Transparent })
        $row.Add_MouseLeftButtonUp({
            param($s, $e)
            $e.Handled = $true
            $id = [string]$s.Tag
            Close-PetActions
            Invoke-PetAction $id
        })

        $stack.Children.Add($row) | Out-Null
        if ($it.id -eq 'wander') { $script:actChecks['wander'] = $chk }
        if ($it.id -eq 'review') { $script:actChecks['review'] = $chk }
    }

    $border.Measure([System.Windows.Size]::new(236, [double]::PositiveInfinity))
    $script:actPanelH = [Math]::Ceiling($border.DesiredSize.Height)
    $script:actTailH = 9

    $shell = New-Object System.Windows.Controls.Canvas
    $shell.Width = 236
    $shell.Height = $script:actPanelH + $script:actTailH
    [System.Windows.Controls.Canvas]::SetLeft($border, 0)
    [System.Windows.Controls.Canvas]::SetTop($border, 0)
    $shell.Children.Add($border) | Out-Null

    $tailPath = New-Object System.Windows.Shapes.Path
    $tailPath.Fill = Act-Brush '#FCFEFF' 0.985
    $tailPath.Visibility = 'Collapsed'
    $shell.Children.Add($tailPath) | Out-Null

    $tt = New-Object System.Windows.Media.TranslateTransform(0, 0)
    $shell.RenderTransform = $tt

    $popup = New-Object System.Windows.Controls.Primitives.Popup
    $popup.AllowsTransparency = $true
    $popup.StaysOpen = $false
    $popup.Placement = 'Absolute'
    $popup.Child = $shell
    $popup.Add_Opened({
        $script:actShell.Opacity = 0
        $script:actTt.Y = 10
        $an = New-Object System.Windows.Media.Animation.DoubleAnimation
        $an.From = 0.0
        $an.To = 1.0
        $an.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(130))
        $script:actShell.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $an)
        $an2 = New-Object System.Windows.Media.Animation.DoubleAnimation
        $an2.From = 10.0
        $an2.To = 0.0
        $an2.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(150))
        $script:actTt.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $an2)
    })

    $script:actShell = $shell
    $script:actBorder = $border
    $script:actTail = $tailPath
    $script:actTt = $tt
    $script:actPopup = $popup
}

function Show-PetActions {
    Initialize-PetActions
    if ($script:actPopup.IsOpen) { return }
    Update-PetActionChecks

    $wa = [System.Windows.SystemParameters]::WorkArea
    $pw = 236.0
    $ph = [double]$script:actPanelH
    $th = [double]$script:actTailH
    $wx = [double]$script:actWin.Left
    $wy = [double]$script:actWin.Top
    $ww = 300.0
    $wh = 432.0
    if ($script:actWin.ActualWidth -gt 50) { $ww = [double]$script:actWin.ActualWidth }
    if ($script:actWin.ActualHeight -gt 50) { $wh = [double]$script:actWin.ActualHeight }

    # 锚点 = 角色头顶，和说话气泡的尾巴尖是同一个点（贴人）
    #   说话气泡：底边 bubbleBottom，尾巴尖 bubbleBottom + 14
    $ax = $wx + 150.0
    $ay = $wy + [double]$script:bubbleBottom + 14.0

    # 首选：头顶上方；面板尾巴尖精确抵住头顶（gap = 0）
    $tailOn = $true
    $left = $ax - $pw / 2.0
    $top = $ay - $ph - 8.0

    if ($top -lt $wa.Top + 4) {
        # 上方放不下：放角色右侧贴着头部；没位置再放左侧；都不行兜底到下方
        $tailOn = $false
        if (($wx + $ww + $pw + 6.0) -le ($wa.Right - 6)) {
            $left = $wx + $ww + 6.0
            $top = $ay - 64.0
        } elseif (($wx - $pw - 6.0) -ge ($wa.Left + 6)) {
            $left = $wx - $pw - 6.0
            $top = $ay - 64.0
        } else {
            $left = $ax - $pw / 2.0
            $top = $wy + $wh + 6.0
        }
    }

    if ($left -lt $wa.Left + 6) { $left = $wa.Left + 6 }
    if ($left + $pw -gt $wa.Right - 6) { $left = $wa.Right - 6 - $pw }
    if ($top -lt $wa.Top + 4) { $top = $wa.Top + 4 }
    if ($top + $ph + $th -gt $wa.Bottom - 6) { $top = $wa.Bottom - 6 - $ph - $th }

    if ($tailOn) {
        # 尾巴尖对准角色头顶
        $tip = $ax - $left
        if ($tip -lt 18) { $tip = 18 }
        if ($tip -gt ($pw - 18)) { $tip = $pw - 18 }
        $tp = New-Object System.Windows.Media.PathGeometry
        $tf = New-Object System.Windows.Media.PathFigure
        $tf.StartPoint = [System.Windows.Point]::new($tip - 9, $ph - 1)
        $tf.Segments.Add([System.Windows.Media.LineSegment]::new([System.Windows.Point]::new($tip, $ph + 8), $true))
        $tf.Segments.Add([System.Windows.Media.LineSegment]::new([System.Windows.Point]::new($tip + 9, $ph - 1), $true))
        $tf.IsClosed = $true
        $tp.Figures.Add($tf)
        $script:actTail.Data = $tp
        $script:actTail.Visibility = 'Visible'
    } else {
        $script:actTail.Visibility = 'Collapsed'
    }

    $script:actPopup.HorizontalOffset = $left
    $script:actPopup.VerticalOffset = $top
    $script:actPopup.IsOpen = $true
}

function Close-PetActions {
    if ($script:actPopup -and $script:actPopup.IsOpen) { $script:actPopup.IsOpen = $false }
}
