# https://t.me/ZGQinc

Write-Output "Installing Spotify modfied by SpotX..."

iex "& { $(iwr -useb 'https://raw.githubusercontent.com/SpotX-Official/spotx-official.github.io/main/run.ps1') } -new_theme"

Write-Output "Installing Spicetify..."

iwr -useb https://raw.githubusercontent.com/spicetify/spicetify-cli/master/install.ps1 | iex

Write-Output "Installing custom-apps and extensions..."

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
