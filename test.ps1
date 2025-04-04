chcp 65001 > $null

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

Write-Output "中文"
Pause