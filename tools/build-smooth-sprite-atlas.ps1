param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [int]$FrameCount = 48
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
if ($FrameCount -lt 16) { throw 'FrameCount must be at least 16.' }

$sourceCell = 320
$cell = 256
$rowCount = 5
$keyAtlasPath = & (Join-Path $PSScriptRoot 'build-sprite-atlas.ps1') -ProjectRoot $ProjectRoot
$outputPath = Join-Path $ProjectRoot 'frontend\public\sprites\niulai-atlas.png'
$rifeRoot = Join-Path $ProjectRoot '.tools\rife-ncnn-vulkan-20221029-windows'
$rife = Join-Path $rifeRoot 'rife-ncnn-vulkan.exe'
$model = Join-Path $rifeRoot 'rife-v4.6'
if (-not (Test-Path -LiteralPath $rife)) { throw "RIFE tool not found: $rife" }
if (-not (Test-Path -LiteralPath $model)) { throw "RIFE model not found: $model" }

$workRoot = Join-Path $ProjectRoot ('.tools\sprite-rife-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $workRoot | Out-Null

if (-not ('Niulai.AlphaRecovery' -as [type])) {
    $drawingDirectory = Split-Path -Parent ([System.Drawing.Bitmap].Assembly.Location)
    $drawingAssemblies = @(Get-ChildItem -LiteralPath $drawingDirectory -File |
        Where-Object { $_.Name -match '^System\.Drawing.*\.dll$|^System\.Private\.Windows\..*\.dll$' } |
        ForEach-Object FullName)
    Add-Type -ReferencedAssemblies $drawingAssemblies -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace Niulai {
    public static class AlphaRecovery {
        public static void Recover(string blackPath, string whitePath, string outputPath) {
            using (var black = new Bitmap(blackPath))
            using (var white = new Bitmap(whitePath))
            using (var output = new Bitmap(black.Width, black.Height, PixelFormat.Format32bppArgb)) {
                var rect = new Rectangle(0, 0, black.Width, black.Height);
                var bd = black.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
                var wd = white.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
                var od = output.LockBits(rect, ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
                try {
                    var br = new byte[Math.Abs(bd.Stride) * black.Height];
                    var wr = new byte[Math.Abs(wd.Stride) * white.Height];
                    var oraw = new byte[Math.Abs(od.Stride) * output.Height];
                    Marshal.Copy(bd.Scan0, br, 0, br.Length);
                    Marshal.Copy(wd.Scan0, wr, 0, wr.Length);
                    for (int y = 0; y < black.Height; y++) {
                        for (int x = 0; x < black.Width; x++) {
                            int bi = y * bd.Stride + x * 3;
                            int wi = y * wd.Stride + x * 3;
                            int oi = y * od.Stride + x * 4;
                            int diff = ((wr[wi] - br[bi]) + (wr[wi + 1] - br[bi + 1]) + (wr[wi + 2] - br[bi + 2])) / 3;
                            int alpha = Math.Max(0, Math.Min(255, 255 - diff));
                            if (alpha < 5) alpha = 0;
                            oraw[oi + 3] = (byte)alpha;
                            if (alpha > 0) {
                                oraw[oi] = (byte)Math.Min(255, br[bi] * 255 / alpha);
                                oraw[oi + 1] = (byte)Math.Min(255, br[bi + 1] * 255 / alpha);
                                oraw[oi + 2] = (byte)Math.Min(255, br[bi + 2] * 255 / alpha);
                            }
                        }
                    }
                    Marshal.Copy(oraw, 0, od.Scan0, oraw.Length);
                } finally {
                    black.UnlockBits(bd); white.UnlockBits(wd); output.UnlockBits(od);
                }
                output.Save(outputPath, ImageFormat.Png);
            }
        }
    }
}
'@
}

$keyAtlas = [System.Drawing.Bitmap]::FromFile($keyAtlasPath)
try {
    for ($row = 0; $row -lt $rowCount; $row++) {
        $blackInput = Join-Path $workRoot "row-$row-black-input"
        $whiteInput = Join-Path $workRoot "row-$row-white-input"
        $blackOutput = Join-Path $workRoot "row-$row-black-output"
        $whiteOutput = Join-Path $workRoot "row-$row-white-output"
        $alphaOutput = Join-Path $workRoot "row-$row-alpha-output"
        New-Item -ItemType Directory -Force -Path $blackInput, $whiteInput, $blackOutput, $whiteOutput, $alphaOutput | Out-Null

        # Repeat key 0 as key 4 so RIFE also interpolates the loop seam.
        for ($column = 0; $column -lt 5; $column++) {
            $sourceColumn = $column % 4
            $source = [System.Drawing.Rectangle]::new($sourceColumn * $sourceCell, $row * $sourceCell, $sourceCell, $sourceCell)
            foreach ($variant in @('black', 'white')) {
                $background = if ($variant -eq 'black') { [System.Drawing.Color]::Black } else { [System.Drawing.Color]::White }
                $frame = [System.Drawing.Bitmap]::new($sourceCell, $sourceCell, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
                $frameGraphics = [System.Drawing.Graphics]::FromImage($frame)
                try {
                    $frameGraphics.Clear($background)
                    $frameGraphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
                    $destination = [System.Drawing.Rectangle]::new(0, 0, $sourceCell, $sourceCell)
                    $frameGraphics.DrawImage($keyAtlas, $destination, $source, [System.Drawing.GraphicsUnit]::Pixel)
                } finally { $frameGraphics.Dispose() }
                $targetDir = if ($variant -eq 'black') { $blackInput } else { $whiteInput }
                $frame.Save((Join-Path $targetDir ('{0:D3}.png' -f $column)), [System.Drawing.Imaging.ImageFormat]::Png)
                $frame.Dispose()
            }
        }

        & $rife -i $blackInput -o $blackOutput -n ($FrameCount + 1) -m $model -g 0 -j 2:2:2 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "RIFE black pass failed for row $row." }
        & $rife -i $whiteInput -o $whiteOutput -n ($FrameCount + 1) -m $model -g 0 -j 2:2:2 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "RIFE white pass failed for row $row." }

        $blackFrames = @(Get-ChildItem -LiteralPath $blackOutput -Filter '*.png' | Sort-Object Name)
        $whiteFrames = @(Get-ChildItem -LiteralPath $whiteOutput -Filter '*.png' | Sort-Object Name)
        if ($blackFrames.Count -lt $FrameCount -or $whiteFrames.Count -lt $FrameCount) { throw "RIFE returned too few frames for row $row." }
        for ($index = 0; $index -lt $FrameCount; $index++) {
            [Niulai.AlphaRecovery]::Recover($blackFrames[$index].FullName, $whiteFrames[$index].FullName, (Join-Path $alphaOutput ('frame-{0:D3}.png' -f $index)))
        }
    }
} finally { $keyAtlas.Dispose() }

$smoothAtlas = [System.Drawing.Bitmap]::new($cell * $FrameCount, $cell * $rowCount, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$atlasGraphics = [System.Drawing.Graphics]::FromImage($smoothAtlas)
$atlasGraphics.Clear([System.Drawing.Color]::Transparent)
$atlasGraphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
$atlasGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
try {
    for ($row = 0; $row -lt $rowCount; $row++) {
        for ($column = 0; $column -lt $FrameCount; $column++) {
            $framePath = Join-Path $workRoot "row-$row-alpha-output\frame-$('{0:D3}' -f $column).png"
            $frame = [System.Drawing.Image]::FromFile($framePath)
            try {
                $destination = [System.Drawing.Rectangle]::new($column * $cell, $row * $cell, $cell, $cell)
                $source = [System.Drawing.Rectangle]::new(0, 0, $sourceCell, $sourceCell)
                $atlasGraphics.DrawImage($frame, $destination, $source, [System.Drawing.GraphicsUnit]::Pixel)
            } finally { $frame.Dispose() }
        }
    }
} finally { $atlasGraphics.Dispose() }

$rawPath = Join-Path $workRoot 'niulai-rife-atlas-unquantized.png'
$smoothAtlas.Save($rawPath, [System.Drawing.Imaging.ImageFormat]::Png)
$smoothAtlas.Dispose()

$pngquant = Join-Path $ProjectRoot '.tools\pngquant\pngquant\pngquant.exe'
if (Test-Path -LiteralPath $pngquant) {
    & $pngquant --quality 55-88 --speed 1 --strip --force --output $outputPath -- $rawPath
    if ($LASTEXITCODE -ne 0) { throw 'pngquant failed to optimize the RIFE sprite atlas.' }
} else {
    Copy-Item -LiteralPath $rawPath -Destination $outputPath -Force
}

Write-Output $outputPath
