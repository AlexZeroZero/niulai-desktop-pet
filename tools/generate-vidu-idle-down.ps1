param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$sourcePath = Join-Path $ProjectRoot 'assets\animation-video\vidu-v1\niulai-reference-clean-fullbody-1024-v1.png'
$outputDirectory = Join-Path $ProjectRoot 'assets\animation-video\vidu-v3'
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

if (-not (Test-Path -LiteralPath $sourcePath)) {
    throw "Clean full-body reference image not found: $sourcePath"
}

$jobs = @(
    @{
        Name = 'idle-look'
        Duration = 6
        Audio = $false
        Output = 'niulai-idle-look-vidu-v3-raw.mp4'
        Prompt = @'
One continuous locked-camera shot on a plain black background. Preserve the exact orange furry anthropomorphic bull from the reference: identical face, horns, ears, muzzle, fur, body proportions, colours, lighting and sleepy personality. Keep the complete body, horns, hands, legs, hooves and tail visible with generous padding in every frame.

The bull is calmly standing still in its normal idle pose. Both feet remain firmly planted in exactly the same place. The hips, belly, shoulders and arms remain stable with no side-to-side body sway. The character naturally looks around as if checking its surroundings: eyes slowly glance to the left, the head follows only a few degrees, pauses; eyes return through centre; then eyes glance to the right and the head follows only a few degrees; finally the gaze returns to centre. One ear gives a small curious flick during each side glance. Include a natural blink and a tiny slow breath. The expression is alert, curious and slightly funny, not frightened.

All motion must be subtle, smooth and continuous with many in-between poses. Absolutely no walking, stepping, foot sliding, body rocking, dancing, shoulder swinging, arm waving, wrist vibration, twitching, sudden jumps, camera movement, zoom, cuts, crop, motion blur, speech, mouth talking, extra limbs, missing limbs, deformation, red outline, coloured halo, glow, text or props. Begin and end in the same centred neutral pose for a clean loop.
'@
    },
    @{
        Name = 'down-cry'
        Duration = 8
        Audio = $true
        Output = 'niulai-down-cry-vidu-v3-raw.mp4'
        Prompt = @'
One continuous locked-camera shot on a plain black background. Preserve the exact orange furry anthropomorphic bull from the reference: identical face, horns, ears, muzzle, fur, body proportions, colours and lighting. Keep the complete body, horns, hands, legs, hooves and tail visible with generous padding in every frame.

The bull sees a sudden market crash and reacts with clear but controlled physical acting. It takes one tiny backward stagger, shoulders droop, ears lower, knees bend naturally and the body smoothly settles into a low disappointed crouch. The feet stay beneath the hips and never cross. The spine bends slightly forward as one connected body, not like rubber. Hands rise slowly near the cheeks with softly bent elbows; wrists and fingers remain stable. The face becomes deeply wronged and tearful.

At about 1.2 seconds, while lowering into the crouch, the bull looks forward and cries once in Mandarin Chinese: “妈妈！” The mouth clearly opens and articulates the two syllables MA MA, with natural jaw, lips and cheeks synchronized to the cry. After speaking, the mouth closes; the bull remains crouched and quietly cries, with two visible tears, one slow shoulder sob and one gentle wipe of a cheek. The final pose is a readable, sympathetic crouched crying pose.

Motion must be smooth and continuous with many natural in-between poses. Absolutely no falling over, collapsing flat, violent shaking, rapid bouncing, kicking, crossed legs, hand flapping, wrist vibration, twitching, rubber limbs, extra or disappearing limbs, body deformation, camera movement, zoom, cuts, crop, motion blur, extra dialogue, text, props, red outline, coloured halo or glow.
'@
    }
)

$secureKey = Read-Host 'Vidu API key' -AsSecureString
$keyPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
try {
    $apiKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($keyPointer)
    if ([string]::IsNullOrWhiteSpace($apiKey)) { throw 'Vidu API key is empty.' }

    $profiles = @(
        @{ BaseUri = 'https://api.vidu.com'; Scheme = 'Token' },
        @{ BaseUri = 'https://api.vidu.cn'; Scheme = 'Token' },
        @{ BaseUri = 'https://api.vidu.com'; Scheme = 'Bearer' },
        @{ BaseUri = 'https://api.vidu.cn'; Scheme = 'Bearer' }
    )
    $profile = $null
    foreach ($candidate in $profiles) {
        $candidateHeaders = @{ Authorization = "$($candidate.Scheme) $apiKey" }
        try {
            Invoke-RestMethod -Uri "$($candidate.BaseUri)/ent/v2/credits" -Method Get `
                -Headers $candidateHeaders -ContentType 'application/json' -TimeoutSec 45 | Out-Null
            $profile = $candidate
            $headers = $candidateHeaders
            break
        } catch {
            $statusCode = [int]$_.Exception.Response.StatusCode
            if ($statusCode -notin @(401, 403, 404)) { throw }
        }
    }
    if (-not $profile) { throw 'Vidu rejected the API key.' }

    $imageBytes = [System.IO.File]::ReadAllBytes($sourcePath)
    $imageData = 'data:image/png;base64,' + [Convert]::ToBase64String($imageBytes)

    foreach ($job in $jobs) {
        $payload = @{
            model = 'viduq3-pro-fast'
            images = @($imageData)
            prompt = $job.Prompt.Trim()
            duration = $job.Duration
            resolution = '720p'
            audio = $job.Audio
            is_rec = $false
            off_peak = $false
        } | ConvertTo-Json -Depth 6 -Compress

        $request = Invoke-RestMethod -Uri "$($profile.BaseUri)/ent/v2/img2video" -Method Post `
            -Headers $headers -ContentType 'application/json' -Body $payload -TimeoutSec 180
        if (-not $request.task_id) { throw "Vidu did not return a task ID for $($job.Name)." }
        Write-Output "JOB=$($job.Name) TASK_ID=$($request.task_id)"

        $deadline = [DateTime]::UtcNow.AddMinutes(30)
        do {
            Start-Sleep -Seconds 8
            $result = Invoke-RestMethod -Uri "$($profile.BaseUri)/ent/v2/tasks/$($request.task_id)/creations" `
                -Method Get -Headers $headers -ContentType 'application/json' -TimeoutSec 90
            Write-Output "JOB=$($job.Name) STATUS=$($result.state)"
            if ($result.state -eq 'success') {
                $creation = @($result.creations)[0]
                if (-not $creation.url) { throw "Vidu completed $($job.Name) without a video URL." }
                $progressPreference = 'SilentlyContinue'
                $outputPath = Join-Path $outputDirectory $job.Output
                Invoke-WebRequest -Uri $creation.url -OutFile $outputPath -UseBasicParsing -TimeoutSec 600
                Write-Output "JOB=$($job.Name) OUTPUT=$outputPath"
                break
            }
            if ($result.state -eq 'failed') { throw "Vidu $($job.Name) failed: $($result.err_code)" }
        } while ([DateTime]::UtcNow -lt $deadline)
        if ($result.state -ne 'success') { throw "Timed out waiting for Vidu $($job.Name)." }
    }
} finally {
    $apiKey = $null
    if ($keyPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($keyPointer)
    }
}
