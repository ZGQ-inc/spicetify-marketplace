<#
.SYNOPSIS
    SpotX + Spicetify Unified Compatibility Hotfix Script
    Supports Spotify 1.2.x (Webpack) and 1.3.x+ (Rspack Architecture)
.DESCRIPTION
    Fixes critical compatibility issues between SpotX and Spicetify:
    1. Spotify 1.3.0+ fatal black screen:
       "Uncaught SyntaxError: Unexpected identifier 'Spicetify'"
       (Caused by Spicetify semver compare bug injecting obsolete legacy syntax into 1.3.0+)
    2. Spotify 1.3.0+ Rspack runtime undefined globals:
       Resolves Spicetify.React / Spicetify.ReactDOM / Spicetify.URI undefined states
    3. Marketplace & Custom Apps missing or crashing:
       - Fixes "useNavigateStable must be used within a StableUseNavigateProvider"
       - Fixes RegistryContext "useReducer on undefined" modal popups
       - Injects custom app routes into Rspack / Webpack .u chunk map & MiniCss whitelist
       - Fixes route bundle push header ("window.push is not a function")
    4. Spotify 1.2.x compatibility:
       - Fixes SpotX index.html redirection dropping xpui-snapshot.js
       - Normalizes v8_context_snapshot.bin casing from SpotX commit 9fa954a
.LINK
    https://github.com/ZGQ-inc/spotx-spicetify-fusion
#>

