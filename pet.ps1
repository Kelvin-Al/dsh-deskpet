# =====================================================================
#  DSH 桌宠 · 小蓝鲸 (DeepSeek Deskpet)
#  透明置顶悬浮窗 + 矢量小蓝鲸 + 呼吸/眨眼/游动/气泡/DSH 状态感知
#
#  运行:  powershell -STA -NoProfile -ExecutionPolicy Bypass -File pet.ps1
#  或双击 launch.cmd
# =====================================================================
$ErrorActionPreference = 'Stop'

# 启动期任何致命错误都写进 pet.log，避免双击后“什么都没发生”
trap {
    try {
        $p = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'pet.log' } else { Join-Path (Get-Location) 'pet.log' }
        Add-Content -Path $p -Value ('[{0:HH:mm:ss}] FATAL {1} (line {2})' -f (Get-Date), $_.Exception.Message, $_.InvocationInfo.ScriptLineNumber) -Encoding UTF8
    } catch { }
    exit 1
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml | Out-Null

# ---------- 隐藏控制台 ----------
try {
    Add-Type -Namespace DshPet -Name Native -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'@ -ErrorAction SilentlyContinue
    $ch = [DshPet.Native]::GetConsoleWindow()
    if ($ch -ne [IntPtr]::Zero) { [void][DshPet.Native]::ShowWindow($ch, 0) }
} catch { }

# ---------- 单实例 ----------
# 已经有实例在跑：把它叫到前面，然后退出（不再静默失败）
$script:mutex = New-Object System.Threading.Mutex($false, 'Local\DshDeskpet.BlueWhale')
$script:owned = $false
try {
    $script:owned = $script:mutex.WaitOne(0)
} catch [System.Threading.AbandonedMutexException] {
    # 上一个实例被强杀，接管它
    $script:owned = $true
}
if (-not $script:owned) {
    try {
        if (-not ('DshPetActivate' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public class DshPetActivate {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
}
'@
        }
        $script:actHwnd = [IntPtr]::Zero
        $cb = [DshPetActivate+EnumProc]{
            param($h, $l)
            $sb = New-Object System.Text.StringBuilder 256
            [void][DshPetActivate]::GetWindowText($h, $sb, 256)
            if ($sb.ToString() -eq 'DSH Deskpet') { $script:actHwnd = $h; return $false }
            return $true
        }
        [void][DshPetActivate]::EnumWindows($cb, [IntPtr]::Zero)
        if ($script:actHwnd -ne [IntPtr]::Zero) {
            [void][DshPetActivate]::ShowWindow($script:actHwnd, 9)   # SW_RESTORE
            [void][DshPetActivate]::SetForegroundWindow($script:actHwnd)
        }
        $lp = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'pet.log' } else { Join-Path (Get-Location) 'pet.log' }
        Add-Content -Path $lp -Value ('[{0:HH:mm:ss}] second launch: 已有一只在跑，把旧窗口叫到前面' -f (Get-Date)) -Encoding UTF8
    } catch { }
    return
}

$script:Dir = if ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { (Get-Location).Path }
$script:LogPath = Join-Path $script:Dir 'pet.log'
function Log([string]$m) {
    try {
        $line = '[{0:HH:mm:ss}] {1}' -f (Get-Date), $m
        if ($m -eq 'start') { Set-Content -Path $script:LogPath -Value $line -Encoding UTF8 }
        else { Add-Content -Path $script:LogPath -Value $line -Encoding UTF8 }
    } catch { }
}
Log 'start'
$script:StateFile = Join-Path $script:Dir 'pet-state.json'
$script:ConfigFile = Join-Path $script:Dir 'pet-config.json'
$script:SessionRoot = Join-Path $env:USERPROFILE '.dsh\sessions'

# ---------- 配色 (DeepSeek 蓝) ----------
function Brush([string]$hex, [double]$op = 1.0) {
    $c = [System.Windows.Media.ColorConverter]::ConvertFromString($hex)
    $b = New-Object System.Windows.Media.SolidColorBrush($c)
    $b.Opacity = $op
    return $b
}

$C_BLUE_HI = '#9DB2FF'
$C_BLUE    = '#4D6BFE'
$C_BLUE_LO = '#2A43D8'
$C_DARK    = '#0D1B45'
$C_BELLY   = '#F1F6FF'
$C_BLUSH   = '#FF9EC4'

# ---------- 配置 ----------
$script:cfg = @{
    name    = '小鲸'
    wander  = $false
    scale   = 1.0
    bob     = $false
    sprite  = ''
    spriteHeight = 300
    topmost = $true
    lines   = @(
        '我是小蓝鲸，DeepSeek 家养的 🐋'
        '在写了在写了…',
        '这个仓库我熟。',
        '要不要我帮你跑个测试？',
        '别忘了 commit 呀。',
        '我帮你在后台盯着终端。',
        '嗯…让我想想。',
        '摸鱼是不对的，但我是鲸鱼。'
    )
}
if (Test-Path $script:ConfigFile) {
    try {
        $raw = Get-Content $script:ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($p in $raw.PSObject.Properties) {
            if ($null -ne $p.Value) { $script:cfg[$p.Name] = $p.Value }
        }
    } catch { }
}

# ---------- 窗口 ----------
$win = New-Object System.Windows.Window
$win.Title = 'DSH Deskpet'
$win.WindowStyle = 'None'
$win.AllowsTransparency = $true
$win.Background = [System.Windows.Media.Brushes]::Transparent
$win.Topmost = [bool]$script:cfg.topmost
$win.ShowInTaskbar = $false
$win.ShowActivated = $false
$win.ResizeMode = 'NoResize'
$win.Width = 300
$win.Height = 320

$wa = [System.Windows.SystemParameters]::WorkArea
$win.Left = [Math]::Max($wa.Left, $wa.Right - 340)
$win.Top  = [Math]::Max($wa.Top,  $wa.Bottom - 360)

$root = New-Object System.Windows.Controls.Canvas
$root.Width = 300
$root.Height = 320
$root.Background = [System.Windows.Media.Brushes]::Transparent
$win.Content = $root

