chcp 65001

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

Write-Output "中文"
Pause