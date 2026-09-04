param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$partsRoot = Join-Path $ProjectRoot 'assets\animation-source\puppet'
$outputRoot = Join-Path $ProjectRoot 'assets\animation-source\puppet-run'
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null

$parts = @{}
foreach ($name in @('head','torso','tail','arm_left','arm_right','leg_left','leg_right')) {
    $parts[$name] = [System.Drawing.Image]::FromFile((Join-Path $partsRoot "$name.png"))
}

function Convert-PuppetPoint([double]$x, [double]$y, [double]$angle, [double]$offsetY) {
    $radians = $angle * [Math]::PI / 180
    $dx = $x - 160; $dy = $y - 170
    return @(
        (160 + $dx * [Math]::Cos($radians) - $dy * [Math]::Sin($radians))
        (170 + $dx * [Math]::Sin($radians) + $dy * [Math]::Cos($radians) + $offsetY)
    )
}

function Draw-PuppetPart {
    param(
        [System.Drawing.Graphics]$Graphics,
        [System.Drawing.Image]$Image,
        [double]$TargetX, [double]$TargetY,
        [double]$PivotX, [double]$PivotY,
        [double]$Scale, [double]$Rotation
    )
    $saved = $Graphics.Save()
    try {
        $Graphics.TranslateTransform([single]$TargetX, [single]$TargetY)
        $Graphics.RotateTransform([single]$Rotation)
        $Graphics.ScaleTransform([single]$Scale, [single]$Scale)
        $Graphics.DrawImage($Image, [single](-$PivotX), [single](-$PivotY), [single]$Image.Width, [single]$Image.Height)
    } finally { $Graphics.Restore($saved) }
}

try {
    for ($index = 0; $index -lt 48; $index++) {
        $phase = $index / 48.0 * [Math]::PI * 2
        $stride = [Math]::Sin($phase)
        $rebound = [Math]::Cos($phase * 2)
        $rootAngle = 0.8 * [Math]::Sin($phase - 0.25)
        $rootY = 3.0 + 3.0 * $rebound
        $leftLift = 8.0 * [Math]::Max(0, $stride)
        $rightLift = 8.0 * [Math]::Max(0, -$stride)

        $frame = [System.Drawing.Bitmap]::new(320, 320, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $graphics = [System.Drawing.Graphics]::FromImage($frame)
        try {
            $graphics.Clear([System.Drawing.Color]::Transparent)
            $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
            $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality

            $shadowWidth = 76 - 8 * $rebound
            $shadowBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(55, 24, 12, 7))
            try { $graphics.FillEllipse($shadowBrush, [single](160 - $shadowWidth / 2), 282, [single]$shadowWidth, 10) }
            finally { $shadowBrush.Dispose() }

            $tailPoint = Convert-PuppetPoint 205 190 $rootAngle $rootY
            $farLegPoint = Convert-PuppetPoint 175 (193 - $rightLift) $rootAngle $rootY
            $farArmPoint = Convert-PuppetPoint 195 109 $rootAngle $rootY
            $torsoPoint = Convert-PuppetPoint 160 148 $rootAngle $rootY
            $nearLegPoint = Convert-PuppetPoint 145 (193 - $leftLift) $rootAngle $rootY
            $nearArmPoint = Convert-PuppetPoint 125 109 $rootAngle $rootY
            $headPoint = Convert-PuppetPoint 160 103 $rootAngle $rootY

            Draw-PuppetPart $graphics $parts.tail $tailPoint[0] $tailPoint[1] ($parts.tail.Width * 0.80) ($parts.tail.Height * 0.08) 0.31 ($rootAngle + 12 * [Math]::Sin($phase - 0.75))
            Draw-PuppetPart $graphics $parts.leg_right $farLegPoint[0] $farLegPoint[1] ($parts.leg_right.Width * 0.50) ($parts.leg_right.Height * 0.08) 0.28 ($rootAngle - 5 - 10 * $stride)
            Draw-PuppetPart $graphics $parts.arm_right $farArmPoint[0] $farArmPoint[1] ($parts.arm_right.Width * 0.50) ($parts.arm_right.Height * 0.08) 0.24 ($rootAngle - 15 + 12 * $stride)
            Draw-PuppetPart $graphics $parts.leg_left $nearLegPoint[0] $nearLegPoint[1] ($parts.leg_left.Width * 0.50) ($parts.leg_left.Height * 0.08) 0.29 ($rootAngle + 5 + 10 * $stride)
            Draw-PuppetPart $graphics $parts.arm_left $nearArmPoint[0] $nearArmPoint[1] ($parts.arm_left.Width * 0.50) ($parts.arm_left.Height * 0.08) 0.28 ($rootAngle + 15 - 12 * $stride)
            # Torso renders over the rounded sockets so shoulder and hip
            # joints remain hidden while every limb stays rigid.
            Draw-PuppetPart $graphics $parts.torso $torsoPoint[0] $torsoPoint[1] ($parts.torso.Width * 0.50) ($parts.torso.Height * 0.50) 0.39 $rootAngle
            Draw-PuppetPart $graphics $parts.head $headPoint[0] $headPoint[1] ($parts.head.Width * 0.50) ($parts.head.Height * 0.88) 0.34 ($rootAngle - 1.8 * [Math]::Sin($phase - 0.45))
        } finally { $graphics.Dispose() }
        try {
            $frame.Save((Join-Path $outputRoot ('frame-{0:D3}.png' -f $index)), [System.Drawing.Imaging.ImageFormat]::Png)
        } finally { $frame.Dispose() }
    }
} finally {
    foreach ($image in $parts.Values) { $image.Dispose() }
}

Write-Output $outputRoot
