# =====================================================================
#  pet-chat.ps1 · 桌宠内聊天框（输入 + 输出都在这一个气泡窗里）
#  由 pet.ps1 在 pet-actions.ps1 之后 dot-source 引入。
#  走 DSH 同一个网关（tokendance，OpenAI 兼容），不消耗 DeepSeek 官方 token 余额。
# =====================================================================

$script:chatHistory  = @()
$script:chatPopup    = $null
$script:chatList     = $null
$script:chatScroll   = $null
$script:chatInput    = $null
$script:chatSendBtn  = $null
$script:chatBusy     = $false
$script:chatRunspace = $null
$script:chatPs       = $null
$script:chatHandle   = $null
$script:chatTimer    = $null
$script:chatPendingTb = $null

function Chat-Brush([string]$hex, [double]$op = 1.0) {
    $c = [System.Windows.Media.ColorConverter]::ConvertFromString($hex)
    $b = New-Object System.Windows.Media.SolidColorBrush($c)
    $b.Opacity = $op
    return $b
}

function Get-ChatKey {
    if ($script:cfg.chatKey) { return [string]$script:cfg.chatKey }
    $cred = Join-Path $env:USERPROFILE '.dsh\.credentials.yaml'
    if (-not (Test-Path $cred)) { return $null }
    foreach ($line in Get-Content $cred -ErrorAction SilentlyContinue) {
        if ($line -match '^\s*TOKENDANCE_API_KEY\s*:\s*(\S+)') { return $matches[1] }
    }
    return $null
}

function Get-ChatUrl {
    if ($script:cfg.chatUrl) { return [string]$script:cfg.chatUrl }
    return 'https://tokendance.space/gateway/v1/chat/completions'
}

function Get-ChatModel {
    if ($script:cfg.chatModel) { return [string]$script:cfg.chatModel }
    return 'deepseek-v4.1-flash-1017'
}

function Get-ChatSystem {
    if ($script:cfg.chatSystem) { return [string]$script:cfg.chatSystem }
    return '你是小鲸，一只住在 Windows 桌面上的 DeepSeek 桌宠。用简短、自然、可爱的中文回答，口语化，两三句话以内，不要用 Markdown 列表或代码块。'
}

# ---------- 消息气泡 ----------
function Add-ChatBubble([string]$role, [string]$text) {
    $wrap = New-Object System.Windows.Controls.Border
    $wrap.CornerRadius = [System.Windows.CornerRadius]::new(11)
    $wrap.Padding = [System.Windows.Thickness]::new(10, 6, 10, 7)
    $wrap.Margin = [System.Windows.Thickness]::new(4, 3, 4, 3)
    $wrap.MaxWidth = 252

    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = $text
    $tb.TextWrapping = 'Wrap'
    $tb.FontSize = 12.5
    $tb.LineHeight = 19
    $tb.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI, Segoe UI')

    if ($role -eq 'user') {
        $wrap.Background = Chat-Brush '#4D6BFE' 1.0
        $tb.Foreground = [System.Windows.Media.Brushes]::White
    } elseif ($role -eq 'system') {
        $wrap.Background = [System.Windows.Media.Brushes]::Transparent
        $tb.Foreground = Chat-Brush '#8A97BD' 1.0
        $tb.FontSize = 11.5
    } else {
        $wrap.Background = Chat-Brush '#EEF3FF' 1.0
        $tb.Foreground = Chat-Brush '#16306B' 1.0
    }
    $wrap.Child = $tb

    $row = New-Object System.Windows.Controls.StackPanel
    if ($role -eq 'user') { $row.HorizontalAlignment = 'Right' } else { $row.HorizontalAlignment = 'Left' }
    $row.Children.Add($wrap) | Out-Null
    $script:chatList.Children.Add($row) | Out-Null
    $script:chatScroll.ScrollToEnd()
    return $tb
}

function Set-ChatPending([string]$text) {
    if ($script:chatPendingTb) { $script:chatPendingTb.Text = $text }
    $script:chatScroll.ScrollToEnd()
}

