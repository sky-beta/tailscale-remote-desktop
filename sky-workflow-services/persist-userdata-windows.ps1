param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Restore', 'Save')]
    [string]$Mode
)

$ErrorActionPreference = 'Stop'
$profileRoot = $env:USERPROFILE
$backupRoot = 'Z:\yan\workflow-userdata\windows'

if ($Mode -eq 'Save') {
    New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
} elseif (-not (Test-Path -LiteralPath $backupRoot)) {
    Write-Warning 'AList backup folder is unavailable; app profile restore was skipped.'
    return
}

$profiles = [ordered]@{
    'chrome'          = 'AppData\Local\Google\Chrome\User Data'
    'edge'            = 'AppData\Local\Microsoft\Edge\User Data'
    'firefox-roaming' = 'AppData\Roaming\Mozilla\Firefox'
    'firefox-local'   = 'AppData\Local\Mozilla\Firefox'
    'bilibili-roaming'= 'AppData\Roaming\bilibili'
    'bilibili-local'  = 'AppData\Local\bilibili'
    'bilibili-cn-roam'= 'AppData\Roaming\哔哩哔哩'
    'bilibili-cn-loc' = 'AppData\Local\哔哩哔哩'
    'qqnt-roaming'    = 'AppData\Roaming\Tencent\QQNT'
    'qqnt-local'      = 'AppData\Local\Tencent\QQNT'
    'qq-roaming'      = 'AppData\Roaming\Tencent\QQ'
    'qq-local'        = 'AppData\Local\Tencent\QQ'
    'wechat-roaming'  = 'AppData\Roaming\Tencent\WeChat'
    'wechat-local'    = 'AppData\Local\Tencent\WeChat'
    'qq-documents'    = 'Documents\Tencent Files'
    'wechat-documents'= 'Documents\WeChat Files'
    'weixin-documents'= 'Documents\Weixin Files'
}

if ($Mode -eq 'Save') {
    $processNames = @('chrome', 'msedge', 'firefox', 'QQ', 'WeChat', 'Weixin', 'bilibili', 'BiliBili')
    $running = @(Get-Process -Name $processNames -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero })
    foreach ($proc in $running) {
        try { [void]$proc.CloseMainWindow() } catch {}
    }
    if ($running.Count -gt 0) { Start-Sleep -Seconds 12 }
    foreach ($proc in $running) {
        try {
            $proc.Refresh()
            if (-not $proc.HasExited) {
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
            }
        } catch {}
    }
}

$cacheNames = @('Cache', 'Code Cache', 'GPUCache', 'ShaderCache', 'GrShaderCache', 'DawnCache', 'Crashpad')
$copied = 0
foreach ($entry in $profiles.GetEnumerator()) {
    $localPath = Join-Path $profileRoot $entry.Value
    $backupPath = Join-Path $backupRoot $entry.Key
    if ($Mode -eq 'Restore') {
        if (-not (Test-Path -LiteralPath $backupPath)) { continue }
        $source = $backupPath
        $destination = $localPath
    } else {
        if (-not (Test-Path -LiteralPath $localPath)) { continue }
        $source = $localPath
        $destination = $backupPath
        New-Item -ItemType Directory -Force -Path $destination | Out-Null
    }

    New-Item -ItemType Directory -Force -Path $destination | Out-Null
    & robocopy.exe $source $destination /E /Z /R:2 /W:2 /COPY:DAT /DCOPY:DAT /XJ /FFT /XD $cacheNames /NFL /NDL /NJH /NJS /NP
    $code = $LASTEXITCODE
    if ($code -ge 8) {
        Write-Warning ("Profile copy failed for " + $entry.Key + " (robocopy " + $code + ").")
    } else {
        $copied++
    }
}

if ($Mode -eq 'Restore') {
    $packageRoot = Join-Path $profileRoot 'AppData\Local\Packages'
    if (Test-Path -LiteralPath $packageRoot) {
        Get-ChildItem -LiteralPath $packageRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '(?i)(bilibili|哔哩哔哩|tencent|wechat|weixin)' } |
            ForEach-Object {
                $target = Join-Path $backupRoot ('packages\' + $_.Name)
                if (Test-Path -LiteralPath $target) {
                    & robocopy.exe $target $_.FullName /E /Z /R:2 /W:2 /COPY:DAT /DCOPY:DAT /XJ /FFT /XD $cacheNames /NFL /NDL /NJH /NJS /NP
                    if ($LASTEXITCODE -ge 8) { Write-Warning ("Package profile restore failed for " + $_.Name) }
                }
            }
    }
} else {
    $packageRoot = Join-Path $profileRoot 'AppData\Local\Packages'
    if (Test-Path -LiteralPath $packageRoot) {
        Get-ChildItem -LiteralPath $packageRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '(?i)(bilibili|哔哩哔哩|tencent|wechat|weixin)' } |
            ForEach-Object {
                $target = Join-Path $backupRoot ('packages\' + $_.Name)
                New-Item -ItemType Directory -Force -Path $target | Out-Null
                & robocopy.exe $_.FullName $target /E /Z /R:2 /W:2 /COPY:DAT /DCOPY:DAT /XJ /FFT /XD $cacheNames /NFL /NDL /NJH /NJS /NP
                if ($LASTEXITCODE -ge 8) { Write-Warning ("Package profile save failed for " + $_.Name) }
            }
    }
}

if ($Mode -eq 'Restore') {
    foreach ($policyPath in @('HKCU:\Software\Policies\Google\Chrome', 'HKCU:\Software\Policies\Microsoft\Edge')) {
        New-Item -Path $policyPath -Force | Out-Null
        New-ItemProperty -Path $policyPath -Name 'RestoreOnStartup' -PropertyType DWord -Value 1 -Force | Out-Null
    }
    $firefoxProfiles = Join-Path $profileRoot 'AppData\Roaming\Mozilla\Firefox\Profiles'
    if (Test-Path -LiteralPath $firefoxProfiles) {
        Get-ChildItem -LiteralPath $firefoxProfiles -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $userJs = Join-Path $_.FullName 'user.js'
            $lines = @()
            if (Test-Path -LiteralPath $userJs) {
                $lines = @(Get-Content -LiteralPath $userJs -ErrorAction SilentlyContinue |
                    Where-Object { $_ -notmatch 'browser\.(startup\.page|sessionstore\.resume_from_crash)' })
            }
            $lines += 'user_pref("browser.startup.page", 3);'
            $lines += 'user_pref("browser.sessionstore.resume_from_crash", true);'
            Set-Content -LiteralPath $userJs -Value $lines -Encoding utf8
        }
    }
}

Write-Host ($Mode + ' complete. Profile groups copied: ' + $copied)
