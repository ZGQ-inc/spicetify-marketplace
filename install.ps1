# SpotX + Spicetify All-in-One Automated Installer (Windows Edition)
# Supports Spotify 1.2.x & 1.3.x (Rspack)
# GitHub: https://github.com/ZGQ-inc/spotx-spicetify-fusion
# Telegram: https://t.me/ZGQinc

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ProgressPreference = 'SilentlyContinue'

Write-Host " SpotX + Spicetify All-in-One Automated Installer" -ForegroundColor Cyan
Write-Host " Supports Spotify 1.2.x & 1.3.x (Rspack)" -ForegroundColor Cyan
Write-Host " GitHub: https://github.com/ZGQ-inc/spotx-spicetify-fusion" -ForegroundColor Cyan

# 1. Install / Update Spotify with SpotX
Write-Host "[1/5] Installing Spotify and patching with SpotX..." -ForegroundColor Yellow

$spotxUrl = "https://raw.githubusercontent.com/SpotX-Official/SpotX/main/run.ps1"
$spotxLocalPath = Join-Path $env:TEMP "run_spotx.ps1"
Invoke-WebRequest -Uri $spotxUrl -OutFile $spotxLocalPath -UseBasicParsing

# Bypass SpotX installation block and auto-answer 'N' to Defender exclusions prompt
$spotxContent = Get-Content -Raw -Path $spotxLocalPath
$spotxContent = $spotxContent -replace '(?s)if\s*\(\$test_js\)\s*\{.*?Stop-Script\s*\}', '# Spicetify block bypassed by SpotX-Spicetify-Fusion'
$spotxContent = $spotxContent -replace 'Read-Host\s+-Prompt\s+\$defenderPrompt', "'n'"
$spotxContent | Set-Content -Path $spotxLocalPath -Encoding UTF8

& $spotxLocalPath -confirm_uninstall_ms_spoti -sp-over -new_theme -block_update_on -podcasts_on -dev -exp_spotify -adsections_off -cl 20000 -topsearchbar -newFullscreenMode -canvasHome -rightsidebarcolor -hide_col_icon_off -no_pause -defender_exclusions_off

# 2. Install Spicetify CLI (bypassing internal Marketplace prompt so Spotify can be initialized first)
Write-Host "[2/5] Installing Spicetify CLI..." -ForegroundColor Yellow
$spicetifyCliUrl = "https://raw.githubusercontent.com/spicetify/spicetify-cli/master/install.ps1"
$spicetifyScript = (Invoke-WebRequest -Uri $spicetifyCliUrl -UseBasicParsing).Content
# Bypass internal Marketplace prompt inside Spicetify CLI installer
$spicetifyScript = $spicetifyScript -replace '(?s)#region Marketplace.*?#endregion Marketplace', '# Marketplace prompt bypassed; handled in next step'
Invoke-Expression $spicetifyScript

# Ensure spicetify is immediately available in current process PATH
$spicetifyBin = "$env:LOCALAPPDATA\spicetify"
if (Test-Path $spicetifyBin -and ($env:PATH -notmatch [regex]::Escape($spicetifyBin))) {
    $env:PATH = "$spicetifyBin;$env:PATH"
}

# 3. Pre-launch Spotify to initialize CEF state, auto-grant local network permission, and install Marketplace
Write-Host "[3/5] Pre-launching Spotify, granting permissions, and installing Marketplace..." -ForegroundColor Yellow

# Launch Spotify in background to initialize browser cache and local database
Write-Host "  -> Launching Spotify to initialize profile and runtime..." -ForegroundColor Cyan
$spotifyExe = "$env:APPDATA\Spotify\Spotify.exe"
if (-not (Test-Path $spotifyExe)) {
    $spotifyExe = "$env:LOCALAPPDATA\Spotify\Spotify.exe"
}
if (Test-Path $spotifyExe) {
    Start-Process -FilePath $spotifyExe -ErrorAction SilentlyContinue
}

