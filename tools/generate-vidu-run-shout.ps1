param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [int]$Duration = 6
)

$ErrorActionPreference = 'Stop'
$sourcePath = Join-Path $ProjectRoot 'assets\animation-video\vidu-v1\niulai-reference-clean-fullbody-1024-v1.png'
$outputDirectory = Join-Path $ProjectRoot 'assets\animation-video\vidu-v2'
$outputPath = Join-Path $outputDirectory 'niulai-run-shout-vidu-v2-raw.mp4'
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

if (-not (Test-Path -LiteralPath $sourcePath)) {
    throw "Clean full-body reference image not found: $sourcePath"
}

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
    $prompt = @'
One continuous locked-camera shot on a plain black background. Preserve the exact orange furry anthropomorphic bull from the reference: identical face, horns, ears, muzzle, fur, body proportions, colours and lighting. Keep the complete body, both horns, hands, legs, hooves and tail visible with generous padding in every frame.

From the first frame the bull performs a lively but controlled run in place. The run is smooth, evenly paced and physically coordinated: opposite arm and leg move together, arms swing from the shoulders with softly bent elbows, wrists and hands remain stable, feet alternate naturally beneath the hips, knees lift only slightly, stride is short, torso stays upright, pelvis shifts subtly, shoulders counter-rotate naturally, and the head remains stable. The character does not travel across the frame.

At exactly 2.0 seconds, while continuing the same run, the bull looks forward and loudly shouts once in Mandarin Chinese: “牛来！” The mouth must visibly open and articulate two clear syllables, NIU then LAI, with natural jaw, lips and cheeks synchronized to the shout. Keep running during the shout. Close the mouth naturally after the second syllable and continue the same run until the end. No other words, voices or dialogue.

Motion is continuous with many natural in-between poses and no sudden jumps. Absolutely no high-knee march, kicking, hopping, bouncing, sliding, crossed legs, flapping hands, wrist vibration, twitching, frozen limbs, rubber limbs, deformation, extra or missing limbs, camera movement, zoom, cuts, crop, motion blur, text, props, red outline, coloured halo or glow.
'@
    $payload = @{
        model = 'viduq3-pro-fast'
        images = @($imageData)
        prompt = $prompt.Trim()
        duration = $Duration
        resolution = '720p'
        audio = $true
        is_rec = $false
        off_peak = $false
    } | ConvertTo-Json -Depth 6 -Compress

    $request = Invoke-RestMethod -Uri "$($profile.BaseUri)/ent/v2/img2video" -Method Post `
        -Headers $headers -ContentType 'application/json' -Body $payload -TimeoutSec 180
    if (-not $request.task_id) { throw 'Vidu did not return a task ID.' }
    Write-Output "TASK_ID=$($request.task_id)"

    $deadline = [DateTime]::UtcNow.AddMinutes(30)
    do {
        Start-Sleep -Seconds 8
        $result = Invoke-RestMethod -Uri "$($profile.BaseUri)/ent/v2/tasks/$($request.task_id)/creations" `
            -Method Get -Headers $headers -ContentType 'application/json' -TimeoutSec 90
        Write-Output "STATUS=$($result.state)"
        if ($result.state -eq 'success') {
            $creation = @($result.creations)[0]
            if (-not $creation.url) { throw 'Vidu completed without a video URL.' }
            $progressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $creation.url -OutFile $outputPath -UseBasicParsing -TimeoutSec 600
            Write-Output "OUTPUT=$outputPath"
            exit 0
        }
        if ($result.state -eq 'failed') { throw "Vidu task failed: $($result.err_code)" }
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'Timed out waiting for Vidu video generation.'
} finally {
    $apiKey = $null
    if ($keyPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($keyPointer)
    }
}
