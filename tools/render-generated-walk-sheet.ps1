param(
    [Parameter(Mandatory = $true)]
    [string]$SheetPath,
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'assets\animation-video\walk-v1\frames'),
    [int]$Columns = 4,
    [int]$Rows = 3,
    [int]$CellInset = 10,
    [switch]$AutoGridCrop,
    [int]$NormalizeHeight = 0,
    [ValidateSet('blue', 'green')]
    [string]$Chroma = 'blue'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

function Get-LongestConsecutiveRun([int[]]$Values) {
    if (-not $Values -or $Values.Count -eq 0) { return $null }
    $bestStart = $Values[0]
    $bestEnd = $Values[0]
    $runStart = $Values[0]
    $previous = $Values[0]
    foreach ($value in $Values | Select-Object -Skip 1) {
        if ($value -ne ($previous + 1)) {
            if (($previous - $runStart) -gt ($bestEnd - $bestStart)) {
                $bestStart = $runStart
                $bestEnd = $previous
            }
            $runStart = $value
        }
        $previous = $value
    }
    if (($previous - $runStart) -gt ($bestEnd - $bestStart)) {
        $bestStart = $runStart
        $bestEnd = $previous
    }
    return [pscustomobject]@{ Start = [int]$bestStart; End = [int]$bestEnd }
}

$canvasSize = 512
$targetBottom = 478

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
Get-ChildItem -LiteralPath $OutputDirectory -Filter 'frame-*.png' -File -ErrorAction SilentlyContinue |
    Remove-Item -Force

