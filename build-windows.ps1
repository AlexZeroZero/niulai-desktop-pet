$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$goRoot = Join-Path $workspace '.tools\go-runtime\go'
$goPath = Join-Path $workspace '.tools\gopath'
$node = Join-Path $workspace '.tools\node-v22.19.0-win-x64'
$env:Path = (Join-Path $goRoot 'bin') + ';' + (Join-Path $goPath 'bin') + ';' + $node + ';' + $env:Path
$nsis = Get-ChildItem "$env:LOCALAPPDATA\electron-builder\Cache" -Recurse -Filter makensis.exe -ErrorAction SilentlyContinue | Where-Object { $_.DirectoryName -notmatch '\\Bin$' } | Select-Object -First 1
if ($nsis) { $env:Path = $nsis.DirectoryName + ';' + $env:Path }
$env:GOPATH = $goPath
& (Join-Path $goPath 'bin\wails.exe') build -clean -platform windows/amd64 -nsis
