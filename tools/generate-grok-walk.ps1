param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [int]$Duration = 4
)

$ErrorActionPreference = 'Stop'
$sourcePath = Join-Path $ProjectRoot 'assets\animation-source\base\idle-0.png'
$outputDirectory = Join-Path $ProjectRoot 'assets\animation-video\grok-v11'
$outputPath = Join-Path $outputDirectory 'niulai-micro-shuffle-grok-v12-raw.mp4'
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

$secureKey = Read-Host 'xAI API key' -AsSecureString
$keyPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
try {
    $apiKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($keyPointer)
    $imageBytes = [System.IO.File]::ReadAllBytes($sourcePath)
    $imageData = 'data:image/png;base64,' + [Convert]::ToBase64String($imageBytes)
    $headers = @{ Authorization = "Bearer $apiKey" }
    $prompt = @'
Locked camera, locked character scale, empty transparent-looking black background. The exact orange furry anthropomorphic bull performs exactly two extremely small alternating shuffle steps in place and returns to the starting pose. This is a micro-shuffle, not normal walking: both thighs remain nearly vertical at all times; knees never rise; each hoof stays touching or skimming the floor and slides only three centimeters forward then back, always directly beneath the hips. The vertical height of either hoof never exceeds one quarter of a hoof height. Pelvis stays perfectly level, torso upright, head nearly motionless. Arms move only two centimeters opposite the feet with softly bent elbows; shoulders, wrists and hands remain relaxed and stable. Begin the micro-shuffle immediately and maintain smooth, evenly timed left-right alternation through the entire clip. Absolutely no high knee, no thigh lift, no long step, no running, no marching, no kicking, no crossed legs, no bouncing, no hand flapping, no wrist vibration, no pose jumps, no body deformation, no camera movement, no zoom, no motion blur, no extra limbs, no props, no text. Preserve the exact face, horns, orange fur, body proportions, lighting and neutral expression from the source image. Full body remains visible in every frame.
'@
    $payload = @{
        model = 'grok-imagine-video-1.5'
        prompt = $prompt.Trim()
        image = @{ url = $imageData }
        duration = $Duration
        resolution = '720p'
    } | ConvertTo-Json -Depth 5 -Compress

    $request = Invoke-RestMethod -Uri 'https://api.x.ai/v1/videos/generations' -Method Post -Headers $headers -ContentType 'application/json' -Body $payload -TimeoutSec 120
    if (-not $request.request_id) { throw 'xAI did not return a video request ID.' }
    Write-Output "REQUEST_ID=$($request.request_id)"

    $deadline = [DateTime]::UtcNow.AddMinutes(20)
    do {
        Start-Sleep -Seconds 6
        $result = Invoke-RestMethod -Uri "https://api.x.ai/v1/videos/$($request.request_id)" -Method Get -Headers $headers -TimeoutSec 60
        Write-Output "STATUS=$($result.status)"
        if ($result.status -eq 'done') {
            if (-not $result.video.url) { throw 'xAI finished without a video URL.' }
            Invoke-WebRequest -Uri $result.video.url -OutFile $outputPath -UseBasicParsing -TimeoutSec 300
            Write-Output "OUTPUT=$outputPath"
            exit 0
        }
        if ($result.status -in @('failed', 'expired')) { throw "xAI video request $($result.status)." }
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'Timed out waiting for the xAI video.'
} finally {
    $apiKey = $null
    if ($keyPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($keyPointer)
    }
}
