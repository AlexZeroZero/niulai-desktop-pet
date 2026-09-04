param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [int]$Duration = 6,
    [string]$Model = 'viduq2-pro-fast'
)

$ErrorActionPreference = 'Stop'
$sourcePath = Join-Path $ProjectRoot 'assets\animation-video\vidu-v1\niulai-reference-clean-fullbody-1024-v1.png'
$outputDirectory = Join-Path $ProjectRoot 'assets\animation-video\vidu-v1'
$outputPath = Join-Path $outputDirectory 'niulai-micro-gait-vidu-v1-raw.mp4'
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

if (-not (Test-Path -LiteralPath $sourcePath)) {
    throw "Clean full-body reference image not found: $sourcePath"
}

$secureKey = Read-Host 'Vidu API key' -AsSecureString
$keyPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
try {
    $apiKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($keyPointer)
    if ([string]::IsNullOrWhiteSpace($apiKey)) { throw 'Vidu API key is empty.' }

    $imageBytes = [System.IO.File]::ReadAllBytes($sourcePath)
    $imageData = 'data:image/png;base64,' + [Convert]::ToBase64String($imageBytes)
    $authProfiles = @(
        @{ BaseUri = 'https://api.vidu.com'; Scheme = 'Token' },
        @{ BaseUri = 'https://api.vidu.cn'; Scheme = 'Token' },
        @{ BaseUri = 'https://api.vidu.com'; Scheme = 'Bearer' },
        @{ BaseUri = 'https://api.vidu.cn'; Scheme = 'Bearer' }
    )
    $selectedProfile = $null
    foreach ($profile in $authProfiles) {
        $candidateHeaders = @{ Authorization = "$($profile.Scheme) $apiKey" }
        try {
            Invoke-RestMethod `
                -Uri "$($profile.BaseUri)/ent/v2/credits" `
                -Method Get `
                -Headers $candidateHeaders `
                -ContentType 'application/json' `
                -TimeoutSec 45 | Out-Null
            $selectedProfile = $profile
            $headers = $candidateHeaders
            break
        } catch {
            $statusCode = [int]$_.Exception.Response.StatusCode
            if ($statusCode -notin @(401, 403, 404)) { throw }
        }
    }
    if (-not $selectedProfile) {
        throw 'Vidu rejected the API key on both API regions and supported authorization schemes.'
    }
    $prompt = @'
Locked camera and locked character scale. Preserve the exact orange furry anthropomorphic bull from the reference: identical face, horns, ears, muzzle, fur, body proportions, colour, lighting and sleepy expression. Keep the full body, both horns, both hands, both legs, both hooves and tail visible in every frame.

The bull performs exactly one slow, gentle, seamless walking-in-place cycle over the entire clip: two tiny alternating steps, left then right, ending in exactly the starting neutral pose. Feet stay directly below the hips. Each hoof lifts no more than one quarter of its own height and moves no more than half a hoof length. Knees bend softly and continuously. When the left leg moves forward, the right arm moves forward; when the right leg moves forward, the left arm moves forward. Arms swing from the shoulders in a very small smooth arc with relaxed elbows. Wrists, hands and fingers remain stable with zero shaking. The pelvis makes only a subtle natural side-to-side weight shift, the shoulders counter-rotate slightly, the torso remains upright, and the head stays almost still. Motion is evenly timed with slow ease-in and ease-out, no pauses and no sudden pose changes.

Absolutely no running, marching, high knees, kicking, long strides, bouncing, hopping, sliding, crossed legs, arm flapping, wrist vibration, tremor, twitching, body warping, rubber limbs, extra limbs, disappearing limbs, camera movement, zoom, cuts, motion blur, text, props or sound. Plain black background. No red outline, no coloured halo, no glow. Begin and end on the same pose for a clean loop.
'@
    $payload = @{
        model = $Model
        images = @($imageData)
        prompt = $prompt.Trim()
        duration = $Duration
        resolution = '720p'
        movement_amplitude = 'small'
        audio = $false
        bgm = $false
        is_rec = $false
        off_peak = $false
    } | ConvertTo-Json -Depth 6 -Compress

    $request = Invoke-RestMethod `
        -Uri "$($selectedProfile.BaseUri)/ent/v2/img2video" `
        -Method Post `
        -Headers $headers `
        -ContentType 'application/json' `
        -Body $payload `
        -TimeoutSec 180

    if (-not $request.task_id) { throw 'Vidu did not return a task ID.' }
    Write-Output "TASK_ID=$($request.task_id)"

    $deadline = [DateTime]::UtcNow.AddMinutes(30)
    do {
        Start-Sleep -Seconds 8
        $result = Invoke-RestMethod `
            -Uri "$($selectedProfile.BaseUri)/ent/v2/tasks/$($request.task_id)/creations" `
            -Method Get `
            -Headers $headers `
            -ContentType 'application/json' `
            -TimeoutSec 90
        Write-Output "STATUS=$($result.state)"

        if ($result.state -eq 'success') {
            $creation = @($result.creations)[0]
            if (-not $creation.url) { throw 'Vidu completed without a video URL.' }
            Invoke-WebRequest -Uri $creation.url -OutFile $outputPath -UseBasicParsing -TimeoutSec 600
            Write-Output "OUTPUT=$outputPath"
            exit 0
        }
        if ($result.state -eq 'failed') {
            throw "Vidu task failed: $($result.err_code)"
        }
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'Timed out waiting for Vidu video generation.'
} finally {
    $apiKey = $null
    if ($keyPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($keyPointer)
    }
}