# ---------- 面板 ----------
function Initialize-PetChat {
    if ($script:chatPopup) { return }

    $border = New-Object System.Windows.Controls.Border
    $border.Width = 320
    $border.CornerRadius = [System.Windows.CornerRadius]::new(16)
    $border.Background = Chat-Brush '#FCFEFF' 1.0
    $border.BorderBrush = Chat-Brush '#C9D8FF' 1.0
    $border.BorderThickness = [System.Windows.Thickness]::new(1)
    $border.Padding = [System.Windows.Thickness]::new(10, 8, 10, 10)

    $sh = New-Object System.Windows.Media.Effects.DropShadowEffect
    $sh.BlurRadius = 22
    $sh.ShadowDepth = 4
    $sh.Opacity = 0.26
    $sh.Color = [System.Windows.Media.ColorConverter]::ConvertFromString('#2A43D8')
    $border.Effect = $sh

    $dock = New-Object System.Windows.Controls.DockPanel

    # 标题栏
    $head = New-Object System.Windows.Controls.DockPanel
    $head.Height = 26
    [System.Windows.Controls.DockPanel]::SetDock($head, 'Top')

    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = '和小鲸聊天'
    $title.FontSize = 12.5
    $title.FontWeight = 'SemiBold'
    $title.Foreground = Chat-Brush '#2A43D8' 1.0
    $title.VerticalAlignment = 'Center'
    [System.Windows.Controls.DockPanel]::SetDock($title, 'Left')

    $close = New-Object System.Windows.Controls.TextBlock
    $close.Text = '✕'
    $close.FontSize = 12
    $close.Width = 20
    $close.TextAlignment = 'Right'
    $close.Cursor = [System.Windows.Input.Cursors]::Hand
    $close.Foreground = Chat-Brush '#8A97BD' 1.0
    $close.VerticalAlignment = 'Center'
    [System.Windows.Controls.DockPanel]::SetDock($close, 'Right')
    $close.Add_MouseLeftButtonUp({ param($s, $e) Close-PetChat; $e.Handled = $true })

    $clear = New-Object System.Windows.Controls.TextBlock
    $clear.Text = '清空'
    $clear.FontSize = 11
    $clear.Width = 32
    $clear.TextAlignment = 'Right'
    $clear.Cursor = [System.Windows.Input.Cursors]::Hand
    $clear.Foreground = Chat-Brush '#8A97BD' 1.0
    $clear.VerticalAlignment = 'Center'
    [System.Windows.Controls.DockPanel]::SetDock($clear, 'Right')
    $clear.Add_MouseLeftButtonUp({ param($s, $e) Clear-PetChat; $e.Handled = $true })

    $head.Children.Add($title) | Out-Null
    $head.Children.Add($clear) | Out-Null
    $head.Children.Add($close) | Out-Null

    # 输入区
    $inputRow = New-Object System.Windows.Controls.DockPanel
    $inputRow.Height = 36
    [System.Windows.Controls.DockPanel]::SetDock($inputRow, 'Bottom')

    $send = New-Object System.Windows.Controls.Border
    $send.Width = 52
    $send.CornerRadius = [System.Windows.CornerRadius]::new(10)
    $send.Background = Chat-Brush '#4D6BFE' 1.0
    $send.Cursor = [System.Windows.Input.Cursors]::Hand
    $send.Margin = [System.Windows.Thickness]::new(6, 0, 0, 0)
    [System.Windows.Controls.DockPanel]::SetDock($send, 'Right')
    $sendTxt = New-Object System.Windows.Controls.TextBlock
    $sendTxt.Text = '发送'
    $sendTxt.FontSize = 12.5
    $sendTxt.Foreground = [System.Windows.Media.Brushes]::White
    $sendTxt.HorizontalAlignment = 'Center'
    $sendTxt.VerticalAlignment = 'Center'
    $send.Child = $sendTxt
    $send.Add_MouseLeftButtonUp({ param($s, $e) Send-ChatFromBox; $e.Handled = $true })

    $inputBox = New-Object System.Windows.Controls.Border
    $inputBox.CornerRadius = [System.Windows.CornerRadius]::new(10)
    $inputBox.Background = Chat-Brush '#F2F6FF' 1.0
    $inputBox.BorderBrush = Chat-Brush '#D5E1FA' 1.0
    $inputBox.BorderThickness = [System.Windows.Thickness]::new(1)
    $inputBox.Padding = [System.Windows.Thickness]::new(9, 0, 9, 0)

    $tb = New-Object System.Windows.Controls.TextBox
    $tb.BorderThickness = [System.Windows.Thickness]::new(0)
    $tb.Background = [System.Windows.Media.Brushes]::Transparent
    $tb.FontSize = 12.5
    $tb.VerticalContentAlignment = 'Center'
    $tb.Foreground = Chat-Brush '#16306B' 1.0
    $tb.CaretBrush = Chat-Brush '#2A43D8' 1.0
    $tb.Add_KeyDown({
        param($s, $e)
        if ($e.Key -eq [System.Windows.Input.Key]::Enter) {
            $e.Handled = $true
            Send-ChatFromBox
        } elseif ($e.Key -eq [System.Windows.Input.Key]::Escape) {
            $e.Handled = $true
            Close-PetChat
        }
    })
    $inputBox.Child = $tb

    $inputRow.Children.Add($send) | Out-Null
    $inputRow.Children.Add($inputBox) | Out-Null

    # 消息区
    $stack = New-Object System.Windows.Controls.StackPanel
    $scroll = New-Object System.Windows.Controls.ScrollViewer
    $scroll.VerticalScrollBarVisibility = 'Auto'
    $scroll.HorizontalScrollBarVisibility = 'Disabled'
    $scroll.Height = 330
    $scroll.Margin = [System.Windows.Thickness]::new(0, 6, 0, 8)
    $scroll.Content = $stack

    $dock.Children.Add($head) | Out-Null
    $dock.Children.Add($inputRow) | Out-Null
    $dock.Children.Add($scroll) | Out-Null
    $border.Child = $dock

    $popup = New-Object System.Windows.Controls.Primitives.Popup
    $popup.AllowsTransparency = $true
    $popup.StaysOpen = $false
    $popup.Placement = 'Absolute'
    $popup.Child = $border

    $script:chatPopup  = $popup
    $script:chatList   = $stack
    $script:chatScroll = $scroll
    $script:chatInput  = $tb
    $script:chatSendBtn = $send

    $script:chatTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:chatTimer.Interval = [TimeSpan]::FromMilliseconds(200)
    $script:chatTimer.Add_Tick({ Poll-Chat })
}

