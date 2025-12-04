# https://t.me/ZGQinc

# $url = "https://spicetify.zgqinc.gq/run.exe"
# $output = Join-Path $env:TEMP "install_spotify.exe"
# Invoke-WebRequest -Uri $url -OutFile $output
# Start-Process -FilePath $output -Wait
# Remove-Item -Path $output -Force

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ProgressPreference = 'SilentlyContinue'

Write-Output "Installing Spotify and patching with SpotX..."
# iex "& { $(iwr -useb 'https://raw.githubusercontent.com/SpotX-Official/spotx-official.github.io/main/run.ps1') } -confirm_uninstall_ms_spoti -sp-over -new_theme -block_update_on -podcasts_on -dev -exp_spotify -adsections_off -cl 20000 -topsearchbar -newFullscreenMode -canvasHome -rightsidebarcolor -hide_col_icon_off"

$spotxUrl = "https://raw.githubusercontent.com/SpotX-Official/spotx-official.github.io/main/run.ps1"
$spotxLocalPath = Join-Path $env:TEMP "run_spotx.ps1"
Invoke-WebRequest -Uri $spotxUrl -OutFile $spotxLocalPath -UseBasicParsing

(Get-Content -Raw -Path $spotxLocalPath) -replace '(?s)if\s*\(\$test_js\)\s*\{(.*?)(Write-Host\s*\(\$lang\)\.StopScript\s*\n)?(Pause\s*\n)?(Exit\s*)?\}', {
    param($m)
    $body = $m.Groups[1].Value
    "if (`$test_js) {`n$body`n}"
} | Set-Content -Path $spotxLocalPath -Encoding UTF8

# & $spotxLocalPath -confirm_uninstall_ms_spoti -sp-over -new_theme -block_update_on -podcasts_on -dev -exp_spotify -adsections_off -cl 20000 -topsearchbar -newFullscreenMode -canvasHome -rightsidebarcolor -hide_col_icon_off

& $spotxLocalPath -confirm_uninstall_ms_spoti -sp-over -new_theme -block_update_on -podcasts_on -dev -exp_spotify -adsections_off -cl 20000 -topsearchbar -newFullscreenMode -canvasHome -rightsidebarcolor -hide_col_icon_off -version 1.2.77.358.g4339a634-545

Write-Output "Installing Spicetify..."
iwr -useb https://raw.githubusercontent.com/spicetify/spicetify-cli/master/install.ps1 | iex

Write-Output "Installing custom-apps and extensions..."

Write-Output "Downloading Enhancify..."
# iwr -useb https://github.com/ECE49595-Team-6/EnhancifyInstall/releases/latest/download/install.ps1 | iex
$apiUrl = "https://api.github.com/repos/ECE49595-Team-6/EnhancifyInstall/releases/latest"
$downloadPath = "$env:APPDATA\spicetify\CustomApps\Enhancify"
$response = Invoke-RestMethod -Uri $apiUrl
$downloadUrl = $response.assets[0].browser_download_url
if (-not $downloadUrl) {
    Write-Error "Error: Failed to find release."
    exit
}
$tempZipPath = "$env:TEMP\Enhancify.zip"
Invoke-WebRequest -Uri $downloadUrl -OutFile $tempZipPath
New-Item -ItemType Directory -Path $downloadPath -Force | Out-Null
Expand-Archive -Path $tempZipPath -DestinationPath $downloadPath -Force
Remove-Item -Path $tempZipPath

Write-Output "Downloading stats..."
$apiUrl = "https://api.github.com/repos/harbassan/spicetify-apps/releases"
$downloadPath = "$env:APPDATA\spicetify\CustomApps"
$response = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing
$downloadUrl = $response.assets | ForEach-Object { $_.browser_download_url } | Where-Object { $_ -match "stats.*\.zip$" } | Select-Object -First 1
if (-not $downloadUrl) {
    Write-Error "Error: Failed to find release."
    exit
}
$tempZipPath = "$env:TEMP\spicetify-stats.zip"
Invoke-WebRequest -Uri $downloadUrl -OutFile $tempZipPath -UseBasicParsing
Expand-Archive -Path $tempZipPath -DestinationPath $downloadPath -Force
Remove-Item -Path $tempZipPath

Write-Output "Trying to fix custom-app stats..."
if ($downloadUrl -match "stats-v1\.1\.2/") {
    Write-Output "Stats version is 1.1.2, patching index.js..."

    $target = "$env:APPDATA\spicetify\CustomApps\stats\index.js"
    $backup = "$target.bak"

    if (Test-Path $backup) {
        Write-Output "index.js already patched, skip."
    }
    else {
        Copy-Item -Path $target -Destination $backup -Force
        Write-Output "index.js.bak created."

        $content = Get-Content -Path $target -Raw
        $original = 'const resizeHost = document.querySelector(".Root__main-view .os-resize-observer-host") ?? document.querySelector(".Root__main-view .os-size-observer");'
        $replacement = 'const resizeHost = document.querySelector(".Root__main-view .os-resize-observer-host") ?? document.querySelector(".Root__main-view .os-size-observer") ?? document.querySelector(".Root__main-view");'

        $newContent = $content -replace [regex]::Escape($original), $replacement
        [System.IO.File]::WriteAllText($target, $newContent, [System.Text.Encoding]::UTF8)
        Write-Output "Replace complete."

        spicetify config custom_apps stats-
        spicetify apply
    }
}
else {
    Write-Output "Stats version is not 1.1.2, skip."
}

Write-Output "Configuring Spicetify..."
spicetify restore backup
spicetify backup apply
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

Write-Output "Installation completed."
