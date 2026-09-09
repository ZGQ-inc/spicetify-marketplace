<#
.SYNOPSIS
    SpotX + Spicetify 终极全自动兼容补丁 (适配 Spotify 1.2.x 与全新 1.3.x Rspack 架构)
.DESCRIPTION
    彻底解决以下核心故障：
    1. 彻底解决 Spotify 1.3.0 启动黑屏报错：
       "Uncaught SyntaxError: Unexpected identifier 'Spicetify'"
       (原因：Spicetify 版本比对逻辑缺陷误将 1.3.0 当作 < 1.2.78 注入了破坏语法的代码)
    2. 彻底解决 Spotify 1.3.0 Rspack 运行时兼容：
       Spicetify.React / Spicetify.ReactDOM 处于 undefined 状态导致 "出错了 请尝试重新加载此页面" 弹窗
    3. 彻底解决 Marketplace 消失 / 报错：
       "useNavigateStable must be used within a StableUseNavigateProvider"
    4. 彻底解决 Spotify 1.3.0 页面抛出 RegistryContext 错误
    5. 彻底解决 Rspack 下 Custom Apps 分包推送失败：
       "window.push is not a function" 与 "Loading chunk spicetify-routes-marketplace failed"
    6. 自动为 Rspack 分包表 (.u) 与 MiniCss 白名单注入所有 Custom Apps
    7. 自动恢复 Spicetify.URI 模块解析
#>

[CmdletBinding()]
param(
    [switch]$Quiet,
    [switch]$LaunchSpotify
)

function Write-Log {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    if (-not $Quiet) {
        Write-Host $Message -ForegroundColor $Color
    }
}

Write-Log " SpotX + Spicetify 终极全自动兼容补丁 (v2.0)" "Cyan"
Write-Log " 支持 Spotify 1.2.x 及最新 1.3.x (Rspack 架构)" "Cyan"

# 1. 关闭正在运行的 Spotify 进程
$spotifyProcs = Get-Process -Name "Spotify" -ErrorAction SilentlyContinue
if ($spotifyProcs) {
    Write-Log "[INFO] 正在关闭运行中的 Spotify 进程..." "Yellow"
    $spotifyProcs | Stop-Process -Force
    Start-Sleep -Milliseconds 800
}

# 2. 定位 Spotify 与 Spicetify 目录
$SpotifyDir = Join-Path $env:APPDATA "Spotify"
if (-not (Test-Path $SpotifyDir)) {
    $SpotifyDir = Join-Path $env:LOCALAPPDATA "Spotify"
}
$SpotifyAppsDir = Join-Path $SpotifyDir "Apps\xpui"
$xpuiJs = Join-Path $SpotifyAppsDir "xpui.js"
$wrapperJs = Join-Path $SpotifyAppsDir "helper\spicetifyWrapper.js"

if (-not (Test-Path $xpuiJs)) {
    Write-Log "[ERROR] 未找到 Spotify xpui.js 文件，路径不存在: $xpuiJs" "Red"
    Write-Log "请确保已安装 Spotify 并运行过 Spicetify apply。" "Yellow"
    exit 1
}

Write-Log "[+] 找到 Spotify 核心路径: $SpotifyAppsDir" "Green"

# 3. 修补 xpui.js
Write-Log "[INFO] 正在检查并修补 xpui.js..." "Cyan"
$xpuiContent = [System.IO.File]::ReadAllText($xpuiJs, [System.Text.Encoding]::UTF8)
$xpuiPatched = $false

# 3a. 修复 Spicetify 1.3.0 版本比对 Bug 导致的 SyntaxError 致命黑屏
# 根因: Spicetify 把 1.3.0 误判为旧版，替换代码造成 return(0,f.useCallback)Spicetify.Snackbar.enqueueImageSnackbar=((...
$badSnackbar = "Spicetify.Snackbar.enqueueImageSnackbar="
if ($xpuiContent.Contains($badSnackbar)) {
    $xpuiContent = $xpuiContent.Replace($badSnackbar, "")
    $xpuiPatched = $true
    Write-Log "  [+] 成功修复 Spicetify 语法错误 (解决启动黑屏 SyntaxError)" "Green"
}

# 3b. 修复 useNavigateStable 路由抛错 (解决 Marketplace 页面白屏崩溃)
$oldNav = "return(0,e.useNavigateStable)()"
$safeNav = 'return(()=>{try{return(0,e.useNavigateStable)()}catch(err){return Spicetify?.Platform?.History?.push||Spicetify?.Platform?.History?.navigate||(()=>({}))}})()'
if ($xpuiContent.Contains($oldNav)) {
    $xpuiContent = $xpuiContent.Replace($oldNav, $safeNav)
    $xpuiPatched = $true
    Write-Log "  [+] 成功注入 useNavigateStable 安全降级函数" "Green"
}

# 3c. 修复 Spotify 1.3.0 RegistryContext 抛错 (解决 useReducer on undefined 弹窗)
$oldRegistry = "(0,i.useContext)(e.yv)"
$safeRegistry = "((0,i.useContext)(e.yv)||Spicetify?.Platform?.Registry||{entries:new Map()})"
if ($xpuiContent.Contains($oldRegistry) -and -not $xpuiContent.Contains($safeRegistry)) {
    $xpuiContent = $xpuiContent.Replace($oldRegistry, $safeRegistry)
    $xpuiPatched = $true
    Write-Log "  [+] 成功注入 RegistryContext 安全兜底" "Green"
}