function Position-PetChat {
    $wa = [System.Windows.SystemParameters]::WorkArea
    $pw = 320.0
    $ph = 420.0
    $wx = [double]$script:actWin.Left
    $wy = [double]$script:actWin.Top
    $ww = if ($script:actWin.ActualWidth -gt 50) { [double]$script:actWin.ActualWidth } else { 300.0 }
    $wh = if ($script:actWin.ActualHeight -gt 50) { [double]$script:actWin.ActualHeight } else { 432.0 }

    $ax = $wx + $ww / 2.0
    $ay = $wy + [double]$script:bubbleBottom + 14.0

    $left = $ax - $pw / 2.0
    $top = $ay - $ph - 8.0
    if ($top -lt $wa.Top + 4) {
        # 上方放不下：贴角色右侧，放不下再放左侧，最后兜底下方
        if (($wx + $ww + $pw + 6.0) -le ($wa.Right - 6)) {
            $left = $wx + $ww + 6.0
            $top = $wy + 40.0
        } elseif (($wx - $pw - 6.0) -ge ($wa.Left + 6)) {
            $left = $wx - $pw - 6.0
            $top = $wy + 40.0
        } else {
            $left = $ax - $pw / 2.0
            $top = $wy + $wh + 6.0
        }
    }
    if ($left -lt $wa.Left + 6) { $left = $wa.Left + 6 }
    if ($left + $pw -gt $wa.Right - 6) { $left = $wa.Right - 6 - $pw }
    if ($top -lt $wa.Top + 4) { $top = $wa.Top + 4 }
    if ($top + $ph -gt $wa.Bottom - 6) { $top = $wa.Bottom - 6 - $ph }

    $script:chatPopup.HorizontalOffset = $left
    $script:chatPopup.VerticalOffset = $top
}

