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

# Bypass SpotX installation block, auto-answer 'N' to Defender exclusions prompt, and launch SpotifySetup directly
$spotxContent = Get-Content -Raw -Path $spotxLocalPath
$spotxContent = $spotxContent -replace '(?s)if\s*\(\$test_js\)\s*\{.*?Stop-Script\s*\}', '# Spicetify block bypassed by SpotX-Spicetify-Fusion'
$spotxContent = $spotxContent -replace 'Read-Host\s+-Prompt\s+\$defenderPrompt', "'n'"
$spotxContent = $spotxContent -replace 'Start-Process\s+-FilePath\s+explorer\.exe\s+-ArgumentList\s+\$setupExe', 'Start-Process -FilePath $setupExe'
$spotxContent | Set-Content -Path $spotxLocalPath -Encoding UTF8

& $spotxLocalPath -confirm_uninstall_ms_spoti -sp-over -new_theme -block_update_on -podcasts_on -dev -exp_spotify -adsections_off -cl 20000 -topsearchbar -newFullscreenMode -canvasHome -rightsidebarcolor -hide_col_icon_off -no_pause -defender_exclusions_off

# 2. Install Spicetify CLI (bypassing internal Marketplace prompt so Spotify can be initialized first)
Write-Host "[2/5] Installing Spicetify CLI..." -ForegroundColor Yellow
$spicetifyCliUrl = "https://raw.githubusercontent.com/spicetify/spicetify-cli/master/install.ps1"
$spicetifyScript = (Invoke-WebRequest -Uri $spicetifyCliUrl -UseBasicParsing).Content
# Bypass internal Marketplace prompt and admin check inside Spicetify CLI installer
$spicetifyScript = $spicetifyScript -replace '(?s)#region Marketplace.*?#endregion Marketplace', '# Marketplace prompt bypassed; handled in next step'
$spicetifyScript = $spicetifyScript -replace 'if\s*\(-not\s*\(Test-Admin\)\)\s*\{', 'if ($false) {'
$spicetifyScript = $spicetifyScript -replace '\$Host\.UI\.RawUI\.Flushinputbuffer\(\)', '# flush bypassed'
Invoke-Expression $spicetifyScript

# Ensure spicetify is immediately available in current process PATH
$spicetifyBin = "$env:LOCALAPPDATA\spicetify"
if ((Test-Path $spicetifyBin) -and ($env:PATH -notmatch [regex]::Escape($spicetifyBin))) {
    $env:PATH = "$spicetifyBin;$env:PATH"
}

# 3. Pre-launch Spotify to initialize CEF state, auto-grant local network permission, and install Marketplace
Write-Host "[3/5] Pre-launching Spotify, granting permissions, and installing Marketplace..." -ForegroundColor Yellow

function Grant-ChromiumLocalNetworkAccess {
    $prefPaths = @(
        "$env:LOCALAPPDATA\Spotify\Default\Preferences",
        "$env:APPDATA\Spotify\Default\Preferences",
        "$env:LOCALAPPDATA\Spotify\User Data\Default\Preferences"
    )
    foreach ($pp in $prefPaths) {
        if (Test-Path $pp) {
            try {
                $prefObj = Get-Content -Path $pp -Raw -Encoding UTF8 | ConvertFrom-Json
                if (-not $prefObj.profile) { $prefObj | Add-Member -NotePropertyName "profile" -NotePropertyValue ([PSCustomObject]@{}) -Force }
                if (-not $prefObj.profile.content_settings) { $prefObj.profile | Add-Member -NotePropertyName "content_settings" -NotePropertyValue ([PSCustomObject]@{}) -Force }
                if (-not $prefObj.profile.content_settings.exceptions) { $prefObj.profile.content_settings | Add-Member -NotePropertyName "exceptions" -NotePropertyValue ([PSCustomObject]@{}) -Force }

                $grantObj = [PSCustomObject]@{
                    "https://login.app.spotify.com:443,*" = [PSCustomObject]@{
                        "setting" = 1
                    }
                }
                $prefObj.profile.content_settings.exceptions | Add-Member -NotePropertyName "local_network_access" -NotePropertyValue $grantObj -Force
                $prefObj.profile.content_settings.exceptions | Add-Member -NotePropertyName "local_network" -NotePropertyValue $grantObj -Force
                $prefObj.profile.content_settings.exceptions | Add-Member -NotePropertyName "loopback_network" -NotePropertyValue $grantObj -Force

                if (-not $prefObj.default_content_setting_values) {
                    $prefObj | Add-Member -NotePropertyName "default_content_setting_values" -NotePropertyValue ([PSCustomObject]@{}) -Force
                }
                $prefObj.default_content_setting_values | Add-Member -NotePropertyName "local_network_access" -NotePropertyValue 1 -Force
                $prefObj.default_content_setting_values | Add-Member -NotePropertyName "local_network" -NotePropertyValue 1 -Force

                $prefObj | ConvertTo-Json -Depth 32 | Set-Content -Path $pp -Encoding UTF8
                Write-Host "  [+] Pre-configured Chromium local network access permission in Preferences" -ForegroundColor Green
            } catch {}
        }
    }
}

