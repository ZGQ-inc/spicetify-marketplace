# https://t.me/ZGQinc

$spotxCommand = "iex ""& { $(iwr -useb 'https://raw.githubusercontent.com/SpotX-Official/spotx-official.github.io/main/run.ps1') } -new_theme"""
$spotxInput = @"
N
Y
"@
$spotxProcess = Start-Process powershell -ArgumentList "-NoProfile", "-Command", $spotxCommand -RedirectStandardInput "spotxInput.txt" -NoNewWindow -Wait

$spicetifyCommand = "iwr -useb https://raw.githubusercontent.com/spicetify/spicetify-cli/master/install.ps1 | iex"
$spicetifyInput = @"
Y
"@
$spicetifyProcess = Start-Process powershell -ArgumentList "-NoProfile", "-Command", $spicetifyCommand -RedirectStandardInput "spicetifyInput.txt" -NoNewWindow -Wait

$apiUrl = "https://api.github.com/repos/harbassan/spicetify-apps/releases"
$downloadPath = "$env:APPDATA\spicetify\CustomApps"

$response = Invoke-RestMethod -Uri $apiUrl
$downloadUrl = $response.assets | ForEach-Object { $_.browser_download_url } | Where-Object { $_ -match "stats.*\.zip$" } | Select-Object -First 1

if (-not $downloadUrl) {
    Write-Error "stats release not found."
    exit 1
}

$tempZipPath = "$env:TEMP\spicetify-stats.zip"

Invoke-WebRequest -Uri $downloadUrl -OutFile $tempZipPath
Expand-Archive -Path $tempZipPath -DestinationPath $downloadPath -Force
Remove-Item -Path $tempZipPath
Write-Output "success mv stats custom app."

spicetify config custom_apps stats
spicetify config custom_apps lyrics-plus
spicetify config sidebar_config 0
spicetify apply
