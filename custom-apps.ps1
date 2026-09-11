# SpotX + Spicetify Fusion - Curated Custom Apps & Extensions Installer
# GitHub: https://github.com/ZGQ-inc/spotx-spicetify-fusion
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ProgressPreference = 'SilentlyContinue'

Write-Host " SpotX + Spicetify Fusion - Custom Apps & Extensions Installer" -ForegroundColor Cyan
Write-Host " Curated: Enhancify, Stats (patched), lyrics-plus & Popular Extensions" -ForegroundColor Cyan

$spicetifyBin = "$env:LOCALAPPDATA\spicetify"
if ((Test-Path $spicetifyBin) -and ($env:PATH -notmatch [regex]::Escape($spicetifyBin))) {
    $env:PATH = "$spicetifyBin;$env:PATH"
}
$SpotifyDir = Join-Path $env:APPDATA "Spotify"
if (-not (Test-Path $SpotifyDir)) {
    $SpotifyDir = Join-Path $env:LOCALAPPDATA "Spotify"
}
$SpotifyExe = Join-Path $SpotifyDir "Spotify.exe"
$SpotifyAppsDir = Join-Path $SpotifyDir "Apps\xpui"
$xpuiJs = Join-Path $SpotifyAppsDir "xpui.js"
$customAppsDir = "$env:APPDATA\spicetify\CustomApps"
if (-not (Test-Path $customAppsDir)) {
    New-Item -ItemType Directory -Path $customAppsDir -Force | Out-Null
}

Write-Host "Installing Enhancify..." -ForegroundColor Yellow
try {
    $apiUrl = "https://api.github.com/repos/ECE49595-Team-6/EnhancifyInstall/releases/latest"
    $downloadPath = "$customAppsDir\Enhancify"
    $response = Invoke-RestMethod -Uri $apiUrl
    $downloadUrl = $response.assets[0].browser_download_url
    if ($downloadUrl) {
        $tempZipPath = "$env:TEMP\Enhancify.zip"
        Invoke-WebRequest -Uri $downloadUrl -OutFile $tempZipPath
        New-Item -ItemType Directory -Path $downloadPath -Force | Out-Null
        Expand-Archive -Path $tempZipPath -DestinationPath $downloadPath -Force
        Remove-Item -Path $tempZipPath -Force -ErrorAction SilentlyContinue
        Write-Host "  [+] Enhancify installed successfully." -ForegroundColor Green
    }
} catch {
    Write-Warning "Enhancify download failed: $_"
}

Write-Host "Installing Stats..." -ForegroundColor Yellow
try {
    $apiUrl = "https://api.github.com/repos/harbassan/spicetify-apps/releases"
    $response = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing
    $downloadUrl = $response.assets | ForEach-Object { $_.browser_download_url } | Where-Object { $_ -match "stats.*\.zip$" } | Select-Object -First 1
    if ($downloadUrl) {
        $tempZipPath = "$env:TEMP\spicetify-stats.zip"
        Invoke-WebRequest -Uri $downloadUrl -OutFile $tempZipPath -UseBasicParsing
        Expand-Archive -Path $tempZipPath -DestinationPath $customAppsDir -Force
        Remove-Item -Path $tempZipPath -Force -ErrorAction SilentlyContinue

        $target = "$customAppsDir\stats\index.js"
        if (Test-Path $target) {
            $content = Get-Content -Path $target -Raw
            $original = 'const resizeHost = document.querySelector(".Root__main-view .os-resize-observer-host") ?? document.querySelector(".Root__main-view .os-size-observer");'
            $replacement = 'const resizeHost = document.querySelector(".Root__main-view .os-resize-observer-host") ?? document.querySelector(".Root__main-view .os-size-observer") ?? document.querySelector(".Root__main-view");'
            $newContent = $content -replace [regex]::Escape($original), $replacement
            [System.IO.File]::WriteAllText($target, $newContent, [System.Text.Encoding]::UTF8)
            Write-Host "  [+] Stats resize observer patched for modern Spotify UI." -ForegroundColor Green
        }
        Write-Host "  [+] Stats installed successfully." -ForegroundColor Green
    }
} catch {
    Write-Warning "Stats download failed: $_"
}
Write-Host "Configuring Spicetify custom apps and extensions..." -ForegroundColor Yellow
spicetify config custom_apps Enhancify stats lyrics-plus
spicetify config extensions bookmark.js fullAppDisplay.js keyboardShortcut.js loopyLoop.js popupLyrics.js shuffle+.js trashbin.js webnowplaying.js
spicetify config sidebar_config 0
spicetify apply

