param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

if (-not ('Niulai.PuppetExtractor' -as [type])) {
    $drawingDirectory = Split-Path -Parent ([System.Drawing.Bitmap].Assembly.Location)
    $drawingAssemblies = @(Get-ChildItem -LiteralPath $drawingDirectory -File |
        Where-Object { $_.Name -match '^System\.Drawing.*\.dll$|^System\.Private\.Windows\..*\.dll$' } |
        ForEach-Object FullName)
    Add-Type -ReferencedAssemblies $drawingAssemblies -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;

namespace Niulai {
    public static class PuppetExtractor {
        public static void Extract(string sourcePath, string outputPath, int x, int y, int width, int height) {
            using (var source = new Bitmap(sourcePath))
            using (var keyed = new Bitmap(width, height, PixelFormat.Format32bppArgb)) {
                int minX = width, minY = height, maxX = -1, maxY = -1;
                for (int py = 0; py < height; py++) {
                    for (int px = 0; px < width; px++) {
                        Color c = source.GetPixel(x + px, y + py);
                        int dominance = c.B - Math.Max(c.R, c.G);
                        int alpha = dominance >= 45 ? 0 : dominance <= -10 ? 255 : (45 - dominance) * 255 / 55;
                        int blue = Math.Min(c.B, Math.Max(c.R, c.G));
                        keyed.SetPixel(px, py, Color.FromArgb(alpha, c.R, c.G, blue));
                        if (alpha > 12) {
                            minX = Math.Min(minX, px); minY = Math.Min(minY, py);
                            maxX = Math.Max(maxX, px); maxY = Math.Max(maxY, py);
                        }
                    }
                }
                if (maxX < minX || maxY < minY) throw new Exception("No foreground found in " + outputPath);
                int pad = 3;
                minX = Math.Max(0, minX - pad); minY = Math.Max(0, minY - pad);
                maxX = Math.Min(width - 1, maxX + pad); maxY = Math.Min(height - 1, maxY + pad);
                Rectangle crop = new Rectangle(minX, minY, maxX - minX + 1, maxY - minY + 1);
                using (var output = keyed.Clone(crop, PixelFormat.Format32bppArgb)) {
                    output.Save(outputPath, ImageFormat.Png);
                }
            }
        }
    }
}
'@
}

$source = Join-Path $ProjectRoot 'assets\animation-source\generated\niulai-puppet-parts-v1.png'
$output = Join-Path $ProjectRoot 'assets\animation-source\puppet'
New-Item -ItemType Directory -Force -Path $output | Out-Null

$regions = @{
    head       = @(0, 0, 430, 360)
    torso      = @(430, 0, 420, 390)
    tail       = @(840, 0, 310, 390)
    arm_left   = @(0, 370, 370, 390)
    arm_right  = @(370, 370, 380, 390)
    leg_left   = @(750, 330, 350, 440)
    leg_right  = @(1080, 330, 368, 440)
    hand_left  = @(0, 730, 360, 356)
    hand_right = @(360, 730, 390, 356)
    shin_left  = @(750, 720, 350, 366)
    shin_right = @(1080, 720, 368, 366)
}

foreach ($name in $regions.Keys) {
    $r = $regions[$name]
    [Niulai.PuppetExtractor]::Extract($source, (Join-Path $output "$name.png"), $r[0], $r[1], $r[2], $r[3])
}

Get-ChildItem -LiteralPath $output -Filter '*.png' | Sort-Object Name | Select-Object Name, Length
