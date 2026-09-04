param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$sourcePath = Join-Path $ProjectRoot 'assets\animation-video\grok-v11\niulai-small-gait-grok-v11-raw.mp4'
$outputPath = Join-Path $ProjectRoot 'assets\animation-video\grok-v11\niulai-grok-v13-motion-reduced.mp4'

$secureKey = Read-Host 'xAI API key' -AsSecureString
$keyPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
try {
    $apiKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($keyPointer)
    $videoBytes = [System.IO.File]::ReadAllBytes($sourcePath)
    $videoData = 'data:video/mp4;base64,' + [Convert]::ToBase64String($videoBytes)
    $headers = @{ Authorization = "Bearer $apiKey" }
    $prompt = @'
Preserve the exact video, character identity, timing, frame count, camera, scale, background, lighting and image quality. Modify only the body motion: reduce every leg and arm movement to 35 percent of the original amplitude. Convert the large knee lifts into tiny low shuffle steps with both thighs nearly vertical, hooves always beneath the hips and never higher than one quarter of a hoof. Keep clear left-right alternation and opposite arm-leg timing. Keep the pelvis level, torso upright and head steady. Make the gait continuous and evenly paced from beginning to end. Stabilize shoulders, elbows, wrists and hands; remove all wrist flutter and sudden joint acceleration. No new action, no pause, no deformation, no extra limbs, no camera movement, no zoom, no blur, no text. Full body visible throughout.
'@
    $payload = @{
        model = 'grok-imagine-video'
        prompt = $prompt.Trim()
        video = @{ url = $videoData }
    } | ConvertTo-Json -Depth 5 -Compress

    $request = Invoke-RestMethod -Uri 'https://api.x.ai/v1/videos/edits' -Method Post -Headers $headers -ContentType 'application/json' -Body $payload -TimeoutSec 180
    if (-not $request.request_id) { throw 'xAI did not return an edit request ID.' }
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
        if ($result.status -in @('failed', 'expired')) { throw "xAI video edit $($result.status)." }
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'Timed out waiting for the xAI video edit.'
} finally {
    $apiKey = $null
    if ($keyPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($keyPointer)
    }
}