# 3d. 修复 Spotify 1.3.0 Rspack 下 Custom Apps 分包映射 (.u 与 MiniCss)
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
        $chunkCheckPattern = ':"' + $bundleName + '"'
        if (-not $xpuiContent.Contains($chunkCheckPattern)) {
            [void]$chunkMapSb.Append("$($appId):`"$bundleName`",")
        }
        $cssCheckPattern = "$($appId):1"
        if (-not $xpuiContent.Contains($cssCheckPattern)) {
            [void]$cssMapSb.Append("$($appId):1,")
        }
        $appId++
    }

    # Webpack / Rspack Chunk Map (.u)
    $uTarget = '.u=e=>""+(({'
    if ($chunkMapSb.Length -gt 0 -and $xpuiContent.Contains($uTarget)) {
        $xpuiContent = $xpuiContent.Replace($uTarget, $uTarget + $chunkMapSb.ToString())
        $xpuiPatched = $true
        Write-Log "  [+] 成功注入 Rspack 分包定位表 (.u)" "Green"
    }

    # MiniCss whitelist
    $cssTarget = '0!==d[e]&&({'
    if ($cssMapSb.Length -gt 0 -and $xpuiContent.Contains($cssTarget)) {
        $xpuiContent = $xpuiContent.Replace($cssTarget, $cssTarget + $cssMapSb.ToString())
        $xpuiPatched = $true
        Write-Log "  [+] 成功注入 MiniCss 允许列表" "Green"
    }
}

if ($xpuiPatched) {
    [System.IO.File]::WriteAllText($xpuiJs, $xpuiContent, (New-Object System.Text.UTF8Encoding($false)))
    Write-Log "[SUCCESS] xpui.js 修补完成！" "Green"
} else {
    Write-Log "[INFO] xpui.js 无需更新。" "Cyan"
}

# 4. 修补 helper/spicetifyWrapper.js
if (Test-Path $wrapperJs) {
    Write-Log "[INFO] 正在检查并修补 spicetifyWrapper.js..." "Cyan"
    $wrapContent = [System.IO.File]::ReadAllText($wrapperJs, [System.Text.Encoding]::UTF8)
    $wrapPatched = $false

    # 4a. 兼容 window.rspackChunk (解决 Spicetify.React undefined)
    $chunkTarget = 'window?.webpackChunkclient_web||window?.rspackChunkclient_web'
    $chunkFixed  = 'window?.webpackChunkclient_web||window?.rspackChunkclient_web||window?.rspackChunk'
    if ($wrapContent.Contains($chunkTarget) -and -not $wrapContent.Contains($chunkFixed)) {
        $wrapContent = $wrapContent.Replace($chunkTarget, $chunkFixed)
        $wrapPatched = $true
        Write-Log "  [+] 成功兼容 Spotify 1.3.0 Rspack 运行时" "Green"
    }

    # 4b. 注入 Spicetify.URI 动态解析与 Snackbar 兜底
    $uriTarget = 'Spicetify.React=f.find(m=>m?.useMemo),'
    $uriInjection = '(()=>{let u=f.find(m=>m?.NQG?.PLAYLIST_V2);if(u){let s=u.o_h("spotify:track:4uLU6hMCjMI75M1A2tKUQC")?.constructor;if(s){s.Type=u.NQG,s.from=u.o_h,s.fromString=u.Lce,s.idToHex=u.DY5,s.hexToId=u.dx2,Spicetify.URI=s}}})(),'
    if ($wrapContent.Contains($uriTarget) -and -not $wrapContent.Contains('Spicetify.URI=s')) {
        $wrapContent = $wrapContent.Replace($uriTarget, $uriTarget + $uriInjection)
        $wrapPatched = $true
        Write-Log "  [+] 成功接入 Spicetify.URI 自动化导出" "Green"
    }

    if ($wrapPatched) {
        [System.IO.File]::WriteAllText($wrapperJs, $wrapContent, (New-Object System.Text.UTF8Encoding($false)))
        Write-Log "[SUCCESS] spicetifyWrapper.js 更新完成！" "Green"
    } else {
        Write-Log "[INFO] spicetifyWrapper.js 无需更新。" "Cyan"
    }
}

# 5. 修复所有 spicetify-routes-*.js 文件头中的 Rspack 推送链 (解决 window.push is not a function)
$routeFiles = Get-ChildItem -Path $SpotifyAppsDir -Filter "spicetify-routes-*.js" -ErrorAction SilentlyContinue
foreach ($rf in $routeFiles) {
    $rc = [System.IO.File]::ReadAllText($rf.FullName, [System.Text.Encoding]::UTF8)
    $pushIdx = $rc.IndexOf(').push([[')
    if ($pushIdx -gt 0 -and $pushIdx -lt 300) {
        $fixedHead = '(("u">typeof self?self:global).rspackChunk||=[]' + $rc.Substring($pushIdx)
        [System.IO.File]::WriteAllText($rf.FullName, $fixedHead, (New-Object System.Text.UTF8Encoding($false)))
        Write-Log "  [+] 成功修正 $($rf.Name) Rspack 推送链" "Green"
    }
}

Write-Log " 全部兼容补丁修补完毕！Spotify 1.2.x / 1.3.x 与 Marketplace 已完美恢复！" "Green"

if ($LaunchSpotify) {
    $spotifyExe = Join-Path $SpotifyDir "Spotify.exe"
    if (Test-Path $spotifyExe) {
        Write-Log "[INFO] 正在启动 Spotify..." "Cyan"
        Start-Process -FilePath $spotifyExe
    }
}
