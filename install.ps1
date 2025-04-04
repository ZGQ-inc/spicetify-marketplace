# https://t.me/ZGQinc

Write-Output "Installing Spotify modfied by SpotX..."

iex "& { $(iwr -useb 'https://raw.githubusercontent.com/SpotX-Official/spotx-official.github.io/main/run.ps1') } -new_theme -block_update_on -podcasts_on -dev -exp_spotify -adsections_off -cl 20000 -topsearchbar"

Write-Output "安装 Spicetify ..."

iwr -useb https://raw.githubusercontent.com/spicetify/spicetify-cli/master/install.ps1 | iex

Write-Output "安装 custom-apps 和 extensions ..."

iwr -useb https://github.com/ECE49595-Team-6/EnhancifyInstall/releases/latest/download/install.ps1 | iex

$apiUrl = "https://api.github.com/repos/harbassan/spicetify-apps/releases"
$downloadPath = "$env:APPDATA\spicetify\CustomApps"

$response = Invoke-RestMethod -Uri $apiUrl
$downloadUrl = $response.assets | ForEach-Object { $_.browser_download_url } | Where-Object { $_ -match "stats.*\.zip$" } | Select-Object -First 1

if (-not $downloadUrl) {
    Write-Error "Error. stats release not found."
}

$tempZipPath = "$env:TEMP\spicetify-stats.zip"

Invoke-WebRequest -Uri $downloadUrl -OutFile $tempZipPath
Expand-Archive -Path $tempZipPath -DestinationPath $downloadPath -Force
Remove-Item -Path $tempZipPath

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