Write-Host "Applying Rspack compatibility patches for custom apps..." -ForegroundColor Yellow

if (Test-Path $xpuiJs) {
    $xpuiContent = [System.IO.File]::ReadAllText($xpuiJs, [System.Text.Encoding]::UTF8)
    $xpuiPatched = $false

    $customAppBundles = @()
    $routeFiles = Get-ChildItem -Path $SpotifyAppsDir -Filter "spicetify-routes-*.js" -ErrorAction SilentlyContinue
    foreach ($rf in $routeFiles) {
        if ($rf.Name -match "^spicetify-routes-(.+)\.js$") {
            $customAppBundles += $Matches[1]
        }
    }
    if ($customAppBundles.Count -gt 0) {
        $chunkMapSb = New-Object System.Text.StringBuilder
        $cssMapSb = New-Object System.Text.StringBuilder
        $appId = 1001

        foreach ($app in $customAppBundles) {
            $bundleName = "spicetify-routes-$app"
            $chunkCheck = ':"' + $bundleName + '"'
            if (-not $xpuiContent.Contains($chunkCheck)) {
                [void]$chunkMapSb.Append("$($appId):`"$bundleName`",")
            }
            $cssCheck = "$($appId):1"
            if (-not $xpuiContent.Contains($cssCheck)) {
                [void]$cssMapSb.Append("$($appId):1,")
            }
            $appId++
        }

        $uTarget = '.u=e=>""+(({'
        if ($chunkMapSb.Length -gt 0 -and $xpuiContent.Contains($uTarget)) {
            $xpuiContent = $xpuiContent.Replace($uTarget, $uTarget + $chunkMapSb.ToString())
            $xpuiPatched = $true
            Write-Host "  [+] Injected Custom Apps chunk map into .u loader" -ForegroundColor Green
        }

        $cssTarget = '0!==d[e]&&({'
        if ($cssMapSb.Length -gt 0 -and $xpuiContent.Contains($cssTarget)) {
            $xpuiContent = $xpuiContent.Replace($cssTarget, $cssTarget + $cssMapSb.ToString())
            $xpuiPatched = $true
            Write-Host "  [+] Injected Custom Apps into MiniCss allowlist" -ForegroundColor Green
        }
    }

    if ($xpuiPatched) {
        [System.IO.File]::WriteAllText($xpuiJs, $xpuiContent, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "  [+] xpui.js updated with custom app chunks." -ForegroundColor Green
    }
}

$routeFiles = Get-ChildItem -Path $SpotifyAppsDir -Filter "spicetify-routes-*.js" -ErrorAction SilentlyContinue
if ($routeFiles.Count -gt 0) {
    foreach ($rf in $routeFiles) {
        $rc = [System.IO.File]::ReadAllText($rf.FullName, [System.Text.Encoding]::UTF8)
        $pushIdx = $rc.IndexOf(').push([[')
        if ($pushIdx -gt 0 -and $pushIdx -lt 300) {
            $fixedHead = '(("u">typeof self?self:global).rspackChunk||=[]' + $rc.Substring($pushIdx)
            [System.IO.File]::WriteAllText($rf.FullName, $fixedHead, (New-Object System.Text.UTF8Encoding($false)))
            Write-Host "  [+] Fixed bundle push chain for $($rf.Name)" -ForegroundColor Green
        }
    }
}

Get-Process -Name "Spotify" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
if (Test-Path $SpotifyExe) {
    Start-Process -FilePath $SpotifyExe
}

Write-Host " Custom apps and extensions installed and patched successfully!" -ForegroundColor Green