# ---------- 气泡 ----------
$bubbleTxt = New-Object System.Windows.Controls.TextBlock
$bubbleTxt.TextWrapping = 'Wrap'
$bubbleTxt.MaxWidth = 220
$bubbleTxt.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI, Segoe UI')
$bubbleTxt.FontSize = 13.5
$bubbleTxt.Foreground = Brush '#16306B'
$bubbleTxt.LineHeight = 20

$bubble = New-Object System.Windows.Controls.Border
$bubble.CornerRadius = [System.Windows.CornerRadius]::new(15)
$bubble.Padding = [System.Windows.Thickness]::new(13, 9, 13, 10)
$bubble.Background = Brush '#FCFEFF' 1.0
$bubble.BorderBrush = Brush '#B9CDFF' 0.9
$bubble.BorderThickness = [System.Windows.Thickness]::new(1)
$bubble.Child = $bubbleTxt
$bubble.Visibility = 'Collapsed'

$sh = New-Object System.Windows.Media.Effects.DropShadowEffect
$sh.BlurRadius = 16; $sh.ShadowDepth = 2; $sh.Opacity = 0.28
$sh.Color = [System.Windows.Media.ColorConverter]::ConvertFromString('#2A43D8')
$bubble.Effect = $sh

$tail = New-Object System.Windows.Shapes.Path
$tail.Fill = Brush '#FCFEFF' 1.0
$tail.Visibility = 'Collapsed'

$root.Children.Add($bubble) | Out-Null
$root.Children.Add($tail) | Out-Null

# ---------- 小蓝鲸 ----------
# =====================================================================
#  Character: Q 版鲸鱼娘 (whale girl)
#  canvas 220 x 230
# =====================================================================
# =====================================================================
#  Character: 小蓝鲸 (DeepSeek whale)  canvas 200x190
# =====================================================================
$petC = New-Object System.Windows.Controls.Canvas
$petC.Width = 200
$petC.Height = 190
[System.Windows.Controls.Canvas]::SetLeft($petC, 50)
[System.Windows.Controls.Canvas]::SetTop($petC, 120)
$root.Children.Add($petC) | Out-Null

function New-Geo([scriptblock]$build) {
    $g = New-Object System.Windows.Media.PathGeometry
    $f = New-Object System.Windows.Media.PathFigure
    $build.Invoke($f)
    $f.IsClosed = $true
    $g.Figures.Add($f)
    return $g
}
function Q([double]$cx, [double]$cy, [double]$ex, [double]$ey) {
    $s = New-Object System.Windows.Media.QuadraticBezierSegment(
        [System.Windows.Point]::new($cx, $cy), [System.Windows.Point]::new($ex, $ey), $true)
    return $s
}
function Cub([double]$c1x, [double]$c1y, [double]$c2x, [double]$c2y, [double]$ex, [double]$ey) {
    $s = New-Object System.Windows.Media.BezierSegment(
        [System.Windows.Point]::new($c1x, $c1y),
        [System.Windows.Point]::new($c2x, $c2y),
        [System.Windows.Point]::new($ex, $ey), $true)
    return $s
}

# -- 地面阴影
$shadow = New-Object System.Windows.Shapes.Ellipse
$shadow.Width = 112; $shadow.Height = 18
$shadow.Fill = Brush '#0D1B45' 0.13
$bl = New-Object System.Windows.Media.Effects.BlurEffect
$bl.Radius = 9
$shadow.Effect = $bl
[System.Windows.Controls.Canvas]::SetLeft($shadow, 44)
[System.Windows.Controls.Canvas]::SetTop($shadow, 148)
$petC.Children.Add($shadow) | Out-Null

# -- 尾巴（在身后，左右两支尾鳍）
$tailGeo = New-Geo {
    param($f)
    $f.StartPoint = [System.Windows.Point]::new(64, 122)
    $f.Segments.Add((Cub 52 130 36 138 26 150))
    $f.Segments.Add((Cub 44 152 60 144 70 132))
}
$tailEl = New-Object System.Windows.Shapes.Path
$tailEl.Data = $tailGeo
$tailEl.Fill = Brush '#2A43D8' 1.0
$petC.Children.Add($tailEl) | Out-Null

$tailGeo2 = New-Geo {
    param($f)
    $f.StartPoint = [System.Windows.Point]::new(62, 114)
    $f.Segments.Add((Cub 48 104 34 92 26 78))
    $f.Segments.Add((Cub 42 80 58 94 68 108))
}
$tailEl2 = New-Object System.Windows.Shapes.Path
$tailEl2.Data = $tailGeo2
$tailEl2.Fill = Brush '#3450E6' 0.95
$petC.Children.Add($tailEl2) | Out-Null

# -- 身体
$bodyGeo = New-Geo {
    param($f)
    $f.StartPoint = [System.Windows.Point]::new(34, 98)
    $f.Segments.Add((Cub 34 62 62 42 100 42))
    $f.Segments.Add((Cub 138 42 166 62 166 98))
    $f.Segments.Add((Cub 166 130 138 150 100 150))
    $f.Segments.Add((Cub 62 150 34 130 34 98))
}

$bodyGrad = New-Object System.Windows.Media.LinearGradientBrush
$bodyGrad.StartPoint = [System.Windows.Point]::new(0.15, 0)
$bodyGrad.EndPoint = [System.Windows.Point]::new(0.8, 1)
$bodyGrad.GradientStops.Add((New-Object System.Windows.Media.GradientStop([System.Windows.Media.ColorConverter]::ConvertFromString($C_BLUE_HI), 0)))
$bodyGrad.GradientStops.Add((New-Object System.Windows.Media.GradientStop([System.Windows.Media.ColorConverter]::ConvertFromString($C_BLUE), 0.45)))
$bodyGrad.GradientStops.Add((New-Object System.Windows.Media.GradientStop([System.Windows.Media.ColorConverter]::ConvertFromString($C_BLUE_LO), 1)))

$body = New-Object System.Windows.Shapes.Path
$body.Data = $bodyGeo
$body.Fill = $bodyGrad
$body.Stroke = Brush '#A9BAFF' 0.55
$body.StrokeThickness = 1.2
$petC.Children.Add($body) | Out-Null

# -- 身体内部（受裁剪）：肚皮 + 高光 + 喷气孔
$inner = New-Object System.Windows.Controls.Canvas
$inner.Width = 200
$inner.Height = 190
$inner.Clip = $bodyGeo
$petC.Children.Add($inner) | Out-Null

