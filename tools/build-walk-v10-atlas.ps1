param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$sourceDirectory = Join-Path $ProjectRoot 'assets\animation-video\walk-v10\frames-72-2d'
$outputPath = Join-Path $ProjectRoot 'frontend\public\sprites\niulai-walk-v10.png'
$rawPath = Join-Path $ProjectRoot '.tools\niulai-walk-v10-unquantized.png'
$frameCount = 72
$columns = 24
$rows = 3
$cell = 256

$frames = @(Get-ChildItem -LiteralPath $sourceDirectory -Filter 'frame-*.png' -File | Sort-Object Name)
if ($frames.Count -ne $frameCount) {
    throw "Expected $frameCount walk frames, found $($frames.Count)."
}

# Every authored frame shares the same 512x512 registration. Use one fixed
# source rectangle for all frames so the feet stay anchored and no per-frame
# auto-cropping can introduce positional shimmer.
$sourceRectangle = [System.Drawing.Rectangle]::new(64, 96, 384, 384)
$sheet = [System.Drawing.Bitmap]::new($columns * $cell, $rows * $cell, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$graphics = [System.Drawing.Graphics]::FromImage($sheet)
try {
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    for ($index = 0; $index -lt $frameCount; $index++) {
        $frame = [System.Drawing.Bitmap]::FromFile($frames[$index].FullName)
        try {
            if ($frame.Width -ne 512 -or $frame.Height -ne 512) {
                throw "Unexpected frame size: $($frames[$index].FullName)"
            }
            $x = ($index % $columns) * $cell
            $y = [Math]::Floor($index / $columns) * $cell
            $destination = [System.Drawing.Rectangle]::new($x, $y, $cell, $cell)
            $graphics.DrawImage($frame, $destination, $sourceRectangle, [System.Drawing.GraphicsUnit]::Pixel)
        } finally {
            $frame.Dispose()
        }
    }
} finally {
    $graphics.Dispose()
}

$sheet.Save($rawPath, [System.Drawing.Imaging.ImageFormat]::Png)
$sheet.Dispose()

$pngquant = Join-Path $ProjectRoot '.tools\pngquant\pngquant\pngquant.exe'
if (Test-Path -LiteralPath $pngquant) {
    & $pngquant --quality 65-90 --speed 1 --strip --force --output $outputPath -- $rawPath
    if ($LASTEXITCODE -ne 0) { throw 'pngquant failed to optimize the walk atlas.' }
} else {
    Copy-Item -LiteralPath $rawPath -Destination $outputPath -Force
}

Remove-Item -LiteralPath $rawPath -Force
Write-Output $outputPath
