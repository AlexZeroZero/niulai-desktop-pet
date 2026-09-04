param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [int]$FrameCount = 48
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$sourceRoot = Join-Path $ProjectRoot 'assets\animation-source\rigged'
$outputPath = Join-Path $ProjectRoot 'frontend\public\sprites\niulai-atlas.png'
$rawPath = Join-Path $sourceRoot 'niulai-atlas-unquantized.png'
$contactPath = Join-Path $ProjectRoot 'animation-contact-coordinated-final.png'
$metricsPath = Join-Path $ProjectRoot 'animation-loop-metrics.csv'
$states = @('idle', 'run', 'cry', 'sleep', 'drag')
$cell = 256
$sourceCell = 320

foreach ($state in $states) {
    for ($index = 0; $index -lt $FrameCount; $index++) {
        $framePath = Join-Path $sourceRoot "$state\frame-$('{0:D3}' -f $index).png"
        if (-not (Test-Path -LiteralPath $framePath)) { throw "Missing coordinated frame: $framePath" }
    }
}

$atlas = [System.Drawing.Bitmap]::new($cell * $FrameCount, $cell * $states.Count, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$graphics = [System.Drawing.Graphics]::FromImage($atlas)
try {
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    for ($row = 0; $row -lt $states.Count; $row++) {
        for ($column = 0; $column -lt $FrameCount; $column++) {
            $framePath = Join-Path $sourceRoot "$($states[$row])\frame-$('{0:D3}' -f $column).png"
            $frame = [System.Drawing.Image]::FromFile($framePath)
            try {
                $destination = [System.Drawing.Rectangle]::new($column * $cell, $row * $cell, $cell, $cell)
                $source = [System.Drawing.Rectangle]::new(0, 0, $sourceCell, $sourceCell)
                $graphics.DrawImage($frame, $destination, $source, [System.Drawing.GraphicsUnit]::Pixel)
            } finally { $frame.Dispose() }
        }
    }
} finally { $graphics.Dispose() }
$atlas.Save($rawPath, [System.Drawing.Imaging.ImageFormat]::Png)
$atlas.Dispose()

$pngquant = Join-Path $ProjectRoot '.tools\pngquant\pngquant\pngquant.exe'
if (Test-Path -LiteralPath $pngquant) {
    & $pngquant --quality 55-88 --speed 1 --strip --force --output $outputPath -- $rawPath
    if ($LASTEXITCODE -ne 0) { throw 'pngquant failed to optimize the coordinated sprite atlas.' }
} else {
    Copy-Item -LiteralPath $rawPath -Destination $outputPath -Force
}

# Eight evenly spaced poses expose limb phasing and scale drift at a glance.
$samples = @(0, 6, 12, 18, 24, 30, 36, 42)
$previewCell = 160
$contact = [System.Drawing.Bitmap]::new($previewCell * $samples.Count, $previewCell * $states.Count, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$contactGraphics = [System.Drawing.Graphics]::FromImage($contact)
try {
    $contactGraphics.Clear([System.Drawing.Color]::FromArgb(255, 28, 29, 33))
    $contactGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    for ($row = 0; $row -lt $states.Count; $row++) {
        for ($column = 0; $column -lt $samples.Count; $column++) {
            $framePath = Join-Path $sourceRoot "$($states[$row])\frame-$('{0:D3}' -f $samples[$column]).png"
            $frame = [System.Drawing.Image]::FromFile($framePath)
            try {
                $destination = [System.Drawing.Rectangle]::new($column * $previewCell, $row * $previewCell, $previewCell, $previewCell)
                $contactGraphics.DrawImage($frame, $destination)
            } finally { $frame.Dispose() }
        }
    }
} finally { $contactGraphics.Dispose() }
$contact.Save($contactPath, [System.Drawing.Imaging.ImageFormat]::Png)
$contact.Dispose()

function Get-FrameDifference([string]$LeftPath, [string]$RightPath) {
    $size = 32
    $left = [System.Drawing.Bitmap]::new($size, $size)
    $right = [System.Drawing.Bitmap]::new($size, $size)
    $leftSource = [System.Drawing.Image]::FromFile($LeftPath)
    $rightSource = [System.Drawing.Image]::FromFile($RightPath)
    try {
        $g1 = [System.Drawing.Graphics]::FromImage($left)
        $g2 = [System.Drawing.Graphics]::FromImage($right)
        try {
            $g1.DrawImage($leftSource, 0, 0, $size, $size)
            $g2.DrawImage($rightSource, 0, 0, $size, $size)
        } finally { $g1.Dispose(); $g2.Dispose() }
        [double]$sum = 0
        for ($y = 0; $y -lt $size; $y++) {
            for ($x = 0; $x -lt $size; $x++) {
                $a = $left.GetPixel($x, $y)
                $b = $right.GetPixel($x, $y)
                $sum += [Math]::Abs($a.A - $b.A) + [Math]::Abs($a.R - $b.R) + [Math]::Abs($a.G - $b.G) + [Math]::Abs($a.B - $b.B)
            }
        }
        return $sum / ($size * $size * 4 * 255)
    } finally { $leftSource.Dispose(); $rightSource.Dispose(); $left.Dispose(); $right.Dispose() }
}

$metrics = foreach ($state in $states) {
    $differences = for ($index = 0; $index -lt $FrameCount; $index++) {
        $next = ($index + 1) % $FrameCount
        Get-FrameDifference (Join-Path $sourceRoot "$state\frame-$('{0:D3}' -f $index).png") (Join-Path $sourceRoot "$state\frame-$('{0:D3}' -f $next).png")
    }
    $average = ($differences | Measure-Object -Average).Average
    [pscustomobject]@{
        State = $state
        AverageNeighborDifference = [Math]::Round($average, 6)
        LoopSeamDifference = [Math]::Round($differences[-1], 6)
        SeamToAverageRatio = if ($average) { [Math]::Round($differences[-1] / $average, 3) } else { 0 }
    }
}
$metrics | Export-Csv -LiteralPath $metricsPath -NoTypeInformation -Encoding UTF8

Remove-Item -LiteralPath $rawPath -Force
Write-Output $outputPath
Write-Output $contactPath
Write-Output $metricsPath
