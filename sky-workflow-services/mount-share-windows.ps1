$ErrorActionPreference = 'Stop'
if (!$env:SHARED_ALIST_USERNAME -or !$env:SHARED_ALIST_PASSWORD) { throw 'Missing WebDAV credentials' }
$msi=Join-Path $env:RUNNER_TEMP 'winfsp.msi'
$zip=Join-Path $env:RUNNER_TEMP 'rclone-windows.zip'
$p=Start-Process msiexec.exe -ArgumentList @('/i',('"'+$msi+'"'),'/qn','/norestart') -Wait -PassThru
if($p.ExitCode -ne 0){throw "WinFsp installer exit $($p.ExitCode)"}
$dir=Join-Path $env:LOCALAPPDATA 'SkyShare'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Expand-Archive -LiteralPath $zip -DestinationPath $dir -Force
$rc=(Get-ChildItem $dir -Recurse -Filter rclone.exe | Select-Object -First 1).FullName
if(!$rc){throw 'rclone executable missing'}
$env:RCLONE_CONFIG_SKYSHARE_TYPE='webdav'
$env:RCLONE_CONFIG_SKYSHARE_URL='https://striking-rebecka-wxj3837-0de393a2.koyeb.app/alist/dav/'
$env:RCLONE_CONFIG_SKYSHARE_VENDOR='other'
$env:RCLONE_CONFIG_SKYSHARE_USER=$env:SHARED_ALIST_USERNAME
$env:RCLONE_CONFIG_SKYSHARE_PASS=(& $rc obscure $env:SHARED_ALIST_PASSWORD)
$log=Join-Path $dir 'rclone.log'
if(-not(Test-Path 'Z:\')) {
  $proc=Start-Process -FilePath $rc -WindowStyle Hidden -ArgumentList @('mount','skyshare:','Z:','--vfs-cache-mode','writes','--log-file',('"'+$log+'"')) -PassThru
  for($i=0;$i -lt 30;$i++){if(Test-Path 'Z:\'){break};if($proc.HasExited){throw 'rclone mount exited'};Start-Sleep 2}
}
if(-not(Test-Path 'Z:\')){throw 'WebDAV drive did not appear'}
$desktop=[Environment]::GetFolderPath('Desktop')
$shortcut=(New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $desktop 'AList共享.lnk'))
$shortcut.TargetPath='Z:\'
$shortcut.Save()
Write-Output 'Shared AList drive mounted and desktop shortcut created.'
