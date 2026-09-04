param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$SourcePath,
    [string]$OutputPath,
    [int]$Columns = 4,
    [int]$Rows = 4,
    [int]$FrameCount = 16
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

if (-not ('Niulai.SpriteSheetExtractor' -as [type])) {
    $drawingDirectory = Split-Path -Parent ([System.Drawing.Bitmap].Assembly.Location)
    $drawingAssemblies = @(Get-ChildItem -LiteralPath $drawingDirectory -File |
        Where-Object { $_.Name -match '^System\.Drawing.*\.dll$|^System\.Private\.Windows\..*\.dll$' } |
        ForEach-Object FullName)
    Add-Type -ReferencedAssemblies $drawingAssemblies -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;

namespace Niulai {
    public static class SpriteSheetExtractor {
        public static Rectangle ExtractCell(string sourcePath, string outputPath, int x, int y, int width, int height) {
            using (var source = new Bitmap(sourcePath))
            using (var keyed = new Bitmap(width, height, PixelFormat.Format32bppArgb)) {
                int minX = width, minY = height, maxX = -1, maxY = -1;
                for (int py = 0; py < height; py++) {
                    for (int px = 0; px < width; px++) {
                        Color c = source.GetPixel(x + px, y + py);
                        // The new production sheet uses a saturated blue key.
                        // Fade only blue-dominant edge pixels; orange fur, brown
                        // horns and pink muzzle never satisfy this test.
                        int blueDominance = c.B - Math.Max(c.R, c.G);
                        int alpha = 255;
                        // Use a hard key at source resolution. The later
                        // high-quality downscale recreates a clean antialiased
                        // alpha edge without carrying blue RGB into the fur.
                        if (c.B > 120 && blueDominance > 26) alpha = 0;
                        alpha = Math.Max(0, Math.Min(255, alpha));
                        keyed.SetPixel(px, py, alpha == 0
                            ? Color.FromArgb(0, 0, 0, 0)
                            : Color.FromArgb(alpha, c.R, c.G, c.B));
                        if (alpha > 14) {
                            minX = Math.Min(minX, px); minY = Math.Min(minY, py);
                            maxX = Math.Max(maxX, px); maxY = Math.Max(maxY, py);
                        }
                    }
                }
                Rectangle bounds = KeepLargestComponent(keyed);
                keyed.Save(outputPath, ImageFormat.Png);
                return bounds;
            }
        }

        private static Rectangle KeepLargestComponent(Bitmap image) {
            int width = image.Width, height = image.Height;
            int[] labels = new int[width * height];
            int[] queue = new int[width * height];
            int bestLabel = 0, bestSize = 0, label = 0;
            for (int y = 0; y < height; y++) {
                for (int x = 0; x < width; x++) {
                    int start = y * width + x;
                    if (labels[start] != 0 || image.GetPixel(x, y).A <= 14) continue;
                    label++;
                    int head = 0, tail = 0;
                    labels[start] = label;
                    queue[tail++] = start;
                    while (head < tail) {
                        int current = queue[head++];
                        int cx = current % width, cy = current / width;
                        for (int oy = -1; oy <= 1; oy++) {
                            for (int ox = -1; ox <= 1; ox++) {
                                if (ox == 0 && oy == 0) continue;
                                int nx = cx + ox, ny = cy + oy;
                                if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;
                                int next = ny * width + nx;
                                if (labels[next] == 0 && image.GetPixel(nx, ny).A > 14) {
                                    labels[next] = label;
                                    queue[tail++] = next;
                                }
                            }
                        }
                    }
                    if (tail > bestSize) { bestSize = tail; bestLabel = label; }
                }
            }
            if (bestLabel == 0) throw new Exception("Empty sprite cell");
            int minX = width, minY = height, maxX = -1, maxY = -1;
            for (int y = 0; y < height; y++) {
                for (int x = 0; x < width; x++) {
                    int index = y * width + x;
                    if (labels[index] == bestLabel) {
                        minX = Math.Min(minX, x); minY = Math.Min(minY, y);
                        maxX = Math.Max(maxX, x); maxY = Math.Max(maxY, y);
                    } else if (image.GetPixel(x, y).A != 0) {
                        image.SetPixel(x, y, Color.FromArgb(0, 0, 0, 0));
                    }
                }
            }
            return new Rectangle(minX, minY, maxX - minX + 1, maxY - minY + 1);
        }

        public static double UpperBodyCentroidX(string path, Rectangle bounds) {
            using (var image = new Bitmap(path)) {
                double weightedX = 0, weight = 0;
                int bottom = Math.Min(image.Height, bounds.Y + (int)Math.Round(bounds.Height * 0.62));
                for (int y = bounds.Y; y < bottom; y++) {
                    for (int x = bounds.X; x < bounds.Right; x++) {
                        int alpha = image.GetPixel(x, y).A;
                        if (alpha <= 14) continue;
                        weightedX += x * alpha;
                        weight += alpha;
                    }
                }
                return weight > 0 ? weightedX / weight : bounds.X + bounds.Width / 2.0;
            }
        }

        public static double OpaqueArea(string path, Rectangle bounds) {
            using (var image = new Bitmap(path)) {
                double area = 0;
                for (int y = bounds.Y; y < bounds.Bottom; y++)
                    for (int x = bounds.X; x < bounds.Right; x++)
                        area += image.GetPixel(x, y).A / 255.0;
                return area;
            }
        }
    }
}
'@
}