# Wait for CEF initialization
Start-Sleep -Seconds 4

# Auto-allow "Access other devices on your local network" in Chromium Preferences
$prefPaths = @(
    "$env:LOCALAPPDATA\Spotify\Default\Preferences",
    "$env:APPDATA\Spotify\Default\Preferences",
    "$env:LOCALAPPDATA\Spotify\User Data\Default\Preferences"
)
foreach ($pp in $prefPaths) {
    if (Test-Path $pp) {
        try {
            $prefObj = Get-Content -Path $pp -Raw -Encoding UTF8 | ConvertFrom-Json
            if (-not $prefObj.profile) { $prefObj | Add-Member -NotePropertyName "profile" -NotePropertyValue ([PSCustomObject]@{}) }
            if (-not $prefObj.profile.content_settings) { $prefObj.profile | Add-Member -NotePropertyName "content_settings" -NotePropertyValue ([PSCustomObject]@{}) }
            if (-not $prefObj.profile.content_settings.exceptions) { $prefObj.profile.content_settings | Add-Member -NotePropertyName "exceptions" -NotePropertyValue ([PSCustomObject]@{}) }

            $grantObj = [PSCustomObject]@{
                "https://login.app.spotify.com:443,*" = [PSCustomObject]@{
                    "setting" = 1
                }
            }
            $prefObj.profile.content_settings.exceptions | Add-Member -NotePropertyName "local_network_access" -NotePropertyValue $grantObj -Force
            $prefObj.profile.content_settings.exceptions | Add-Member -NotePropertyName "local_network" -NotePropertyValue $grantObj -Force
            $prefObj | ConvertTo-Json -Depth 32 | Set-Content -Path $pp -Encoding UTF8
            Write-Host "  [+] Pre-configured Chromium local network access permission in Preferences" -ForegroundColor Green
        } catch {}
    }
}

# Auto-click "Allow" / "允许" on permission prompt via UI Automation
try {
    Add-Type -AssemblyName UIAutomationClient -ErrorAction SilentlyContinue
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $windows = $root.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)
    foreach ($w in $windows) {
        try {
            if ($w.Current.Name -match "Spotify|login|permission" -or $w.Current.ClassName -match "Chrome|Widget") {
                $allowBtn = $w.FindFirst([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, "Allow")))
                if (-not $allowBtn) {
                    $allowBtn = $w.FindFirst([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, "允许")))
                }
                if ($allowBtn) {
                    $pattern = $allowBtn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
                    $pattern.Invoke()
                    Write-Host "  [+] Clicked Allow permission button via UI Automation" -ForegroundColor Green
                }
            }
        } catch {}
    }
} catch {}

# Fallback: Send Enter to activate default Allow button if modal is focused
try {
    $wshell = New-Object -ComObject WScript.Shell
    if ($wshell.AppActivate("Spotify")) {
        Start-Sleep -Milliseconds 300
        $wshell.SendKeys("{ENTER}")
    }
} catch {}

# Wait 5 seconds as requested
Write-Host "  -> Waiting 5 seconds before applying Marketplace..." -ForegroundColor Cyan
Start-Sleep -Seconds 5

# Terminate Spotify cleanly so Spicetify can patch xpui without file locking conflicts
Get-Process -Name "Spotify" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

# Install Marketplace with unattended 'Y' choice (PromptForChoice bypassed with choice 0 = Yes)
Write-Host "  -> Installing Spicetify Marketplace..." -ForegroundColor Cyan
try {
    $marketScript = (Invoke-WebRequest -Uri "https://raw.githubusercontent.com/spicetify/marketplace/main/resources/install.ps1" -UseBasicParsing).Content
    # Automatically answer 'Yes' (0) to theme replacement prompt ("填Y回车")
    $marketScript = $marketScript -replace '\$choice\s*=\s*\$Host\.UI\.PromptForChoice\(.*?\)', '$choice = 0'
    Invoke-Expression $marketScript
} catch {
    Write-Warning "Marketplace installer prompt: $_"
}

