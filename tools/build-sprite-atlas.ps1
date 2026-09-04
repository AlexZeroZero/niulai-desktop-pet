param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$cell = 320
$columns = 4
$rows = @('idle', 'run', 'cry', 'sleep', 'drag')
$sourceDir = Join-Path $ProjectRoot 'assets\animation-source\base'
$idleStripPath = Join-Path $ProjectRoot 'assets\animation-source\generated\idle-fullbody-strip-v1.png'
$dragStripPath = Join-Path $ProjectRoot 'assets\animation-source\generated\drag-strip-v1.png'
$outputDir = Join-Path $ProjectRoot 'assets\animation-source\generated'
$pngPath = Join-Path $outputDir 'niulai-key-atlas.png'
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

function Get-SourceRectangle {
    param([System.Drawing.Image]$Image, [string]$Name, [int]$Column)
    if ($Name -eq 'idle' -or $Name -eq 'drag') {
        $left = [Math]::Floor($Image.Width * $Column / 4)
        $right = [Math]::Floor($Image.Width * ($Column + 1) / 4)
        $padding = if ($Name -eq 'idle') { 45 } else { 0 }
        return [System.Drawing.Rectangle]::new($left, $padding, $right - $left, $Image.Height - $padding * 2)
    }
    return [System.Drawing.Rectangle]::new(0, 0, $Image.Width, $Image.Height)
}

function Get-AlphaBounds {
    param([System.Drawing.Bitmap]$Image, [System.Drawing.Rectangle]$Area)
    $minX = $Area.Right; $minY = $Area.Bottom; $maxX = $Area.Left - 1; $maxY = $Area.Top - 1
    for ($y = $Area.Top; $y -lt $Area.Bottom; $y++) {
        for ($x = $Area.Left; $x -lt $Area.Right; $x++) {
            if ($Image.GetPixel($x, $y).A -gt 6) {
                if ($x -lt $minX) { $minX = $x }; if ($x -gt $maxX) { $maxX = $x }
                if ($y -lt $minY) { $minY = $y }; if ($y -gt $maxY) { $maxY = $y }
            }
        }
    }
    if ($maxX -lt $minX -or $maxY -lt $minY) { throw 'Animation frame is fully transparent.' }
    return [System.Drawing.Rectangle]::new($minX, $minY, $maxX - $minX + 1, $maxY - $minY + 1)
}

$atlas = [System.Drawing.Bitmap]::new($cell * $columns, $cell * $rows.Count, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$graphics = [System.Drawing.Graphics]::FromImage($atlas)
$graphics.Clear([System.Drawing.Color]::Transparent)
$graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
$graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
$graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality

try {
    for ($row = 0; $row -lt $rows.Count; $row++) {
        $name = $rows[$row]; $frames = @(); $maxWidth = 1; $maxHeight = 1
        for ($column = 0; $column -lt $columns; $column++) {
            $path = if ($name -eq 'idle') { $idleStripPath } elseif ($name -eq 'drag') { $dragStripPath } else { Join-Path $sourceDir "$name-$column.png" }
            $image = [System.Drawing.Bitmap]::FromFile($path)
            try {
                $area = Get-SourceRectangle -Image $image -Name $name -Column $column
                $bounds = Get-AlphaBounds -Image $image -Area $area
                $frames += [pscustomobject]@{ Path = $path; Bounds = $bounds }
                $maxWidth = [Math]::Max($maxWidth, $bounds.Width); $maxHeight = [Math]::Max($maxHeight, $bounds.Height)
            } finally { $image.Dispose() }
        }

        # One shared scale per action prevents frame-by-frame body growth.
        $scale = [Math]::Min(292.0 / $maxHeight, 304.0 / $maxWidth)
        for ($column = 0; $column -lt $columns; $column++) {
            $frame = $frames[$column]; $image = [System.Drawing.Bitmap]::FromFile($frame.Path)
            try {
                $targetWidth = [Math]::Max(1, [Math]::Round($frame.Bounds.Width * $scale)); $targetHeight = [Math]::Max(1, [Math]::Round($frame.Bounds.Height * $scale))
                $x = $column * $cell + [Math]::Floor(($cell - $targetWidth) / 2)
                $localY = if ($name -eq 'drag') { 10 } else { $cell - $targetHeight - 10 }
                $y = $row * $cell + $localY
                $destination = [System.Drawing.Rectangle]::new($x, $y, $targetWidth, $targetHeight)
                # The first legacy running key faces the opposite direction
                # from the other three. Interpolating it directly makes the
                # face, shoulders and legs turn through the body. Mirror only
                # that source key so all poses share one camera direction.
                if ($name -eq 'run' -and $column -eq 0) {
                    $saved = $graphics.Save()
                    try {
                        $graphics.TranslateTransform($x + $targetWidth, 0)
                        $graphics.ScaleTransform(-1, 1)
                        $flippedDestination = [System.Drawing.Rectangle]::new(0, $y, $targetWidth, $targetHeight)
                        $graphics.DrawImage($image, $flippedDestination, $frame.Bounds, [System.Drawing.GraphicsUnit]::Pixel)
                    } finally { $graphics.Restore($saved) }
                } else {
                    $graphics.DrawImage($image, $destination, $frame.Bounds, [System.Drawing.GraphicsUnit]::Pixel)
                }
            } finally { $image.Dispose() }
        }
    }
} finally { $graphics.Dispose() }

$atlas.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)
$atlas.Dispose()
Write-Output $pngPath