$source = if ($SourcePath) { $SourcePath } else { Join-Path $ProjectRoot 'assets\animation-source\generated\run-cycle-controlled-arm-flex-12-v3.png' }
$output = if ($OutputPath) { $OutputPath } else { Join-Path $ProjectRoot 'assets\animation-source\controlled-arm-gait-keys' }
New-Item -ItemType Directory -Force -Path $output | Out-Null

$image = [System.Drawing.Image]::FromFile($source)
try {
    $bounds = @()
    for ($index = 0; $index -lt $FrameCount; $index++) {
        $column = $index % $Columns; $row = [Math]::Floor($index / $Columns)
        $left = [Math]::Floor($image.Width * $column / $Columns)
        $right = [Math]::Floor($image.Width * ($column + 1) / $Columns)
        $top = [Math]::Floor($image.Height * $row / $Rows)
        $bottom = [Math]::Floor($image.Height * ($row + 1) / $Rows)
        $raw = Join-Path $output ('raw-{0:D2}.png' -f $index)
        $bounds += [Niulai.SpriteSheetExtractor]::ExtractCell($source, $raw, $left, $top, $right - $left, $bottom - $top)
    }
} finally { $image.Dispose() }

$maxWidth = ($bounds | Measure-Object Width -Maximum).Maximum
$maxHeight = ($bounds | Measure-Object Height -Maximum).Maximum
$scale = [Math]::Min(286.0 / $maxHeight, 294.0 / $maxWidth)
$areas = @()
for ($index = 0; $index -lt $FrameCount; $index++) {
    $areas += [Niulai.SpriteSheetExtractor]::OpaqueArea((Join-Path $output ('raw-{0:D2}.png' -f $index)), $bounds[$index])
}
$sortedAreas = @($areas | Sort-Object)
$medianArea = $sortedAreas[[Math]::Floor($sortedAreas.Count / 2)]

for ($index = 0; $index -lt $FrameCount; $index++) {
    $raw = [System.Drawing.Bitmap]::FromFile((Join-Path $output ('raw-{0:D2}.png' -f $index)))
    $frame = [System.Drawing.Bitmap]::new(320, 320, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($frame)
    try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $b = $bounds[$index]
        $areaScale = $scale * [Math]::Sqrt($medianArea / $areas[$index])
        $frameScale = [Math]::Min($areaScale, [Math]::Min(286.0 / $b.Height, 294.0 / $b.Width))
        $width = [Math]::Round($b.Width * $frameScale); $height = [Math]::Round($b.Height * $frameScale)
        # Anchor the head/torso mass instead of the changing limb bounds. This
        # keeps the character steady while arms, legs and tail move around it.
        $centroidX = [Niulai.SpriteSheetExtractor]::UpperBodyCentroidX((Join-Path $output ('raw-{0:D2}.png' -f $index)), $b)
        $x = [Math]::Round(174 - (($centroidX - $b.X) * $frameScale))
        $y = 310 - $height
        $destination = [System.Drawing.Rectangle]::new($x, $y, $width, $height)
        $graphics.DrawImage($raw, $destination, $b, [System.Drawing.GraphicsUnit]::Pixel)
    } finally { $graphics.Dispose(); $raw.Dispose() }
    try { $frame.Save((Join-Path $output ('frame-{0:D2}.png' -f $index)), [System.Drawing.Imaging.ImageFormat]::Png) }
    finally { $frame.Dispose() }
}

Get-ChildItem -LiteralPath $output -Filter 'raw-*.png' | Remove-Item -Force
Write-Output $output