$sheet = [System.Drawing.Bitmap]::new($SheetPath)
try {
    if (($sheet.Width % $Columns) -ne 0 -or ($sheet.Height % $Rows) -ne 0) {
        throw "Sprite sheet dimensions must divide evenly into a ${Columns}x${Rows} grid."
    }

    $cellWidth = [int]($sheet.Width / $Columns)
    $cellHeight = [int]($sheet.Height / $Rows)
    $prepared = @()
    $heights = @()

    for ($index = 0; $index -lt ($Columns * $Rows); $index++) {
        $column = $index % $Columns
        $row = [int][Math]::Floor($index / $Columns)
        $cellOriginX = $column * $cellWidth
        $cellOriginY = $row * $cellHeight
        $leftInset = $CellInset
        $rightInset = $CellInset
        $topInset = $CellInset
        $bottomInset = $CellInset

        if ($AutoGridCrop) {
            $activeColumns = @()
            for ($localX = 0; $localX -lt $cellWidth; $localX++) {
                $chromaSamples = 0
                $sampleCount = 0
                for ($localY = 0; $localY -lt $cellHeight; $localY += 4) {
                    $sample = $sheet.GetPixel($cellOriginX + $localX, $cellOriginY + $localY)
                    $primary = if ($Chroma -eq 'green') { [int]$sample.G } else { [int]$sample.B }
                    $secondary = if ($Chroma -eq 'green') { [Math]::Max([int]$sample.R, [int]$sample.B) } else { [Math]::Max([int]$sample.R, [int]$sample.G) }
                    if ($primary -gt 90 -and ($primary - $secondary) -gt 20) { $chromaSamples++ }
                    $sampleCount++
                }
                if ($chromaSamples -ge [Math]::Max(2, [int]($sampleCount * 0.18))) { $activeColumns += $localX }
            }

            $activeRows = @()
            for ($localY = 0; $localY -lt $cellHeight; $localY++) {
                $chromaSamples = 0
                $sampleCount = 0
                for ($localX = 0; $localX -lt $cellWidth; $localX += 4) {
                    $sample = $sheet.GetPixel($cellOriginX + $localX, $cellOriginY + $localY)
                    $primary = if ($Chroma -eq 'green') { [int]$sample.G } else { [int]$sample.B }
                    $secondary = if ($Chroma -eq 'green') { [Math]::Max([int]$sample.R, [int]$sample.B) } else { [Math]::Max([int]$sample.R, [int]$sample.G) }
                    if ($primary -gt 90 -and ($primary - $secondary) -gt 20) { $chromaSamples++ }
                    $sampleCount++
                }
                if ($chromaSamples -ge [Math]::Max(2, [int]($sampleCount * 0.18))) { $activeRows += $localY }
            }

            if ($activeColumns.Count -gt 0 -and $activeRows.Count -gt 0) {
                $columnRun = Get-LongestConsecutiveRun $activeColumns
                $rowRun = Get-LongestConsecutiveRun $activeRows
                $leftInset = $columnRun.Start
                $rightInset = $cellWidth - 1 - $columnRun.End
                $topInset = $rowRun.Start
                $bottomInset = $cellHeight - 1 - $rowRun.End
            }
        }

        $sourceRect = [System.Drawing.Rectangle]::new(
            $cellOriginX + $leftInset,
            $cellOriginY + $topInset,
            $cellWidth - $leftInset - $rightInset,
            $cellHeight - $topInset - $bottomInset
        )

        $cutout = [System.Drawing.Bitmap]::new($sourceRect.Width, $sourceRect.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $graphics = [System.Drawing.Graphics]::FromImage($cutout)
        try {
            $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
            $graphics.DrawImage($sheet, [System.Drawing.Rectangle]::new(0, 0, $cutout.Width, $cutout.Height), $sourceRect, [System.Drawing.GraphicsUnit]::Pixel)
        } finally {
            $graphics.Dispose()
        }

        $gridLineRows = [System.Collections.Generic.HashSet[int]]::new()
        $gridLineColumns = [System.Collections.Generic.HashSet[int]]::new()
        for ($y = 0; $y -lt $cutout.Height; $y++) {
            $darkCount = 0
            for ($x = 0; $x -lt $cutout.Width; $x++) {
                $sample = $cutout.GetPixel($x, $y)
                if ([Math]::Max([int]$sample.R, [Math]::Max([int]$sample.G, [int]$sample.B)) -lt 45) { $darkCount++ }
            }
            if ($darkCount -gt ($cutout.Width * 0.45)) { [void]$gridLineRows.Add($y) }
        }
        for ($x = 0; $x -lt $cutout.Width; $x++) {
            $darkCount = 0
            for ($y = 0; $y -lt $cutout.Height; $y++) {
                $sample = $cutout.GetPixel($x, $y)
                if ([Math]::Max([int]$sample.R, [Math]::Max([int]$sample.G, [int]$sample.B)) -lt 45) { $darkCount++ }
            }
            if ($darkCount -gt ($cutout.Height * 0.45)) { [void]$gridLineColumns.Add($x) }
        }

        $minX = $cutout.Width
        $minY = $cutout.Height
        $maxX = -1
        $maxY = -1
        for ($y = 0; $y -lt $cutout.Height; $y++) {
            for ($x = 0; $x -lt $cutout.Width; $x++) {
                $pixel = $cutout.GetPixel($x, $y)
                $red = [int]$pixel.R
                $green = [int]$pixel.G
                $blue = [int]$pixel.B
                $maximum = [Math]::Max($red, [Math]::Max($green, $blue))
                if ($maximum -lt 150 -and ($gridLineRows.Contains($y) -or $gridLineColumns.Contains($x))) {
                    $cutout.SetPixel($x, $y, [System.Drawing.Color]::Transparent)
                    continue
                }
                $chromaValue = if ($Chroma -eq 'green') { $green } else { $blue }
                $otherMaximum = if ($Chroma -eq 'green') { [Math]::Max($red, $blue) } else { [Math]::Max($red, $green) }
                $chromaLead = $chromaValue - $otherMaximum
                $alpha = if ($chromaValue -gt 90 -and $chromaLead -gt 15) {
                    [int][Math]::Max(0, [Math]::Min(255, 255 - (($chromaLead - 15) * 5)))
                } else {
                    255
                }

                if ($alpha -lt 8) {
                    $cutout.SetPixel($x, $y, [System.Drawing.Color]::Transparent)
                } else {
                    # Reduce blue spill on semi-transparent fur edges.
                    if ($Chroma -eq 'green') {
                        $green = [int][Math]::Min($green, [Math]::Max($red, $blue) + 18)
                    } else {
                        $blue = [int][Math]::Min($blue, [Math]::Max($red, $green) + 18)
                    }
                    $cutout.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($alpha, $red, $green, $blue))
                    if ($alpha -ge 48) {
                        $minX = [Math]::Min($minX, $x)
                        $minY = [Math]::Min($minY, $y)
                        $maxX = [Math]::Max($maxX, $x)
                        $maxY = [Math]::Max($maxY, $y)
                    }
                }
            }
        }

        if ($maxX -lt $minX -or $maxY -lt $minY) {
            $cutout.Dispose()
            throw "No character pixels found in frame $index."
        }

        $bounds = [System.Drawing.Rectangle]::FromLTRB($minX, $minY, $maxX + 1, $maxY + 1)
        $prepared += [pscustomobject]@{ Bitmap = $cutout; Bounds = $bounds }
        $heights += $bounds.Height
    }

    $orderedHeights = $heights | Sort-Object
    $medianHeight = [double]$orderedHeights[[int][Math]::Floor($orderedHeights.Count / 2)]
    $scale = [Math]::Min(1.22, 390.0 / $medianHeight)

    for ($index = 0; $index -lt $prepared.Count; $index++) {
        $entry = $prepared[$index]
        $bounds = $entry.Bounds
        $frame = [System.Drawing.Bitmap]::new($canvasSize, $canvasSize, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $graphics = [System.Drawing.Graphics]::FromImage($frame)
        try {
            $graphics.Clear([System.Drawing.Color]::Transparent)
            $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $frameScale = if ($NormalizeHeight -gt 0) { [double]$NormalizeHeight / $bounds.Height } else { $scale }
        $drawWidth = [int][Math]::Round($bounds.Width * $frameScale)
        $drawHeight = [int][Math]::Round($bounds.Height * $frameScale)
            $drawX = [int][Math]::Round(($canvasSize - $drawWidth) / 2)
            $drawY = $targetBottom - $drawHeight
            $destination = [System.Drawing.Rectangle]::new($drawX, $drawY, $drawWidth, $drawHeight)
            $graphics.DrawImage($entry.Bitmap, $destination, $bounds, [System.Drawing.GraphicsUnit]::Pixel)
        } finally {
            $graphics.Dispose()
        }

        $outputPath = Join-Path $OutputDirectory ('frame-{0:D2}.png' -f $index)
        $frame.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $frame.Dispose()
    }

    foreach ($entry in $prepared) {
        $entry.Bitmap.Dispose()
    }
} finally {
    $sheet.Dispose()
}

Write-Output $OutputDirectory
