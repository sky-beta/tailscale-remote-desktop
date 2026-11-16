$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$downloads = Join-Path $env:RUNNER_TEMP 'desktop-apps'
$stateDirectory = Join-Path $env:LOCALAPPDATA 'SkyWorkflow'
$statusFile = Join-Path $stateDirectory 'apps-install.status.json'
New-Item -ItemType Directory -Force -Path $downloads, $stateDirectory | Out-Null
$results = @()
$fatalError = $null
$failed = @()

function Set-AppState([string]$Name, [string]$State, [string]$Detail = '') {
    $path = Join-Path $stateDirectory ("app-$Name.json")
    $temporary = "$path.tmp"
    [ordered]@{ name = $Name; state = $State; detail = $Detail; updatedAt = [DateTimeOffset]::Now.ToString('o') } |
        ConvertTo-Json -Compress | Set-Content -LiteralPath $temporary -Encoding utf8
    Move-Item -LiteralPath $temporary -Destination $path -Force
}

try {
    foreach ($name in @('QQ', 'WeChat', 'Bilibili')) { Set-AppState $name '等待安装' }
    $results = @(
        @('QQ', 'WeChat', 'Bilibili') | ForEach-Object -Parallel {
            $name = [string]$_
            $downloadRoot = $using:downloads
            $stateRoot = $using:stateDirectory
            $ErrorActionPreference = 'Stop'
            $ProgressPreference = 'SilentlyContinue'
            function Set-ParallelAppState([string]$State, [string]$Detail = '') {
                $path = Join-Path $stateRoot ("app-$name.json")
                $temporary = "$path.tmp"
                [ordered]@{ name = $name; state = $State; detail = $Detail; updatedAt = [DateTimeOffset]::Now.ToString('o') } |
                    ConvertTo-Json -Compress | Set-Content -LiteralPath $temporary -Encoding utf8
                Move-Item -LiteralPath $temporary -Destination $path -Force
            }
            try {
                Set-ParallelAppState '获取下载地址'
                switch ($name) {
                    'QQ' {
                        $config = Invoke-RestMethod -Uri 'https://cdn-go.cn/qq-web/im.qq.com_new/latest/rainbow/windowsConfig.js' -TimeoutSec 45
                        $match = [regex]::Match([string]$config, 'var params\s*=\s*(\{.*?\})\s*;')
                        if (!$match.Success) { throw 'Tencent QQ download configuration was not found' }
                        $url = [string](($match.Groups[1].Value | ConvertFrom-Json).ntDownloadX64Url)
                        $fileName = 'QQ-latest-x64.exe'
                        $switch = '/s'
                    }
                    'WeChat' {
                        $page = (Invoke-WebRequest -Uri 'https://pc.weixin.qq.com/' -TimeoutSec 45).Content
                        $match = [regex]::Match($page, 'https://dldir1v6\.qq\.com/weixin/Universal/Windows/WeChatWin_[^" ]+\.exe')
                        if (!$match.Success) { throw 'WeChat download link was not found on its official page' }
                        $url = $match.Value
                        $fileName = 'WeChat-latest.exe'
                        $switch = '/S'
                    }
                    'Bilibili' {
                        $page = (Invoke-WebRequest -Uri 'https://app.bilibili.com/index.html' -TimeoutSec 45).Content
                        $match = [regex]::Match($page, '<a[^>]+href="(https://dl\.hdslb\.com/mobile/fixed/bili_win/[^"]+)"[^>]+title="Windows客户端"')
                        if (!$match.Success) { throw 'Bilibili download link was not found on its official page' }
                        $url = $match.Groups[1].Value
                        $fileName = 'Bilibili-latest.exe'
                        $switch = '/S'
                    }
                }
                if ($url -notmatch '^https://(qqdl\.gtimg\.cn|dldir1v6\.qq\.com|dl\.hdslb\.com)/') { throw 'Official download URL host was not accepted' }
                Set-ParallelAppState '下载中'
                $installer = Join-Path $downloadRoot $fileName
                Invoke-WebRequest -Uri $url -OutFile $installer -TimeoutSec 180
                if ((Get-Item -LiteralPath $installer).Length -lt 1MB) { throw 'Installer download was unexpectedly small' }
                $signature = Get-AuthenticodeSignature -FilePath $installer
                if ($signature.Status -ne 'Valid') { throw ('Installer signature status: ' + $signature.Status) }
                Set-ParallelAppState '静默安装中'
                $process = Start-Process -FilePath $installer -ArgumentList $switch -Wait -PassThru -WindowStyle Hidden
                if ($process.ExitCode -notin @(0, 3010)) { throw ('Installer exit code ' + $process.ExitCode) }
                Set-ParallelAppState '完成'
                [pscustomobject]@{ Name = $name; Success = $true; Error = '' }
            } catch {
                Set-ParallelAppState '失败' $_.Exception.Message
                [pscustomobject]@{ Name = $name; Success = $false; Error = $_.Exception.Message }
            }
        } -ThrottleLimit 3
    )

    function Find-QQExecutable {
        $programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
        $roots = @(
            (Join-Path $env:ProgramFiles 'Tencent'),
            (Join-Path $programFilesX86 'Tencent'),
            (Join-Path $env:LOCALAPPDATA 'Programs\Tencent'),
            (Join-Path $env:LOCALAPPDATA 'Tencent')
        ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
        foreach ($root in $roots) {
            $candidate = Get-ChildItem -LiteralPath $root -Filter 'QQ.exe' -File -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -match '\\Tencent\\QQNT\\QQ\.exe$' } |
                Select-Object -First 1 -ExpandProperty FullName
            if ($candidate) { return $candidate }
        }
        return $null
    }

    $qqExe = Find-QQExecutable
    if (!$qqExe) {
        try {
            Set-AppState 'QQ' 'WinGet 静默安装中'
            $winget = Get-Command winget.exe -ErrorAction Stop
            & $winget.Source install --id Tencent.QQ.NT --exact --source winget --silent --disable-interactivity --accept-source-agreements --accept-package-agreements
            if ($LASTEXITCODE -ne 0) { throw ('WinGet exit code ' + $LASTEXITCODE) }
            for ($attempt = 0; $attempt -lt 12 -and !$qqExe; $attempt++) {
                Start-Sleep -Seconds 5
                $qqExe = Find-QQExecutable
            }
            if (!$qqExe) { throw 'QQ NT executable was not found after fallback installation' }
            Set-AppState 'QQ' '完成'
            $results = @($results | Where-Object { $_.Name -ne 'QQ' }) + [pscustomobject]@{ Name = 'QQ'; Success = $true; Error = '' }
            Write-Output ('QQ NT fallback installation verified: ' + $qqExe)
        } catch {
            Set-AppState 'QQ' '失败' $_.Exception.Message
            $results = @($results | Where-Object { $_.Name -ne 'QQ' }) + [pscustomobject]@{ Name = 'QQ'; Success = $false; Error = ('Fallback install: ' + $_.Exception.Message) }
        }
    }

    $failed = @($results | Where-Object { !$_.Success } | ForEach-Object { $_.Name })
    foreach ($result in $results) {
        if ($result.Success) { Write-Output ($result.Name + ' installation completed.') }
        else { Write-Warning ($result.Name + ' installation failed: ' + $result.Error) }
    }
} catch {
    $fatalError = $_.Exception.Message
    $failed = @('installer')
    Write-Error $fatalError
} finally {
    $status = [ordered]@{
        status = if ($fatalError) { 'failed' } else { 'complete' }
        completedAt = [DateTimeOffset]::Now.ToString('o')
        failed = @($failed)
        results = @($results)
        fatalError = $fatalError
    }
    $status | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statusFile -Encoding utf8
}
