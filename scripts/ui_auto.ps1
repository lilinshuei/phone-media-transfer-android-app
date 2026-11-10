param(
    [Parameter(Mandatory = $true)][string]$Adb,
    [Parameter(Mandatory = $true)][ValidateSet('dump', 'tap', 'type', 'scrollfind', 'back', 'home', 'wait')][string]$Action,
    [string]$Label,
    [string]$Text,
    [int]$MaxScroll = 8,
    [int]$TimeoutSec = 20
)
$ErrorActionPreference = 'Continue'
$xmlPath = Join-Path $env:TEMP 'ui_auto.xml'

function Get-UiXml {
    & $Adb shell "uiautomator dump /sdcard/ui_auto.xml" 2>&1 | Out-Null
    & $Adb pull "/sdcard/ui_auto.xml" $xmlPath 2>&1 | Out-Null
    if (Test-Path $xmlPath) {
        try { return [System.IO.File]::ReadAllText($xmlPath, [System.Text.Encoding]::UTF8) } catch { return '' }
    }
    return ''
}

function Get-Nodes([string]$xml) {
    $list = @()
    if (-not $xml) { return $list }
    foreach ($m in [regex]::Matches($xml, '<node[^>]*/>')) {
        $t = $m.Value
        $tx = [regex]::Match($t, 'text="([^"]*)"').Groups[1].Value
        $d = [regex]::Match($t, 'content-desc="([^"]*)"').Groups[1].Value
        $b = [regex]::Match($t, 'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')
        if ($b.Success) {
            $list += [pscustomobject]@{
                Text = $tx; Desc = $d
                X = [int]((([int]$b.Groups[1].Value) + ([int]$b.Groups[3].Value)) / 2)
                Y = [int]((([int]$b.Groups[2].Value) + ([int]$b.Groups[4].Value)) / 2)
            }
        }
    }
    return $list
}

function Find-Node($nodes, [string]$label) {
    $hit = $nodes | Where-Object { $_.Text -eq $label -or $_.Desc -eq $label } | Select-Object -First 1
    if ($hit) { return $hit }
    $hit = $nodes | Where-Object { $_.Text -like "*$label*" -or $_.Desc -like "*$label*" } | Select-Object -First 1
    return $hit
}

switch ($Action) {
    'dump' {
        $nodes = Get-Nodes (Get-UiXml)
        $visible = @($nodes | Where-Object { $_.Text -or $_.Desc })
        Write-Output ("NODES=" + $nodes.Count + " WITH_TEXT=" + $visible.Count)
        if ($visible.Count -eq 0) {
            Write-Output "（当前界面没有可读文字，可能停在桌面/锁屏，或该界面自绘无无障碍节点）"
        }
        $visible | ForEach-Object {
            "{0},{1}`t{2}`t{3}" -f $_.X, $_.Y, $_.Text, $_.Desc
        }
    }
    'tap' {
        if (-not $Label) { Write-Output 'MISSING_LABEL'; exit 2 }
        $n = Find-Node (Get-Nodes (Get-UiXml)) $Label
        if (-not $n) { Write-Output "NOT_FOUND: $Label"; exit 3 }
        & $Adb shell "input tap $($n.X) $($n.Y)" 2>&1 | Out-Null
        Write-Output ("TAPPED: " + $n.Text + $n.Desc + " @ " + $n.X + "," + $n.Y)
    }
    'type' {
        if (-not $Text) { Write-Output 'MISSING_TEXT'; exit 2 }
        # 安全约束：文本将进入设备端 shell 命令，必须先做严格白名单过滤。
        # 允许：字母、数字、空格、常见中文、- _ . , : @ + = / % 与 #?
        # 拒绝（会被剔除）：; & | ` $ ( ) < > \ " ' 以及所有控制字符
        $allowed = '[^A-Za-z0-9\s\u4e00-\u9fa5_\-\.,:@\+=/%#?]'
        $filtered = [regex]::Replace($Text, $allowed, '')
        if ($filtered -ne $Text) {
            Write-Output 'REJECTED_UNSAFE_CHARS: 已剔除 shell 元字符后再输入'
            $Text = $filtered
        }
        if ([string]::IsNullOrWhiteSpace($Text)) { Write-Output 'EMPTY_AFTER_FILTER'; exit 2 }
        # 空格转成 %s 供 input text 识别；单引号已被过滤，参数无法逃逸出引号
        $safe = $Text -replace ' ', '%s'
        & $Adb shell "input text '$safe'" 2>&1 | Out-Null
        Write-Output ("TYPED: " + $Text)
    }
    'scrollfind' {
        if (-not $Label) { Write-Output 'MISSING_LABEL'; exit 2 }
        for ($i = 0; $i -le $MaxScroll; $i++) {
            $n = Find-Node (Get-Nodes (Get-UiXml)) $Label
            if ($n) {
                & $Adb shell "input tap $($n.X) $($n.Y)" 2>&1 | Out-Null
                Write-Output ("FOUND_AT_SCROLL_" + $i + ": " + $n.X + "," + $n.Y)
                exit 0
            }
            & $Adb shell "input swipe 540 1900 540 700 300" 2>&1 | Out-Null
            Start-Sleep -Milliseconds 700
        }
        Write-Output "NOT_FOUND_AFTER_SCROLL: $Label"
        exit 3
    }
    'wait' {
        if (-not $Label) { Write-Output 'MISSING_LABEL'; exit 2 }
        $deadline = (Get-Date).AddSeconds($TimeoutSec)
        while ((Get-Date) -lt $deadline) {
            $n = Find-Node (Get-Nodes (Get-UiXml)) $Label
            if ($n) { Write-Output ("APPEARED: " + $n.X + "," + $n.Y); exit 0 }
            Start-Sleep -Milliseconds 800
        }
        Write-Output "TIMEOUT: $Label"
        exit 4
    }
    'back' { & $Adb shell "input keyevent 4" 2>&1 | Out-Null; Write-Output 'BACK' }
    'home' { & $Adb shell "input keyevent 3" 2>&1 | Out-Null; Write-Output 'HOME' }
}