function Show-PetChat {
    Initialize-PetChat
    Position-PetChat
    if (-not $script:chatPopup.IsOpen) {
        if ($script:chatList.Children.Count -eq 0) {
            Add-ChatBubble 'system' '聊点什么？我在这儿。' | Out-Null
        }
        $script:chatPopup.IsOpen = $true
    }
    try {
        $script:chatInput.Focus() | Out-Null
        [System.Windows.Input.Keyboard]::Focus($script:chatInput) | Out-Null
    } catch { }
}

function Close-PetChat {
    if ($script:chatPopup -and $script:chatPopup.IsOpen) { $script:chatPopup.IsOpen = $false }
}

function Clear-PetChat {
    $script:chatHistory = @()
    $script:chatList.Children.Clear()
    Add-ChatBubble 'system' '重新开始，说吧。' | Out-Null
}

# ---------- 发送 / 接收 ----------
function Send-ChatFromBox {
    if (-not $script:chatInput) { return }
    if ($script:chatBusy) { return }
    $text = $script:chatInput.Text
    if (-not $text -or -not $text.Trim()) { return }
    $script:chatInput.Text = ''
    Send-ChatMessage $text.Trim()
}

function Send-ChatMessage([string]$text) {
    if ($script:chatBusy) { return }

    $key = Get-ChatKey
    if (-not $key) {
        Add-ChatBubble 'system' '没找到 TOKENDANCE_API_KEY，翻一下 ~/.dsh/.credentials.yaml。' | Out-Null
        return
    }

    Add-ChatBubble 'user' $text | Out-Null
    $script:chatHistory += @{ role = 'user'; content = $text }

    $script:chatPendingTb = Add-ChatBubble 'assistant' '…'
    $script:chatBusy = $true

    $msgs = @()
    $msgs += @{ role = 'system'; content = (Get-ChatSystem) }
    foreach ($m in ($script:chatHistory | Select-Object -Last 12)) { $msgs += @{ role = $m.role; content = $m.content } }
    $body = @{ model = (Get-ChatModel); messages = $msgs; stream = $false; max_tokens = 800; temperature = 0.7 } |
        ConvertTo-Json -Depth 8 -Compress

    if (-not $script:chatRunspace) {
        $script:chatRunspace = [runspacefactory]::CreateRunspace()
        $script:chatRunspace.ApartmentState = 'MTA'
        $script:chatRunspace.Open()
    }

    $script:chatPs = [powershell]::Create()
    $script:chatPs.Runspace = $script:chatRunspace
    [void]$script:chatPs.AddScript({
        param($url, $key, $json)
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $r = Invoke-RestMethod -Uri $url -Method Post -Headers @{ Authorization = "Bearer $key" } `
                -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec 120
            if ($r.choices -and $r.choices[0].message) { return [string]$r.choices[0].message.content }
            return 'ERR::返回格式不对：' + ($r | ConvertTo-Json -Compress -Depth 4)
        } catch {
            return 'ERR::' + $_.Exception.Message
        }
    }).AddArgument((Get-ChatUrl)).AddArgument($key).AddArgument($body)

    $script:chatHandle = $script:chatPs.BeginInvoke()
    $script:chatTimer.Start()
    Log ('chat request: ' + $text.Length + ' chars')
}

function Poll-Chat {
    if (-not $script:chatHandle) { return }
    if (-not $script:chatHandle.IsCompleted) { return }

    $out = ''
    try {
        $res = $script:chatPs.EndInvoke($script:chatHandle)
        $out = [string]($res | Select-Object -First 1)
    } catch {
        $out = 'ERR::' + $_.Exception.Message
    }
    try { $script:chatPs.Dispose() } catch { }
    $script:chatPs = $null
    $script:chatHandle = $null
    $script:chatBusy = $false
    $script:chatTimer.Stop()

    if ($out -like 'ERR::*') {
        Log ('chat error: ' + $out.Substring(5))
        Set-ChatPending ('😵 ' + $out.Substring(5))
        return
    }
    if (-not $out) { $out = '（没说话，再问一次？）' }
    Log ('chat reply: ' + $out.Length + ' chars')
    Set-ChatPending $out
    $script:chatHistory += @{ role = 'assistant'; content = $out }
}
