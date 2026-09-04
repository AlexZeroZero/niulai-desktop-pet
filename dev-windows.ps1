$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$goRoot = Join-Path $workspace '.tools\go-runtime\go'
$goPath = Join-Path $workspace '.tools\gopath'
$node = Join-Path $workspace '.tools\node-v22.19.0-win-x64'
$env:Path = (Join-Path $goRoot 'bin') + ';' + (Join-Path $goPath 'bin') + ';' + $node + ';' + $env:Path
$env:GOPATH = $goPath
& (Join-Path $goPath 'bin\wails.exe') dev
