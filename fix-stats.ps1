Write-Output "Trying to fix custom-app stats..."
if ($downloadUrl -match "stats-v1\.1\.2/") {
    Write-Output "Stats version is 1.1.2, patching index.js..."

    $target = "$env:APPDATA\spicetify\CustomApps\stats\index.js"
    $backup = "$target.bak"
    Copy-Item -Path $target -Destination $backup -Force
    Write-Output "create index.js.bak"
    $content = Get-Content -Path $target -Raw
    $original = 'const resizeHost = document.querySelector(".Root__main-view .os-resize-observer-host") ?? document.querySelector(".Root__main-view .os-size-observer");'
    $replace = 'const resizeHost = document.querySelector(".Root__main-view .os-resize-observer-host") ?? document.querySelector(".Root__main-view .os-size-observer") ?? document.querySelector(".Root__main-view");'

    $newContent = $content -replace [regex]::Escape($original), [System.Text.RegularExpressions.Regex]::Escape($replace)
    [System.IO.File]::WriteAllText($target, $newContent, [System.Text.Encoding]::UTF8)
    Write-Output "Replace completed."
}
else {
    Write-Output "Stats version is not 1.1.2, skip."
}