# src of install.exe, convert to exe with ps2exe
# https://github.com/MScholtes/PS2EXE
# https://t.me/ZGQinc

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ProgressPreference = 'SilentlyContinue'

Write-Output "安装 Spotify 并使用 SpotX 修补 ..."

iex "& { $(iwr -useb 'https://raw.githubusercontent.com/SpotX-Official/spotx-official.github.io/main/run.ps1') } -confirm_uninstall_ms_spoti -sp-over -new_theme -block_update_on -podcasts_on -dev -exp_spotify -adsections_off -cl 20000 -topsearchbar -newFullscreenMode -canvasHome -rightsidebarcolor -hide_col_icon_off"

Write-Output "安装 Spicetify ..."

iwr -useb https://raw.githubusercontent.com/spicetify/spicetify-cli/master/install.ps1 | iex

Write-Output "安装 custom-apps 和 extensions ..."

Write-Output "下载 Enhancify ..."

# iwr -useb https://github.com/ECE49595-Team-6/EnhancifyInstall/releases/latest/download/install.ps1 | iex

$apiUrl = "https://api.github.com/repos/ECE49595-Team-6/EnhancifyInstall/releases/latest"
$downloadPath = "$env:APPDATA\spicetify\CustomApps\Enhancify"
$response = Invoke-RestMethod -Uri $apiUrl
$downloadUrl = $response.assets[0].browser_download_url

if (-not $downloadUrl) {
    Write-Error "错误：未找到 Enhancify 的 release 下载链接。"
    exit
}

$tempZipPath = "$env:TEMP\Enhancify.zip"
Invoke-WebRequest -Uri $downloadUrl -OutFile $tempZipPath
New-Item -ItemType Directory -Path $downloadPath -Force | Out-Null
Expand-Archive -Path $tempZipPath -DestinationPath $downloadPath -Force
Remove-Item -Path $tempZipPath

Write-Output "下载 stats ..."

$apiUrl = "https://api.github.com/repos/harbassan/spicetify-apps/releases"
$downloadPath = "$env:APPDATA\spicetify\CustomApps"
$response = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing
$downloadUrl = $response.assets | ForEach-Object { $_.browser_download_url } | Where-Object { $_ -match "stats.*\.zip$" } | Select-Object -First 1

if (-not $downloadUrl) {
    Write-Error "错误：未找到 stats 的 release 下载链接。"
    exit
}

$tempZipPath = "$env:TEMP\spicetify-stats.zip"
Invoke-WebRequest -Uri $downloadUrl -OutFile $tempZipPath -UseBasicParsing
Expand-Archive -Path $tempZipPath -DestinationPath $downloadPath -Force
Remove-Item -Path $tempZipPath

Write-Output "配置 Spicetify ..."

spicetify config custom_apps Enhancify
spicetify config custom_apps stats
spicetify config custom_apps lyrics-plus
spicetify config extensions bookmark.js
spicetify config extensions fullAppDisplay.js
spicetify config extensions keyboardShortcut.js
spicetify config extensions loopyLoop.js
spicetify config extensions popupLyrics.js
spicetify config extensions shuffle+.js
spicetify config extensions trashbin.js
spicetify config extensions webnowplaying.js
spicetify config sidebar_config 0
spicetify apply

Write-Output "安装完成。"