$belly = New-Object System.Windows.Shapes.Ellipse
$belly.Width = 96; $belly.Height = 62
$belly.Fill = Brush $C_BELLY 0.92
[System.Windows.Controls.Canvas]::SetLeft($belly, 52)
[System.Windows.Controls.Canvas]::SetTop($belly, 108)
$inner.Children.Add($belly) | Out-Null

$bellyLine = New-Object System.Windows.Shapes.Path
$bellyLine.Stroke = Brush '#9DB2FF' 0.5
$bellyLine.StrokeThickness = 1
$bellyLine.Data = New-Geo {
    param($f)
    $f.StartPoint = [System.Windows.Point]::new(56, 116)
    $f.Segments.Add((Q 100 128 144 116))
}
$inner.Children.Add($bellyLine) | Out-Null

$gloss = New-Object System.Windows.Shapes.Ellipse
$gloss.Width = 52; $gloss.Height = 30
$gloss.Fill = Brush '#FFFFFF' 0.40
$gloss.RenderTransform = New-Object System.Windows.Media.RotateTransform(-24)
$gloss.RenderTransformOrigin = [System.Windows.Point]::new(0.5, 0.5)
[System.Windows.Controls.Canvas]::SetLeft($gloss, 56)
[System.Windows.Controls.Canvas]::SetTop($gloss, 56)
$inner.Children.Add($gloss) | Out-Null

$hole = New-Object System.Windows.Shapes.Ellipse
$hole.Width = 20; $hole.Height = 7
$hole.Fill = Brush '#1B2FA8' 0.30
[System.Windows.Controls.Canvas]::SetLeft($hole, 90)
[System.Windows.Controls.Canvas]::SetTop($hole, 50)
$inner.Children.Add($hole) | Out-Null

# -- 喷水花（气泡颗粒）
$spouts = @()
for ($i = 0; $i -lt 6; $i++) {
    $d = New-Object System.Windows.Shapes.Ellipse
    $sz = 4 + ($i % 3) * 2.5
    $d.Width = $sz; $d.Height = $sz
    $d.Fill = Brush '#CFE0FF' 0.9
    $d.Opacity = 0
    $petC.Children.Add($d) | Out-Null
    $spouts += @{ El = $d; P = 2.0 + $i * 0.22; X = 96 + (($i % 2) * 2 - 1) * (4 + $i) }
}

# -- 眼睛
$eyesC = New-Object System.Windows.Controls.Canvas
$eyesC.Width = 200; $eyesC.Height = 190
$petC.Children.Add($eyesC) | Out-Null

$eyeL = New-Object System.Windows.Shapes.Ellipse
$eyeL.Width = 15; $eyeL.Height = 19
$eyeL.Fill = Brush $C_DARK
[System.Windows.Controls.Canvas]::SetLeft($eyeL, 74)
[System.Windows.Controls.Canvas]::SetTop($eyeL, 88)
$eyesC.Children.Add($eyeL) | Out-Null

$eyeR = New-Object System.Windows.Shapes.Ellipse
$eyeR.Width = 15; $eyeR.Height = 19
$eyeR.Fill = Brush $C_DARK
[System.Windows.Controls.Canvas]::SetLeft($eyeR, 111)
[System.Windows.Controls.Canvas]::SetTop($eyeR, 88)
$eyesC.Children.Add($eyeR) | Out-Null

foreach ($ex in 74, 111) {
    $g = New-Object System.Windows.Shapes.Ellipse
    $g.Width = 5; $g.Height = 5
    $g.Fill = Brush '#FFFFFF' 0.92
    [System.Windows.Controls.Canvas]::SetLeft($g, $ex + 3)
    [System.Windows.Controls.Canvas]::SetTop($g, 91)
    $eyesC.Children.Add($g) | Out-Null
}

$eyeScale = New-Object System.Windows.Media.ScaleTransform(1, 1)
$eyesC.RenderTransform = $eyeScale
$eyesC.RenderTransformOrigin = [System.Windows.Point]::new(0.5, 0.53)

# -- 眯眼（开心 / 睡觉时替换）
$happyEyes = New-Object System.Windows.Shapes.Path
$happyEyes.Stroke = Brush $C_DARK
$happyEyes.StrokeThickness = 3
$happyEyes.StrokeStartLineCap = 'Round'
$happyEyes.StrokeEndLineCap = 'Round'
$happyEyes.Data = New-Geo {
    param($f)
    $f.StartPoint = [System.Windows.Point]::new(72, 98)
    $f.Segments.Add((Q 81 90 90 98))
    $f.Segments.Add((Q 104 90 113 98))
}
$happyEyes.Visibility = 'Collapsed'
$petC.Children.Add($happyEyes) | Out-Null

# -- 腮红 + 嘴
foreach ($bx in 52, 124) {
    $e = New-Object System.Windows.Shapes.Ellipse
    $e.Width = 22; $e.Height = 11
    $e.Fill = Brush $C_BLUSH 0.5
    $bl2 = New-Object System.Windows.Media.Effects.BlurEffect
    $bl2.Radius = 4
    $e.Effect = $bl2
    [System.Windows.Controls.Canvas]::SetLeft($e, $bx)
    [System.Windows.Controls.Canvas]::SetTop($e, 110)
    $petC.Children.Add($e) | Out-Null
}

$mouth = New-Object System.Windows.Shapes.Path
$mouth.Stroke = Brush '#22347F' 0.85
$mouth.StrokeThickness = 2.6
$mouth.StrokeStartLineCap = 'Round'
$mouth.StrokeEndLineCap = 'Round'
$mouth.Data = New-Geo {
    param($f)
    $f.StartPoint = [System.Windows.Point]::new(92, 116)
    $f.Segments.Add((Q 100 123 108 116))
}
$petC.Children.Add($mouth) | Out-Null


# ---------- 可选：用立绘代替矢量小鲸 ----------
# 四张状态图必须同尺寸（默认 300x300），这样切状态时不会缩放、气泡位置也固定
$script:bubbleBottom = 112
$script:hasSprite = $false
$script:spriteKey = ''
$script:spriteMap = @{}