# 4. Install Curated Custom Apps & Extensions
Write-Host "[4/5] Installing popular custom apps and extensions..." -ForegroundColor Yellow

# 4a. Enhancify
try {
    Write-Host "  -> Downloading Enhancify..." -ForegroundColor Cyan
    $apiUrl = "https://api.github.com/repos/ECE49595-Team-6/EnhancifyInstall/releases/latest"
    $downloadPath = "$env:APPDATA\spicetify\CustomApps\Enhancify"
    $response = Invoke-RestMethod -Uri $apiUrl
    $downloadUrl = $response.assets[0].browser_download_url
    if ($downloadUrl) {
        $tempZipPath = "$env:TEMP\Enhancify.zip"
        Invoke-WebRequest -Uri $downloadUrl -OutFile $tempZipPath
        New-Item -ItemType Directory -Path $downloadPath -Force | Out-Null
        Expand-Archive -Path $tempZipPath -DestinationPath $downloadPath -Force
        Remove-Item -Path $tempZipPath -Force -ErrorAction SilentlyContinue
    }
} catch {
    Write-Warning "Enhancify download skipped: $_"
}

# 4b. Stats
try {
    Write-Host "  -> Downloading stats..." -ForegroundColor Cyan
    $apiUrl = "https://api.github.com/repos/harbassan/spicetify-apps/releases"
    $downloadPath = "$env:APPDATA\spicetify\CustomApps"
    $response = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing
    $downloadUrl = $response.assets | ForEach-Object { $_.browser_download_url } | Where-Object { $_ -match "stats.*\.zip$" } | Select-Object -First 1
    if ($downloadUrl) {
        $tempZipPath = "$env:TEMP\spicetify-stats.zip"
        Invoke-WebRequest -Uri $downloadUrl -OutFile $tempZipPath -UseBasicParsing
        Expand-Archive -Path $tempZipPath -DestinationPath $downloadPath -Force
        Remove-Item -Path $tempZipPath -Force -ErrorAction SilentlyContinue

        # Patch stats 1.1.2 UI resize observer
        $target = "$env:APPDATA\spicetify\CustomApps\stats\index.js"
        if (Test-Path $target) {
            $content = Get-Content -Path $target -Raw
            $original = 'const resizeHost = document.querySelector(".Root__main-view .os-resize-observer-host") ?? document.querySelector(".Root__main-view .os-size-observer");'
            $replacement = 'const resizeHost = document.querySelector(".Root__main-view .os-resize-observer-host") ?? document.querySelector(".Root__main-view .os-size-observer") ?? document.querySelector(".Root__main-view");'
            $newContent = $content -replace [regex]::Escape($original), $replacement
            [System.IO.File]::WriteAllText($target, $newContent, [System.Text.Encoding]::UTF8)
        }
    }
} catch {
    Write-Warning "Stats app download skipped: $_"
}

# 4c. Configure Spicetify and Apply
Write-Host "  -> Applying Spicetify configuration..." -ForegroundColor Cyan
spicetify restore backup
spicetify backup apply
spicetify config custom_apps marketplace
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

# 5. Apply SpotX + Spicetify Unified Compatibility Hotfix
Write-Host "[5/5] Applying SpotX + Spicetify compatibility hotfix..." -ForegroundColor Yellow

$localFixPath = Join-Path $PSScriptRoot "fix.ps1"
if (Test-Path $localFixPath) {
    & $localFixPath -LaunchSpotify
} else {
    # Fallback to online fix script
    iwr -useb https://spicetify.zgqinc.gq/fix-spotx-spicetify.ps1 | iex
}

Write-Host " Installation and unified hotfix completed successfully!" -ForegroundColor Green
Write-Host " Enjoy your ad-free, fully-customized, high-performance Spotify!" -ForegroundColor Green
