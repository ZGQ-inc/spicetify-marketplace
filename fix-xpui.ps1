<#
.SYNOPSIS
Fixes SpotX + Spicetify compatibility issue (Marketplace missing and useNavigateStable error).

.DESCRIPTION
SpotX merges webpack modules from v8_context_snapshot.bin and xpui-snapshot.js into a single
xpui.js bundle and points index.html to it, removing xpui-snapshot.js.
Spicetify assumes xpui-snapshot.js is present and injects custom app routes into xpui-modules.js,
which the SpotX-modified client never loads.
This script patches xpui.js directly to:
1. Eliminate "useNavigateStable must be used within a StableUseNavigateProvider" by providing safe fallback navigation.
2. Inject Spicetify Custom Apps (Marketplace, stats, Enhancify, lyrics-plus, etc.) routes, nav links, and webpack chunk maps into xpui.js.
#>

[CmdletBinding()]
param(
    [string]$SpotifyAppsDir = "$env:APPDATA\Spotify\Apps\xpui",
    [string]$SpicetifyConfig = "$env:APPDATA\spicetify\config-xpui.ini"
)

$ErrorActionPreference = 'Stop'
Write-Host " SpotX + Spicetify Compatibility Patcher   " -ForegroundColor Cyan

$xpuiJs = Join-Path $SpotifyAppsDir "xpui.js"
if (-not (Test-Path $xpuiJs)) {
    Write-Warning "xpui.js not found at $xpuiJs. Make sure Spotify and Spicetify are installed."
    return
}

# 1. Read custom apps from config-xpui.ini
$customApps = @()
if (Test-Path $SpicetifyConfig) {
    $iniContent = Get-Content $SpicetifyConfig -Raw
    if ($iniContent -match 'custom_apps\s*=\s*([^\r\n]+)') {
        $customApps = ($matches[1] -split '\|') | Where-Object { $_ -and $_.Trim() -ne "" }
    }
}

if ($customApps.Count -eq 0) {
    # Default fallback if config not found
    $customApps = @('lyrics-plus', 'marketplace', 'Enhancify', 'stats')
}
Write-Host "Custom apps to inject: $($customApps -join ', ')" -ForegroundColor Green

# 2. Read xpui.js
Write-Host "Reading xpui.js ($((Get-Item $xpuiJs).Length) bytes)..."
$content = [System.IO.File]::ReadAllText($xpuiJs, [System.Text.Encoding]::UTF8)

# Check if already patched for custom apps
$patched = $false

# 3. Patch useNavigateStable error
$navTarget = 'if(!e)throw Error("useNavigateStable must be used within a StableUseNavigateProvider");'
$navReplace = 'if(!e)return(...t)=>{let[i]=t;try{"number"==typeof i?window.history.go(i):Spicetify?.Platform?.History?.push(i)}catch(e){}};'
if ($content.Contains($navTarget)) {
    $content = $content.Replace($navTarget, $navReplace)
    Write-Host "[OK] Patched useNavigateStable fallback." -ForegroundColor Green
    $patched = $true
} else {
    Write-Host "[SKIP] useNavigateStable already patched or pattern not found." -ForegroundColor Yellow
}