function Load-Sprite([string]$rel) {
    if (-not $rel) { return $null }
    $sp = Join-Path $script:Dir $rel
    if (-not (Test-Path $sp)) { return $null }
    $b = New-Object System.Windows.Media.Imaging.BitmapImage
    $b.BeginInit()
    $b.UriSource = New-Object System.Uri($sp)
    $b.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $b.EndInit()
    $b.Freeze()
    return $b
}

if ($script:cfg.sprite) {
    $map = @{}
    $map['idle'] = Load-Sprite $script:cfg.sprite
    $map['busy'] = Load-Sprite $script:cfg.spriteBusy
    $map['happy'] = Load-Sprite $script:cfg.spriteHappy
    $map['sleepy'] = Load-Sprite $script:cfg.spriteSleepy
    if (-not $map['idle']) { $map['idle'] = $map['busy'] }
    foreach ($k in 'busy', 'happy', 'sleepy') {
        if (-not $map[$k]) { $map[$k] = $map['idle'] }
    }

    if ($map['idle']) {
        $petC.Children.Clear()
        $petC.Width = 300
        $petC.Height = 300
        [System.Windows.Controls.Canvas]::SetLeft($petC, 0)
        [System.Windows.Controls.Canvas]::SetTop($petC, 124)

        $ground = New-Object System.Windows.Shapes.Ellipse
        $ground.Width = 132
        $ground.Height = 13
        $ground.Fill = Brush '#0D1B45' 0.20
        $gb = New-Object System.Windows.Media.Effects.BlurEffect
        $gb.Radius = 8
        $ground.Effect = $gb
        [System.Windows.Controls.Canvas]::SetLeft($ground, 84)
        [System.Windows.Controls.Canvas]::SetTop($ground, 286)
        $petC.Children.Add($ground) | Out-Null

        $img = New-Object System.Windows.Controls.Image
        $img.Stretch = 'Uniform'
        $sh2 = [double]$script:cfg.spriteHeight
        if ($sh2 -le 0) { $sh2 = 280 }
        $img.Width = $sh2
        $img.Height = $sh2
        [System.Windows.Controls.Canvas]::SetLeft($img, [Math]::Round((300 - $sh2) / 2))
        [System.Windows.Controls.Canvas]::SetTop($img, [Math]::Round(290 - $sh2))
        $petC.Children.Add($img) | Out-Null

        $script:spriteMap = $map
        $script:spriteImg = $img
        $script:spriteGround = $ground
        $script:spriteW = $sh2
        $script:spriteH = $sh2

        function Set-Sprite([string]$key) {
            $bmp = $script:spriteMap[$key]
            if (-not $bmp) { $bmp = $script:spriteMap['idle'] }
            if (-not $bmp) { return }
            if ($script:spriteImg.Source -ne $bmp) { $script:spriteImg.Source = $bmp }
            $script:spriteKey = $key
        }

        Set-Sprite 'idle'
        $script:hasSprite = $true

        # 命中检测：立绘在窗口内的位置 + alpha 缓存，双击只响应点到角色上的位置
        $script:spriteLeft = [Math]::Round((300 - $sh2) / 2)
        $script:spriteTop = 124 + [Math]::Round(290 - $sh2)
        $script:spriteHitmap = $null
        try {
            Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
            $hp = Join-Path $script:Dir $script:cfg.sprite
            if ($hp -and (Test-Path $hp)) { $script:spriteHitmap = New-Object System.Drawing.Bitmap $hp }
        } catch { }

        $fxC = New-Object System.Windows.Controls.Canvas
        $fxC.Width = 300
        $fxC.Height = 400
        $fxC.IsHitTestVisible = $false
        $root.Children.Add($fxC) | Out-Null
        $script:fx = @()
        for ($fi = 0; $fi -lt 7; $fi++) {
            $fb = New-Object System.Windows.Shapes.Ellipse
            $fb.Width = 5; $fb.Height = 5
            $fb.Fill = Brush '#D5E4FF' 1.0
            $fb.Opacity = 0
            $fxC.Children.Add($fb) | Out-Null
            $script:fx += @{ El = $fb; P = 1.0; X = 0; Y = 0; R = 5 }
        }
        $script:fxTimer = 2.5

        # 校准气泡锚点：扫描 idle 立绘找角色头顶（跳过呆毛细梢），
        # 让说话气泡和右键气泡的尾巴尖都正好抵在头顶，换图/spriteHeight 时自动跟随。
        $script:bubbleBottom = 120
        try {
            Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
            $bmpPath = Join-Path $script:Dir $script:cfg.sprite
            if (Test-Path $bmpPath) {
                $cbmp = New-Object System.Drawing.Bitmap $bmpPath
                $iw = $cbmp.Width; $ih = $cbmp.Height
                $headY = -1
                for ($cy = 0; $cy -lt $ih -and $headY -lt 0; $cy++) {
                    $cnt = 0
                    for ($cx = 0; $cx -lt $iw; $cx++) {
                        if ($cbmp.GetPixel($cx, $cy).A -gt 8) { $cnt++ }
                    }
                    if ($cnt -ge ($iw * 0.30)) { $headY = $cy }
                }
                $cbmp.Dispose()
                if ($headY -ge 0) {
                    $scale = $sh2 / $ih
                    $imgTopWin = 124 + [Math]::Round(290 - $sh2)
                    $headTopWin = $imgTopWin + $headY * $scale
                    $script:bubbleBottom = [Math]::Round($headTopWin - 14)
                }
            }
        } catch { }

        Log ('bubble anchor y=' + $script:bubbleBottom)
        $win.Height = 124 + 300 + 8
        $root.Height = $win.Height
        Log ("sprite set: idle={0} busy={1} happy={2} sleepy={3}" -f `
            $script:cfg.sprite, $script:cfg.spriteBusy, $script:cfg.spriteHappy, $script:cfg.spriteSleepy)
    } else {
        Log ('sprite missing: ' + $script:cfg.sprite)
    }
}

# 判断 root 内坐标是否落在角色（立绘非透明区域）上
function Test-SpriteHit([double]$px, [double]$py) {
    if (-not $script:hasSprite -or -not $script:spriteHitmap) { return $true }
    $ix = $px - $script:spriteLeft
    $iy = $py - $script:spriteTop
    if ($ix -lt 0 -or $iy -lt 0 -or $ix -ge $script:spriteW -or $iy -ge $script:spriteH) { return $false }
    $ox = [int]($ix * $script:spriteHitmap.Width / $script:spriteW)
    $oy = [int]($iy * $script:spriteHitmap.Height / $script:spriteH)
    if ($ox -lt 0 -or $oy -lt 0 -or $ox -ge $script:spriteHitmap.Width -or $oy -ge $script:spriteHitmap.Height) { return $false }
    return ($script:spriteHitmap.GetPixel($ox, $oy).A -gt 24)
}

# ---------- 动画变换 ----------
$bodyScale = New-Object System.Windows.Media.ScaleTransform($script:cfg.scale, $script:cfg.scale)
$bodyTrans = New-Object System.Windows.Media.TranslateTransform(0, 0)
$bodyRot   = New-Object System.Windows.Media.RotateTransform(0)
$tg = New-Object System.Windows.Media.TransformGroup
$tg.Children.Add($bodyScale) | Out-Null
$tg.Children.Add($bodyRot) | Out-Null
$tg.Children.Add($bodyTrans) | Out-Null
$petC.RenderTransform = $tg
$petC.RenderTransformOrigin = [System.Windows.Point]::new(0.5, 1.0)

# ---------- 状态机 / 气泡 ----------
#  st: idle | busy | sleepy | happy
$script:t = 0.0
$script:st = 'idle'
$script:stSince = [DateTime]::UtcNow
$script:happyUntil = [DateTime]::UtcNow
$script:doneCount = 0        # 已完成、待查看的任务数
$script:pendingDone = 0      # 本轮轮询新完成的个数
$script:running = $false
$script:openMap = @{}        # 上一轮还在跑 turn 的会话
$script:lastTick = $null
$script:bubbleKind = ''
$script:blinkAt = 2.5
$script:blinkPhase = -1.0
$script:bubbleUntil = -1.0
$script:bubbleAlpha = 0.0
$script:spoutTimer = 3.0
$script:dragging = $false
$script:wanderOn = [bool]$script:cfg.wander
$script:nextWalk = 5.0
$script:targetX = $win.Left
$script:lastStateStamp = 0
$script:lastSpoke = -99

function Show-Say([string]$text, [double]$sec = 5.0) {
    $bubbleTxt.Text = $text
    $bubble.Visibility = 'Visible'
    $bubble.InvalidateMeasure()
    $bubble.Measure([System.Windows.Size]::new(236, [double]::PositiveInfinity))
    $w = [Math]::Ceiling($bubble.DesiredSize.Width)
    $h = [Math]::Ceiling($bubble.DesiredSize.Height)
    if ($w -lt 70) { $w = 70 }
    if ($h -lt 26) { $h = 26 }

    $left = [Math]::Round((300 - $w) / 2)
    [System.Windows.Controls.Canvas]::SetLeft($bubble, $left)
    [System.Windows.Controls.Canvas]::SetTop($bubble, $script:bubbleBottom - $h)
    $bubble.Visibility = 'Visible'

    $cx = [Math]::Round($left + $w / 2)
    $tail.Data = New-Geo {
        param($f)
        $f.StartPoint = [System.Windows.Point]::new($cx - 9, ($script:bubbleBottom - 2))
        $f.Segments.Add((Q $cx ($script:bubbleBottom + 14) ($cx + 9) ($script:bubbleBottom - 2)))
    }
    $tail.Visibility = 'Visible'
    $script:bubbleAlpha = 1.0
    $script:bubbleUntil = $script:t + $sec
    $script:lastSpoke = $script:t
}

function Save-Pos {
    try {
        @{ x = [Math]::Round($win.Left); y = [Math]::Round($win.Top) } |
            ConvertTo-Json | Set-Content (Join-Path $script:Dir 'pet-window.json') -Encoding UTF8
    } catch { }
}
function Say-Random {
    $lines = $script:cfg.lines
    if (-not $lines -or $lines.Count -eq 0) { return }
    $i = Get-Random -Minimum 0 -Maximum $lines.Count
    Show-Say $lines[$i]
}

# ---------- 功能面板（点击拉出） ----------
$actFile = Join-Path $script:Dir 'pet-actions.ps1'
if (Test-Path $actFile) { . $actFile }
if (-not (Get-Command Show-PetActions -ErrorAction SilentlyContinue)) {
    function Show-PetActions { }
}

# ---------- 聊天框 ----------
$chatFile = Join-Path $script:Dir 'pet-chat.ps1'
if (Test-Path $chatFile) { . $chatFile }

# ---------- 状态文件 ----------
function Read-State {
    if (-not (Test-Path $script:StateFile)) { return }
    try {
        $st = Get-Content $script:StateFile -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch { return }

    # 只有 updated 前进时才当成一条新指令（情绪由状态机自己管，状态文件只管说话）
    if (-not $st.updated) { return }
    $u = [double]$st.updated
    if ($u -le $script:lastStateStamp) { return }
    $script:lastStateStamp = $u

    if ($st.name) { $script:cfg.name = [string]$st.name }

    if ($st.message) {
        $ageMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - $u
        if ($ageMs -lt 120000) {
            $dur = 6.0
            if ($null -ne $st.duration -and [double]$st.duration -gt 0) { $dur = [double]$st.duration }
            Show-Say ([string]$st.message) $dur
        }
    }
}

# ---------- DSH 任务状态（读会话 projcache 的 turnOpen） ----------
function Update-DshTasks {
    $dir = Join-Path $env:USERPROFILE '.dsh\storages\session_projcache\sessions'
    $now = [DateTime]::UtcNow
    $raw = @{}
    $live = 0
    $done = 0
    $seen = $false
    if (Test-Path $dir) {
        foreach ($f in Get-ChildItem $dir -File -Filter '*.json' -ErrorAction SilentlyContinue) {
            $seen = $true
            $id = $f.BaseName
            $open = $false
            try {
                $j = Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                $row = $j.record.rows.approvalState
                if ($row -and $row.val) { $open = [bool]$row.val.turnOpen }
            } catch { $open = $false }
            if ($open) {
                $raw[$id] = $true
                # 很久没写入的 turn 不当作正在干活，避免卡住的会话让桌宠一直工作
                if (($now - $f.LastWriteTimeUtc).TotalSeconds -lt 150) { $live++ }
            } elseif ($script:openMap.ContainsKey($id)) {
                $done++
            }
        }
    }
    if (-not $seen) {
        # 老版本没有 projcache：退回“会话文件 7 秒内有写入”
        try {
            $f = Get-ChildItem $script:SessionRoot -Recurse -File -Filter '*.zstd' -ErrorAction SilentlyContinue |
                 Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
            if ($f -and ((Get-Date).ToUniversalTime() - $f.LastWriteTimeUtc).TotalSeconds -lt 7) { $live = 1 }
        } catch { }
    }
    $script:running = ($live -gt 0)
    $script:openMap = $raw
    if ($done -gt 0) {
        $script:pendingDone += $done
        Log ('task completed +' + $done)
    }
}

# ---------- 状态机 ----------
function Set-PetState([string]$s, [DateTime]$now) {
    if ($script:st -eq $s) { return }
    Log ('state: {0} -> {1}' -f $script:st, $s)
    $script:st = $s
    $script:stSince = $now
}

function Show-CompletionBubble([int]$newCount) {
    Log ('completion bubble: new=' + $newCount + ' total=' + $script:doneCount)
    $left = ($script:happyUntil - [DateTime]::UtcNow).TotalSeconds
    if ($left -lt 3) { $left = 3 }
    Show-Say ('存在（{0}）个已完成任务待查看' -f $newCount) $left
    $script:bubbleKind = 'review'
}

function Update-PetState([DateTime]$now) {
    # 1) 任务完成：不管当前在干什么，进开心 / 已经在开心就顺延
    if ($script:pendingDone -gt 0) {
        $new = $script:pendingDone
        $script:doneCount += $new
        $script:pendingDone = 0
        if ($script:st -eq 'happy') {
            $script:happyUntil = $script:happyUntil.AddSeconds(30)
        } else {
            $script:st = 'happy'
            $script:stSince = $now
            $script:happyUntil = $now.AddSeconds(30)
        }
        Log ('completion -> happy (n=' + $script:doneCount + ')')
        Show-CompletionBubble $new
    }

    # 2) 开心到点：有活回工作，没活回待机
    if ($script:st -eq 'happy' -and $now -ge $script:happyUntil) {
        if ($script:running) { Set-PetState 'busy' $now } else { Set-PetState 'idle' $now }
        return
    }
    if ($script:st -eq 'happy') { return }

    # 3) 睡着时有人开工，直接醒
    if ($script:st -eq 'sleepy') {
        if ($script:running) {
            Set-PetState 'busy' $now
            Show-Say '来活了，开工！' 2.5
        }
        return
    }

    # 4) 待机 / 工作 跟随 DSH
    $want = if ($script:running) { 'busy' } else { 'idle' }
    if ($script:st -ne $want) {
        Set-PetState $want $now
        if ($want -eq 'busy' -and ($script:t - $script:lastSpoke) -gt 25) {
            Show-Say '开始干活了，我盯着终端 👀' 4
        }
    }

    # 5) 只有待机连续 3 分钟才休眠；工作状态不睡，进入休眠也不弹气泡
    if ($script:st -eq 'idle' -and ($now - $script:stSince).TotalMinutes -ge 3) {
        Set-PetState 'sleepy' $now
    }
}

function Invoke-PetDoubleClick([DateTime]$now) {
    Log ('double-click in ' + $script:st)
    if ($script:st -eq 'sleepy') {
        if ($script:running) { Set-PetState 'busy' $now } else { Set-PetState 'idle' $now }
        Show-Say '唔…我醒啦' 2
        return
    }
    if ($script:st -eq 'idle') {
        $script:st = 'happy'
        $script:stSince = $now
        $script:happyUntil = $now.AddSeconds(15)
        $script:spoutTimer = 0
        Show-Say '嘿嘿…好舒服 🐋' 3
    }
}

# ---------- 主循环 ----------
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(33)
function Update-Fx([double]$dt) {
    $script:fxTimer -= $dt
    if ($script:fxTimer -le 0) {
        $script:fxTimer = 3.0 + (Get-Random -Minimum 0 -Maximum 260) / 100.0
        foreach ($p in $script:fx) {
            if ($p.P -ge 1) {
                $p.P = 0.0
                $w2 = [Math]::Max(30, $script:spriteW - 50)
                $p.X = $script:spriteLeft + 25 + (Get-Random -Minimum 0 -Maximum ([int]$w2))
                $p.Y = 124 + $script:spriteH - 80
                $p.R = 4 + (Get-Random -Minimum 0 -Maximum 5)
                break
            }
        }
    }
    foreach ($p in $script:fx) {
        if ($p.P -lt 1) {
            $p.P += $dt * 0.40
            $q = [Math]::Min(1.0, $p.P)
            $el = $p.El
            $el.Width = $p.R
            $el.Height = $p.R
            [System.Windows.Controls.Canvas]::SetLeft($el, $p.X + [Math]::Sin($q * 7.0) * 7)
            [System.Windows.Controls.Canvas]::SetTop($el, $p.Y - $q * 120)
            $el.Opacity = [Math]::Sin($q * [Math]::PI) * 0.7
        }
    }
}

function Update-Frame {
    $now = [DateTime]::UtcNow
    if ($script:lastTick) {
        $dt = ($now - $script:lastTick).TotalSeconds
        if ($dt -lt 0.001) { $dt = 0.001 }
        if ($dt -gt 0.25) { $dt = 0.25 }
    } else {
        $dt = 0.033
    }
    $script:lastTick = $now
    $script:t += $dt

    Update-PetState $now
    $mode = $script:st

    # 呼吸 / 摆动
    if ($script:hasSprite) {
        $bodyScale.ScaleX = $script:cfg.scale
        $bodyScale.ScaleY = $script:cfg.scale
        $bodyTrans.Y = 0
        $swayAmp = if ($mode -eq "busy") { 0.7 } elseif ($mode -eq "sleepy") { 0.4 } elseif ($mode -eq "happy") { 1.7 } else { 1.1 }
        $swaySpd = if ($mode -eq "sleepy") { 0.6 } elseif ($mode -eq "happy") { 1.8 } else { 1.15 }
        $bodyRot.Angle = $swayAmp * [Math]::Sin($script:t * $swaySpd)
        $wantKey = if ($mode -eq "busy") { "busy" } elseif ($mode -eq "happy") { "happy" } elseif ($mode -eq "sleepy") { "sleepy" } else { "idle" }
        if ($script:spriteKey -ne $wantKey) { Set-Sprite $wantKey }
        Update-Fx $dt
    } else {
        $breathe = [Math]::Sin($script:t * 2.4)
        $bodyScale.ScaleY = $script:cfg.scale * (1 + 0.035 * $breathe)
        $bodyScale.ScaleX = $script:cfg.scale * (1 - 0.018 * $breathe)
        $amp = if ($script:cfg.bob) { 1.0 } else { 0.0 }
        $floatY = 3.0 * $amp * [Math]::Sin($script:t * 1.5)
        if ($mode -eq "sleepy" -and $amp -gt 0) { $floatY = 5.0 * [Math]::Sin($script:t * 0.9) }
        $bodyTrans.Y = $floatY
        $bodyRot.Angle = 1.6 * $amp * [Math]::Sin($script:t * 1.1)
        if ($mode -eq "happy" -and $amp -gt 0) {
            $bodyTrans.Y = -[Math]::Abs([Math]::Sin($script:t * 7.0)) * 9
        }
    }

    # 眨眼
    $script:blinkAt -= $dt
    if ($script:blinkAt -le 0) {
        $script:blinkPhase = 0.0
        $script:blinkAt = 2.2 + (Get-Random -Minimum 0 -Maximum 350) / 100.0
    }
    if ($script:blinkPhase -ge 0) {
        $script:blinkPhase += $dt
        $p = $script:blinkPhase / 0.17
        if ($p -ge 1) { $script:blinkPhase = -1; $eyeScale.ScaleY = 1 }
        else {
            $v = if ($p -lt 0.5) { 1 - $p * 2 * 0.9 } else { 0.1 + ($p - 0.5) * 2 * 0.9 }
            $eyeScale.ScaleY = [Math]::Max(0.08, $v)
        }
    }
    if ($mode -eq 'sleepy') { $eyeScale.ScaleY = 0.12; $eyeScale.ScaleX = 1.05 }
    elseif ($script:blinkPhase -lt 0) { $eyeScale.ScaleY = 1; $eyeScale.ScaleX = 1 }

    # 眯眼替换
    $smile = ($mode -eq 'happy')
    $happyEyes.Visibility = if ($smile) { 'Visible' } else { 'Collapsed' }
    $eyesC.Visibility = if ($smile) { 'Collapsed' } else { 'Visible' }

    # 喷水
    $script:spoutTimer -= $dt
    if ($script:spoutTimer -le 0) {
        $script:spoutTimer = 3.5 + (Get-Random -Minimum 0 -Maximum 300) / 100.0
        foreach ($s in $spouts) { $s.P = 0.0 }
    }
    foreach ($s in $spouts) {
        if ($s.P -le 1) {
            $s.P += $dt * 0.9
            $p = [Math]::Min(1.0, $s.P)
            $el = $s.El
            [System.Windows.Controls.Canvas]::SetLeft($el, $s.X + $p * 10 * [Math]::Sin($p * 6 + $s.X))
            [System.Windows.Controls.Canvas]::SetTop($el, 46 - $p * 40)
            $el.Opacity = [Math]::Sin($p * [Math]::PI) * 0.9
        }
    }

    # 气泡淡出
    if ($script:bubbleUntil -gt 0 -and $script:t -gt $script:bubbleUntil) {
        $script:bubbleAlpha -= $dt * 3.0
        if ($script:bubbleAlpha -le 0) {
            $script:bubbleAlpha = 0
            $bubble.Visibility = 'Collapsed'
            $tail.Visibility = 'Collapsed'
            $script:bubbleUntil = -1
        }
        $bubble.Opacity = $script:bubbleAlpha
        $tail.Opacity = $script:bubbleAlpha
    } elseif ($script:bubbleAlpha -gt 0.95) {
        $bubble.Opacity = 1; $tail.Opacity = 1
    }

    # 游动
    if ($script:wanderOn -and -not $script:dragging) {
        if ($script:t -gt $script:nextWalk) {
            $script:nextWalk = $script:t + 4.0 + (Get-Random -Minimum 0 -Maximum 600) / 100.0
            $script:targetX = Get-Random -Minimum ([int]$wa.Left + 10) -Maximum ([int]($wa.Right - 310))
        }
        $dx = $script:targetX - $win.Left
        if ([Math]::Abs($dx) -gt 2) {
            $spd = if ($mode -eq 'busy') { 26 } else { 16 }
            $win.Left = $win.Left + ([Math]::Sign($dx) * $spd * $dt)
            $bodyRot.Angle += [Math]::Sign($dx) * 3.0
        }
    }
}

$timer.Add_Tick({
    if ($script:paused -or $script:dragging) { return }
    try { Update-Frame } catch { Log ('tick error: ' + $_.Exception.Message) }
})

[System.Windows.Threading.Dispatcher]::CurrentDispatcher.add_UnhandledException({
    param($s, $e)
    Log ('dispatcher error: ' + $e.Exception.Message)
    $e.Handled = $true
})

# ---------- 交互（拖动：屏幕坐标 + DPI 校正，避免坐标自反馈抖动） ----------
Add-Type -Namespace DshPet -Name Cursor -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
[DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
'@ -ErrorAction SilentlyContinue

function Get-CursorScreen {
    $pt = [DshPet.Cursor+POINT]::new()
    [void][DshPet.Cursor]::GetCursorPos([ref]$pt)
    return $pt
}

$script:dragging = $false
$script:winStart = $null
$script:grabPt = $null
$script:dpiScale = $null
$script:pressed = $false
$script:moved = $false
$script:pressT = 0
$script:clickAt = [DateTime]::MinValue
$script:clickX = 0
$script:clickY = 0

$root.Add_MouseLeftButtonDown({
    param($s, $e)
    $script:pressed = $true
    $script:moved = $false
    $script:pressT = [Environment]::TickCount
    $dpi = [System.Windows.Media.VisualTreeHelper]::GetDpi($win)
    $script:dpiScale = [System.Windows.Point]::new($dpi.DpiScaleX, $dpi.DpiScaleY)
    $script:grabPt = Get-CursorScreen
    $script:winStart = [System.Windows.Point]::new($win.Left, $win.Top)
    $script:dragging = $true
    $root.CaptureMouse() | Out-Null
    $e.Handled = $true
})

$root.Add_MouseMove({
    param($s, $e)
    if (-not $script:dragging) { return }
    $cur = Get-CursorScreen
    if (-not $script:moved) {
        if ([Math]::Abs($cur.X - $script:grabPt.X) -gt 5 -or [Math]::Abs($cur.Y - $script:grabPt.Y) -gt 5) {
            $script:moved = $true
        }
    }
    $sx = if ($script:dpiScale.X -gt 0) { $script:dpiScale.X } else { 1.0 }
    $sy = if ($script:dpiScale.Y -gt 0) { $script:dpiScale.Y } else { 1.0 }
    $win.Left = [Math]::Round($script:winStart.X + ($cur.X - $script:grabPt.X) / $sx)
    $win.Top = [Math]::Round($script:winStart.Y + ($cur.Y - $script:grabPt.Y) / $sy)
    $e.Handled = $true
})

$root.Add_MouseLeftButtonUp({
    param($s, $e)
    $script:dragging = $false
    $root.ReleaseMouseCapture()
    if (-not $script:pressed) { return }
    $script:pressed = $false
    if ($script:moved) { Save-Pos; return }

    # 自己判双击：500ms 内、位置接近的第二次点击；只有点到角色身上才算
    $now = [DateTime]::UtcNow
    $p = $e.GetPosition($root)
    if (-not (Test-SpriteHit $p.X $p.Y)) {
        $script:clickAt = [DateTime]::MinValue
        return
    }
    $dx = [Math]::Abs($p.X - $script:clickX)
    $dy = [Math]::Abs($p.Y - $script:clickY)
    $gap = ($now - $script:clickAt).TotalMilliseconds
    if ($gap -lt 500 -and $dx -lt 12 -and $dy -lt 12) {
        $script:clickAt = [DateTime]::MinValue
        Invoke-PetDoubleClick $now
    } else {
        $script:clickAt = $now
        $script:clickX = $p.X
        $script:clickY = $p.Y
    }
})

# 右键拉出同一套气泡面板
$root.Add_MouseRightButtonUp({
    param($s, $e)
    Show-PetActions
    $e.Handled = $true
})

# 状态轮询
$stateTimer = New-Object System.Windows.Threading.DispatcherTimer
$stateTimer.Interval = [TimeSpan]::FromMilliseconds(700)
$stateTimer.Add_Tick({
    try { Read-State } catch { }
    try { Update-DshTasks } catch { Log ('task poll error: ' + $_.Exception.Message) }
})
$stateTimer.Start()

# 关闭时记住位置
$win.Add_Closed({
    $stateTimer.Stop()
    $timer.Stop()
    try {
        @{ x = [Math]::Round($win.Left); y = [Math]::Round($win.Top) } |
            ConvertTo-Json | Set-Content (Join-Path $script:Dir 'pet-window.json') -Encoding UTF8
    } catch { }
    # 关窗后主动收摊：Close() 本身不会结束 Dispatcher.Run()，
    # 不收摊进程会一直挂着并占住单实例互斥体，下次启动会被无声地顶掉。
    try { [System.Windows.Threading.Dispatcher]::CurrentDispatcher.InvokeShutdown() } catch { }
})

# 恢复上次位置；没有记录或基本在屏幕外时回到右下角
$wp = Join-Path $script:Dir 'pet-window.json'
$placed = $false
if (Test-Path $wp) {
    try {
        $w = Get-Content $wp -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $w.x -and $null -ne $w.y) {
            $win.Left = [double]$w.x
            $win.Top = [double]$w.y
            $placed = $true
        }
    } catch { }
}
$vl = [System.Windows.SystemParameters]::VirtualScreenLeft
$vt = [System.Windows.SystemParameters]::VirtualScreenTop
$vr = $vl + [System.Windows.SystemParameters]::VirtualScreenWidth
$vb = $vt + [System.Windows.SystemParameters]::VirtualScreenHeight
$visW = [Math]::Min($win.Left + $win.Width, $vr) - [Math]::Max($win.Left, $vl)
$visH = [Math]::Min($win.Top + $win.Height, $vb) - [Math]::Max($win.Top, $vt)
if (-not $placed -or $visW -lt 120 -or $visH -lt 120) {
    $wa = [System.Windows.SystemParameters]::WorkArea
    $win.Left = $wa.Right - $win.Width - 18
    $win.Top = $wa.Bottom - $win.Height - 10
}

Update-DshTasks
$script:stSince = [DateTime]::UtcNow
$script:lastTick = $null

Log 'ui built'
$win.Show()
Log 'window shown'

# ---------- 系统关机 / 注销：先把自己关掉，别挡着关机 ----------
try {
    $script:winHwnd = (New-Object System.Windows.Interop.WindowInteropHelper($win)).Handle
    $script:winSrc = [System.Windows.Interop.HwndSource]::FromHwnd($script:winHwnd)
    $script:winHook = [System.Windows.Interop.HwndSourceHook]{
        param($h, $msg, $wParam, $lParam, [ref]$handled)
        if ($msg -eq 0x0011) {                 # WM_QUERYENDSESSION
            Log 'WM_QUERYENDSESSION: allow shutdown'
            $handled.Value = $true
            return [IntPtr]1
        }
        if ($msg -eq 0x0016) {                 # WM_ENDSESSION
            Log ('WM_ENDSESSION: closing pet (wParam=' + $wParam + ')')
            try { $win.Close() } catch { }
            $handled.Value = $true
            return [IntPtr]::Zero
        }
        return [IntPtr]::Zero
    }
    $script:winSrc.AddHook($script:winHook)
} catch {
    Log ('session hook failed: ' + $_.Exception.Message)
}

$timer.Start()
$script:t = 0.0
Show-Say ('我是' + $script:cfg.name + ' 🐋') 5

[System.Windows.Threading.Dispatcher]::Run()