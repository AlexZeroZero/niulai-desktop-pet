param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$KeysPath,
    [int]$PoseCount = 12,
    [int]$HoldFrames = 4
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$atlasPath = Join-Path $ProjectRoot 'frontend\public\sprites\niulai-atlas.png'
$keysRoot = if ($KeysPath) { $KeysPath } else { Join-Path $ProjectRoot 'assets\animation-source\controlled-arm-gait-keys' }
$workPath = Join-Path $ProjectRoot 'assets\animation-source\generated\niulai-atlas-2d-run-raw.png'

$source = [System.Drawing.Bitmap]::FromFile($atlasPath)
$atlas = [System.Drawing.Bitmap]::new($source.Width, $source.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$graphics = [System.Drawing.Graphics]::FromImage($atlas)
try {
    $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $graphics.DrawImage($source, 0, 0)
    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

    # Clear the previous run row completely. Twelve readable gait poses with
    # locked wrists are held for four display frames each: no warping/morphing.
    $graphics.FillRectangle([System.Drawing.Brushes]::Transparent, 0, 256, $atlas.Width, 256)
    for ($index = 0; $index -lt 48; $index++) {
        $key = [int][Math]::Floor($index / $HoldFrames) % $PoseCount
        $frame = [System.Drawing.Image]::FromFile((Join-Path $keysRoot ('frame-{0:D2}.png' -f $key)))
        try {
            $destination = [System.Drawing.Rectangle]::new($index * 256, 256, 256, 256)
            $sourceRect = [System.Drawing.Rectangle]::new(0, 0, 320, 320)
            $graphics.DrawImage($frame, $destination, $sourceRect, [System.Drawing.GraphicsUnit]::Pixel)
        } finally { $frame.Dispose() }
    }
} finally { $graphics.Dispose(); $source.Dispose() }

$atlas.Save($workPath, [System.Drawing.Imaging.ImageFormat]::Png)
$atlas.Dispose()

$pngquant = Join-Path $ProjectRoot '.tools\pngquant\pngquant\pngquant.exe'
if (Test-Path -LiteralPath $pngquant) {
    & $pngquant --quality 60-90 --speed 1 --strip --force --output $atlasPath -- $workPath
    if ($LASTEXITCODE -ne 0) { throw 'pngquant failed to optimize the 2D run atlas.' }
} else {
    Copy-Item -LiteralPath $workPath -Destination $atlasPath -Force
}
Remove-Item -LiteralPath $workPath -Force
Write-Output $atlasPath