# 4. Inject Custom Apps if not present
if ($content.Contains('spicetifyApp0')) {
    Write-Host "[SKIP] Custom apps already injected into xpui.js." -ForegroundColor Yellow
} else {
    # 4a. Build injection strings
    $lazySb = New-Object System.Text.StringBuilder
    $routeSb = New-Object System.Text.StringBuilder
    $chunkMapSb = New-Object System.Text.StringBuilder
    $cssMapSb = New-Object System.Text.StringBuilder
    $appNamesSb = New-Object System.Text.StringBuilder

    for ($i = 0; $i -lt $customApps.Count; $i++) {
        $app = $customApps[$i]
        $routeName = "spicetify-routes-$app"

        [void]$lazySb.Append(",spicetifyApp$i=D.lazy((()=>i.e(`"$routeName`").then(i.bind(i,`"$routeName`"))))")
        [void]$routeSb.Append("(0,y.jsx)(eO.qh,{path:`"/$app/*`",pathV6:`"/$app/*`",element:(0,y.jsx)(spicetifyApp$i,{})}),")
        [void]$chunkMapSb.Append("`"$routeName`":`"$routeName`",")
        [void]$cssMapSb.Append("`"$routeName`":1,")
        [void]$appNamesSb.Append("`"$app`",")
    }

    $lazyCode = $lazySb.ToString()
    $routeCode = $routeSb.ToString()
    $chunkMapCode = $chunkMapSb.ToString()
    $cssMapCode = $cssMapSb.ToString()
    $appNamesArray = $appNamesSb.ToString()

    # 4b. Insert Lazy components
    $lazyTarget = 'DesktopUpdateNotificationInner:e}=await i.e(8168).then(i.bind(i,98347));return{default:e}})'
    if ($content.Contains($lazyTarget)) {
        $content = $content.Replace($lazyTarget, $lazyTarget + $lazyCode)
        Write-Host "[OK] Injected custom app lazy loaders." -ForegroundColor Green
        $patched = $true
    } else {
        Write-Warning "Could not find lazy loader insertion point in xpui.js!"
    }

    # 4c. Insert Routes
    $routeTarget = '(0,y.jsx)(eO.qh,{path:"/settings"'
    if ($content.Contains($routeTarget)) {
        $content = $content.Replace($routeTarget, $routeCode + $routeTarget)
        Write-Host "[OK] Injected custom app routes." -ForegroundColor Green
        $patched = $true
    } else {
        Write-Warning "Could not find route insertion point in xpui.js!"
    }

    # 4d. Insert NavLinks
    $navLinkTarget = 'c&&(0,y.jsxs)(dh,{children:[o?(0,y.jsx)(d_,{}):(0,y.jsx)(dm,{}),(0,y.jsx)(dl,{className:dt})]})'
    $navLinkReplace = "c&&(0,y.jsxs)(dh,{children:[o?(0,y.jsx)(d_,{}):(0,y.jsx)(dm,{}),(0,y.jsx)(dl,{className:dt}),Spicetify._renderNavLinks([$appNamesArray], true)]})"
    if ($content.Contains($navLinkTarget)) {
        $content = $content.Replace($navLinkTarget, $navLinkReplace)
        Write-Host "[OK] Injected custom app navigation buttons." -ForegroundColor Green
        $patched = $true
    } else {
        Write-Warning "Could not find navigation button insertion point in xpui.js!"
    }

    # 4e. Insert Webpack chunk maps
    $uTarget = '.u=e=>""+(({'
    if ($content.Contains($uTarget)) {
        $content = $content.Replace($uTarget, $uTarget + $chunkMapCode)
        Write-Host "[OK] Injected chunk map (.u)." -ForegroundColor Green
        $patched = $true
    }

    $objTarget = '{1328:"xpui-pip-mini-player"'
    if ($content.Contains($objTarget)) {
        $content = $content.Replace($objTarget, '{' + $chunkMapCode + '1328:"xpui-pip-mini-player"')
        Write-Host "[OK] Injected chunk map (chunk names)." -ForegroundColor Green
        $patched = $true
    }

    # 4f. Insert MiniCss allowlist
    $cssTarget = '0!==d[e]&&({'
    if ($content.Contains($cssTarget)) {
        $content = $content.Replace($cssTarget, $cssTarget + $cssMapCode)
        Write-Host "[OK] Injected MiniCss stylesheet allowlist." -ForegroundColor Green
        $patched = $true
    }
}

if ($patched) {
    Write-Host "Writing patched xpui.js ($($content.Length) chars)..."
    [System.IO.File]::WriteAllText($xpuiJs, $content, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "Successfully patched Spotify xpui.js! Marketplace and Custom Apps are ready!" -ForegroundColor Cyan
} else {
    Write-Host "No changes were needed." -ForegroundColor Green
}