[CmdletBinding()]
param(
    [switch]$Quiet,
    [switch]$LaunchSpotify,
    [switch]$Force
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Write-Log {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    if (-not $Quiet) {
        Write-Host $Message -ForegroundColor $Color
    }
}

Write-Log " SpotX + Spicetify Unified Compatibility Hotfix (v2.1)" "Cyan"
Write-Log " Supports Spotify 1.2.x (Webpack) & 1.3.x+ (Rspack)" "Cyan"
Write-Log " GitHub: https://github.com/ZGQ-inc/spotx-spicetify-fusion" "Cyan"

# Terminate running Spotify processes
$spotifyProcs = Get-Process -Name "Spotify" -ErrorAction SilentlyContinue
if ($spotifyProcs) {
    Write-Log "[*] Closing running Spotify process..." "Yellow"
    $spotifyProcs | Stop-Process -Force
    Start-Sleep -Milliseconds 800
}

# Locate Spotify & Spicetify directories
$SpotifyDir = Join-Path $env:APPDATA "Spotify"
if (-not (Test-Path $SpotifyDir)) {
    $SpotifyDir = Join-Path $env:LOCALAPPDATA "Spotify"
}
if (-not (Test-Path $SpotifyDir)) {
    Write-Log "[-] Spotify installation directory not found!" "Red"
    exit 1
}

$SpotifyExe = Join-Path $SpotifyDir "Spotify.exe"
$SpotifyAppsDir = Join-Path $SpotifyDir "Apps\xpui"
$xpuiJs = Join-Path $SpotifyAppsDir "xpui.js"
$wrapperJs = Join-Path $SpotifyAppsDir "helper\spicetifyWrapper.js"
$indexHtml = Join-Path $SpotifyAppsDir "index.html"

if (-not (Test-Path $xpuiJs)) {
    Write-Log "[-] Spotify xpui.js not found at: $xpuiJs" "Red"
    Write-Log "    Please run 'spicetify apply' or 'spicetify backup apply' first." "Yellow"
    exit 1
}

# Detect Spotify version and architecture
$detectedVersion = "unknown"
if (Test-Path $SpotifyExe) {
    try {
        $detectedVersion = (Get-Item $SpotifyExe).VersionInfo.ProductVersion
        if (-not $detectedVersion) {
            $detectedVersion = (Get-Item $SpotifyExe).VersionInfo.FileVersion
        }
    } catch {}
}

$xpuiContent = [System.IO.File]::ReadAllText($xpuiJs, [System.Text.Encoding]::UTF8)

$is130OrAbove = $false
if ($detectedVersion -ne "unknown" -and $detectedVersion -match '^1\.([3-9]|\d{2,})\.') {
    $is130OrAbove = $true
} elseif ($xpuiContent.Contains("rspackChunk") -or $xpuiContent.Contains("rspackChunkclient_web")) {
    $is130OrAbove = $true
}

Write-Log "[+] Spotify path: $SpotifyDir" "Green"
if ($is130OrAbove) {
    Write-Log "[+] Detected Spotify Version: $detectedVersion (v1.3.x+ Rspack Architecture)" "Green"
} else {
    Write-Log "[+] Detected Spotify Version: $detectedVersion (v1.2.x Webpack Architecture)" "Green"
}

# SECTION A: Normalize snapshot filenames (Fix for SpotX commit 9fa954a casing hack)
$snapshotDir = $SpotifyDir
$casedSnapshot = Join-Path $snapshotDir "V8_context_snapshot.bin"
$normalSnapshot = Join-Path $snapshotDir "v8_context_snapshot.bin"

if ((Test-Path $casedSnapshot) -and -not (Test-Path $normalSnapshot)) {
    try {
        $tempRename = Join-Path $snapshotDir "v8_context_snapshot.bin.tmp"
        Rename-Item -Path $casedSnapshot -NewName "v8_context_snapshot.bin.tmp" -Force -ErrorAction SilentlyContinue
        Rename-Item -Path $tempRename -NewName "v8_context_snapshot.bin" -Force -ErrorAction SilentlyContinue
        Write-Log "  [+] Normalized snapshot filename casing to 'v8_context_snapshot.bin'" "Green"
    } catch {}
}

# SECTION B: Patch xpui.js
Write-Log "[*] Inspecting and patching xpui.js..." "Cyan"
$xpuiPatched = $false

# B1: Fix Spicetify 1.3.0 semver bug causing SyntaxError fatal black screen
$badSnackbar = "Spicetify.Snackbar.enqueueImageSnackbar="
if ($xpuiContent.Contains($badSnackbar)) {
    $xpuiContent = $xpuiContent.Replace($badSnackbar, "")
    $xpuiPatched = $true
    Write-Log "  [+] Fixed SyntaxError corruption (Resolved 1.3.0 startup black screen)" "Green"
}

# B2: Fix useNavigateStable runtime crash (Resolved Marketplace white screen)
$oldNav = "return(0,e.useNavigateStable)()"
$safeNav = 'return(()=>{try{return(0,e.useNavigateStable)()}catch(err){return Spicetify?.Platform?.History?.push||Spicetify?.Platform?.History?.navigate||(()=>({}))}})()'
if ($xpuiContent.Contains($oldNav)) {
    $xpuiContent = $xpuiContent.Replace($oldNav, $safeNav)
    $xpuiPatched = $true
    Write-Log "  [+] Injected safe fallback for useNavigateStable" "Green"
}

# B3: Fix RegistryContext useReducer on undefined (Resolved Spotify 1.3.0 crash modal)
$oldRegistry = "(0,i.useContext)(e.yv)"
$safeRegistry = "((0,i.useContext)(e.yv)||Spicetify?.Platform?.Registry||{entries:new Map()})"
if ($xpuiContent.Contains($oldRegistry) -and -not $xpuiContent.Contains($safeRegistry)) {
    $xpuiContent = $xpuiContent.Replace($oldRegistry, $safeRegistry)
    $xpuiPatched = $true
    Write-Log "  [+] Injected safe fallback for RegistryContext" "Green"
}

# B4: Scan all spicetify-routes-*.js custom apps
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

    # Rspack / Webpack .u Chunk Location Map Injection
    $uTarget = '.u=e=>""+(({'
    if ($chunkMapSb.Length -gt 0 -and $xpuiContent.Contains($uTarget)) {
        $xpuiContent = $xpuiContent.Replace($uTarget, $uTarget + $chunkMapSb.ToString())
        $xpuiPatched = $true
        Write-Log "  [+] Injected Custom Apps chunk map into .u loader" "Green"
    }

    # MiniCss Whitelist Injection (Ensures app stylesheets load cleanly)
    $cssTarget = '0!==d[e]&&({'
    if ($cssMapSb.Length -gt 0 -and $xpuiContent.Contains($cssTarget)) {
        $xpuiContent = $xpuiContent.Replace($cssTarget, $cssTarget + $cssMapSb.ToString())
        $xpuiPatched = $true
        Write-Log "  [+] Injected Custom Apps into MiniCss allowlist" "Green"
    }
}