# Auto-configure Chromium Preferences before starting
Grant-ChromiumLocalNetworkAccess

# Launch Spotify in background to initialize browser cache and local database
Write-Host "  -> Launching Spotify to initialize profile and runtime..." -ForegroundColor Cyan
$spotifyExe = "$env:APPDATA\Spotify\Spotify.exe"
if (-not (Test-Path $spotifyExe)) {
    $spotifyExe = "$env:LOCALAPPDATA\Spotify\Spotify.exe"
}
if (Test-Path $spotifyExe) {
    Start-Process -FilePath $spotifyExe -ErrorAction SilentlyContinue
}

# Wait for CEF window initialization
Start-Sleep -Seconds 3

# Auto-allow "Access other devices on your local network" in Preferences while running
Grant-ChromiumLocalNetworkAccess

# Auto-click "Allow" / "允许" on permission prompt via UI Automation
try {
    Add-Type -AssemblyName UIAutomationClient -ErrorAction SilentlyContinue
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $windows = $root.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)
    foreach ($w in $windows) {
        try {
            if ($w.Current.Name -match "Spotify|login|permission|network|设备|网络" -or $w.Current.ClassName -match "Chrome|Widget") {
                $buttons = $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)))
                foreach ($btn in $buttons) {
                    $btnName = $btn.Current.Name
                    if ($btnName -match "^(Allow|允许|同意|确定|OK)$") {
                        $pattern = $btn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
                        $pattern.Invoke()
                        Write-Host "  [+] Clicked '$btnName' permission button via UI Automation" -ForegroundColor Green
                        break
                    }
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
Start-Sleep -Seconds 2

# Auto-configure Chromium Preferences again after exit
Grant-ChromiumLocalNetworkAccess

# Install Marketplace with unattended 'Y' choice (PromptForChoice bypassed with choice 0 = Yes)
Write-Host "  -> Installing Spicetify Marketplace..." -ForegroundColor Cyan
try {
    $marketScript = (Invoke-WebRequest -Uri "https://raw.githubusercontent.com/spicetify/marketplace/main/resources/install.ps1" -UseBasicParsing).Content
    # Automatically answer 'Yes' (0) to theme replacement prompt ("填Y回车")
    $marketScript = $marketScript -replace '\$Host\.UI\.RawUI\.Flushinputbuffer\(\)', '# flush bypassed'
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

# 5. Apply SpotX + Spicetify Unified Compatibility Hotfix (Embedded)
Write-Host "[5/5] Applying SpotX + Spicetify compatibility hotfix..." -ForegroundColor Yellow

$SpotifyDir = Join-Path $env:APPDATA "Spotify"
if (-not (Test-Path $SpotifyDir)) {
    $SpotifyDir = Join-Path $env:LOCALAPPDATA "Spotify"
}
$SpotifyExe = Join-Path $SpotifyDir "Spotify.exe"
$SpotifyAppsDir = Join-Path $SpotifyDir "Apps\xpui"
$xpuiJs = Join-Path $SpotifyAppsDir "xpui.js"
$wrapperJs = Join-Path $SpotifyAppsDir "helper\spicetifyWrapper.js"

# Snapshot filename casing normalization (SpotX commit 9fa954a fix)
$casedSnapshot = Join-Path $SpotifyDir "V8_context_snapshot.bin"
$normalSnapshot = Join-Path $SpotifyDir "v8_context_snapshot.bin"
if ((Test-Path $casedSnapshot) -and -not (Test-Path $normalSnapshot)) {
    try {
        $tempRename = Join-Path $SpotifyDir "v8_context_snapshot.bin.tmp"
        Rename-Item -Path $casedSnapshot -NewName "v8_context_snapshot.bin.tmp" -Force -ErrorAction SilentlyContinue
        Rename-Item -Path $tempRename -NewName "v8_context_snapshot.bin" -Force -ErrorAction SilentlyContinue
        Write-Host "  [+] Normalized snapshot filename casing to 'v8_context_snapshot.bin'" -ForegroundColor Green
    } catch {}
}

if (Test-Path $xpuiJs) {
    $xpuiContent = [System.IO.File]::ReadAllText($xpuiJs, [System.Text.Encoding]::UTF8)
    $xpuiPatched = $false

    # 1. Fix Spicetify 1.3.0 semver bug (SyntaxError startup black screen)
    $badSnackbar = "Spicetify.Snackbar.enqueueImageSnackbar="
    if ($xpuiContent.Contains($badSnackbar)) {
        $xpuiContent = $xpuiContent.Replace($badSnackbar, "")
        $xpuiPatched = $true
        Write-Host "  [+] Fixed SyntaxError corruption (Resolved 1.3.0 startup black screen)" -ForegroundColor Green
    }

    # 2. Fix useNavigateStable crash (Marketplace white screen)
    $oldNav = "return(0,e.useNavigateStable)()"
    $safeNav = 'return(()=>{try{return(0,e.useNavigateStable)()}catch(err){return Spicetify?.Platform?.History?.push||Spicetify?.Platform?.History?.navigate||(()=>({}))}})()'
    if ($xpuiContent.Contains($oldNav)) {
        $xpuiContent = $xpuiContent.Replace($oldNav, $safeNav)
        $xpuiPatched = $true
        Write-Host "  [+] Injected safe fallback for useNavigateStable" -ForegroundColor Green
    }

    # 3. Fix RegistryContext useReducer on undefined (Resolved Spotify 1.3.0 crash modal)
    $oldRegistry = "(0,i.useContext)(e.yv)"
    $safeRegistry = "((0,i.useContext)(e.yv)||Spicetify?.Platform?.Registry||{entries:new Map()})"
    if ($xpuiContent.Contains($oldRegistry) -and -not $xpuiContent.Contains($safeRegistry)) {
        $xpuiContent = $xpuiContent.Replace($oldRegistry, $safeRegistry)
        $xpuiPatched = $true
        Write-Host "  [+] Injected safe fallback for RegistryContext" -ForegroundColor Green
    }

    # 4. Scan custom apps and inject chunk map + MiniCss allowlist
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
        Write-Host "  [+] xpui.js successfully patched!" -ForegroundColor Green
    }
}

# 5. Patch helper/spicetifyWrapper.js
if (Test-Path $wrapperJs) {
    $wrapContent = [System.IO.File]::ReadAllText($wrapperJs, [System.Text.Encoding]::UTF8)
    $wrapPatched = $false

    # window.rspackChunk
    $chunkTarget = 'window?.webpackChunkclient_web||window?.rspackChunkclient_web'
    $chunkFixed  = 'window?.webpackChunkclient_web||window?.rspackChunkclient_web||window?.rspackChunk'
    if ($wrapContent.Contains($chunkTarget) -and -not $wrapContent.Contains($chunkFixed)) {
        $wrapContent = $wrapContent.Replace($chunkTarget, $chunkFixed)
        $wrapPatched = $true
        Write-Host "  [+] Hooked window.rspackChunk in spicetifyWrapper.js" -ForegroundColor Green
    }

    # Spicetify.URI
    $uriTarget = 'Spicetify.React=f.find(m=>m?.useMemo),'
    $uriInjection = '(()=>{let u=f.find(m=>m?.NQG?.PLAYLIST_V2);if(u){let s=u.o_h("spotify:track:4uLU6hMCjMI75M1A2tKUQC")?.constructor;if(s){s.Type=u.NQG,s.from=u.o_h,s.fromString=u.Lce,s.idToHex=u.DY5,s.hexToId=u.dx2,Spicetify.URI=s}}})(),'
    if ($wrapContent.Contains($uriTarget) -and -not $wrapContent.Contains('Spicetify.URI=s')) {
        $wrapContent = $wrapContent.Replace($uriTarget, $uriTarget + $uriInjection)
        $wrapPatched = $true
        Write-Host "  [+] Injected dynamic Spicetify.URI parser export" -ForegroundColor Green
    }

    if ($wrapPatched) {
        [System.IO.File]::WriteAllText($wrapperJs, $wrapContent, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "  [+] spicetifyWrapper.js successfully patched!" -ForegroundColor Green
    }
}

# 6. Fix custom apps push headers in spicetify-routes-*.js
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

# 7. Launch Patched Spotify Client
if (Test-Path $SpotifyExe) {
    Write-Host "  -> Launching patched Spotify..." -ForegroundColor Cyan
    Start-Process -FilePath $SpotifyExe
}

Write-Host " Installation and unified hotfix completed successfully!" -ForegroundColor Green
Write-Host " Enjoy your ad-free, fully-customized, high-performance Spotify!" -ForegroundColor Green
