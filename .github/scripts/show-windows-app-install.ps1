$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$stateDirectory = Join-Path $env:LOCALAPPDATA 'SkyWorkflow'
$form = New-Object System.Windows.Forms.Form
$form.Text = '应用后台安装'
$form.Size = New-Object System.Drawing.Size(430, 235)
$form.StartPosition = 'CenterScreen'
$form.TopMost = $true
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $true

$title = New-Object System.Windows.Forms.Label
$title.Text = 'QQ、微信和哔哩哔哩正在静默安装'
$title.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 12, [System.Drawing.FontStyle]::Bold)
$title.Location = New-Object System.Drawing.Point(20, 18)
$title.Size = New-Object System.Drawing.Size(380, 30)
[void]$form.Controls.Add($title)

$labels = @{}
$y = 66
foreach ($name in @('QQ', 'WeChat', 'Bilibili')) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = "$name：等待安装"
    $label.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)
    $label.Location = New-Object System.Drawing.Point(26, $y)
    $label.Size = New-Object System.Drawing.Size(365, 27)
    [void]$form.Controls.Add($label)
    $labels[$name] = $label
    $y += 34
}

$footer = New-Object System.Windows.Forms.Label
$footer.Text = '安装器在后台运行；可继续使用桌面。'
$footer.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
$footer.ForeColor = [System.Drawing.Color]::DimGray
$footer.Location = New-Object System.Drawing.Point(26, 176)
$footer.Size = New-Object System.Drawing.Size(370, 24)
[void]$form.Controls.Add($footer)

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.Add_Tick({
    foreach ($name in @('QQ', 'WeChat', 'Bilibili')) {
        $path = Join-Path $stateDirectory ("app-$name.json")
        if (Test-Path -LiteralPath $path) {
            try {
                $state = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
                $detail = if ($state.detail) { " - $($state.detail)" } else { '' }
                $labels[$name].Text = "$name：$($state.state)$detail"
                if ($state.state -eq '完成') { $labels[$name].ForeColor = [System.Drawing.Color]::ForestGreen }
                elseif ($state.state -eq '失败') { $labels[$name].ForeColor = [System.Drawing.Color]::Firebrick }
            } catch {}
        }
    }
    $statusPath = Join-Path $stateDirectory 'apps-install.status.json'
    if (Test-Path -LiteralPath $statusPath) {
        try {
            $status = Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json
            if ($status.status -in @('complete', 'failed')) {
                $footer.Text = if ($status.failed.Count -gt 0) { '安装流程结束，部分项目失败；详情见日志。' } else { '安装全部完成。' }
                $timer.Stop()
                $closeTimer = New-Object System.Windows.Forms.Timer
                $closeTimer.Interval = 20000
                $closeTimer.Add_Tick({ $closeTimer.Stop(); $form.Close() }.GetNewClosure())
                $closeTimer.Start()
            }
        } catch {}
    }
}.GetNewClosure())
$timer.Start()
[void]$form.ShowDialog()