if ($xpuiPatched) {
    [System.IO.File]::WriteAllText($xpuiJs, $xpuiContent, (New-Object System.Text.UTF8Encoding($false)))
    Write-Log "[SUCCESS] xpui.js successfully patched!" "Green"
} else {
    Write-Log "[INFO] xpui.js is already up-to-date." "Cyan"
}

# SECTION C: Patch helper/spicetifyWrapper.js
if (Test-Path $wrapperJs) {
    Write-Log "[*] Inspecting helper\spicetifyWrapper.js..." "Cyan"
    $wrapContent = [System.IO.File]::ReadAllText($wrapperJs, [System.Text.Encoding]::UTF8)
    $wrapPatched = $false

    # C1: Support window.rspackChunk (Fixes Spicetify.React undefined on 1.3.0+)
    $chunkTarget = 'window?.webpackChunkclient_web||window?.rspackChunkclient_web'
    $chunkFixed  = 'window?.webpackChunkclient_web||window?.rspackChunkclient_web||window?.rspackChunk'
    if ($wrapContent.Contains($chunkTarget) -and -not $wrapContent.Contains($chunkFixed)) {
        $wrapContent = $wrapContent.Replace($chunkTarget, $chunkFixed)
        $wrapPatched = $true
        Write-Log "  [+] Hooked window.rspackChunk in spicetifyWrapper.js" "Green"
    }

    # C2: Dynamic resolution & export of Spicetify.URI
    $uriTarget = 'Spicetify.React=f.find(m=>m?.useMemo),'
    $uriInjection = '(()=>{let u=f.find(m=>m?.NQG?.PLAYLIST_V2);if(u){let s=u.o_h("spotify:track:4uLU6hMCjMI75M1A2tKUQC")?.constructor;if(s){s.Type=u.NQG,s.from=u.o_h,s.fromString=u.Lce,s.idToHex=u.DY5,s.hexToId=u.dx2,Spicetify.URI=s}}})(),'
    if ($wrapContent.Contains($uriTarget) -and -not $wrapContent.Contains('Spicetify.URI=s')) {
        $wrapContent = $wrapContent.Replace($uriTarget, $uriTarget + $uriInjection)
        $wrapPatched = $true
        Write-Log "  [+] Injected dynamic Spicetify.URI parser export" "Green"
    }

    if ($wrapPatched) {
        [System.IO.File]::WriteAllText($wrapperJs, $wrapContent, (New-Object System.Text.UTF8Encoding($false)))
        Write-Log "[SUCCESS] spicetifyWrapper.js successfully patched!" "Green"
    } else {
        Write-Log "[INFO] spicetifyWrapper.js is already up-to-date." "Cyan"
    }
}

# SECTION D: Fix custom apps push headers in spicetify-routes-*.js
if ($routeFiles.Count -gt 0) {
    Write-Log "[*] Inspecting custom app route bundles..." "Cyan"
    foreach ($rf in $routeFiles) {
        $rc = [System.IO.File]::ReadAllText($rf.FullName, [System.Text.Encoding]::UTF8)
        $pushIdx = $rc.IndexOf(').push([[')
        if ($pushIdx -gt 0 -and $pushIdx -lt 300) {
            $fixedHead = '(("u">typeof self?self:global).rspackChunk||=[]' + $rc.Substring($pushIdx)
            [System.IO.File]::WriteAllText($rf.FullName, $fixedHead, (New-Object System.Text.UTF8Encoding($false)))
            Write-Log "  [+] Fixed bundle push chain for $($rf.Name)" "Green"
        }
    }
}

# SECTION E: Verification & Launch
Write-Log " [OK] All SpotX + Spicetify compatibility patches applied!" "Green"
Write-Log " Spotify 1.2.x & 1.3.x Rspack, Marketplace & extensions restored!" "Green"

if ($LaunchSpotify) {
    if (Test-Path $SpotifyExe) {
        Write-Log "[*] Launching Spotify..." "Cyan"
        Start-Process -FilePath $SpotifyExe
    }
}
