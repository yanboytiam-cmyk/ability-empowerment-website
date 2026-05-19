# ============================================================================
#  optimize-media.ps1
#  Batch image + video optimization for the Ability & Empowerment site.
#
#  NON-DESTRUCTIVE: originals are NEVER overwritten or deleted.
#  Outputs land next to originals with .webp / .avif / .webm extensions
#  (and -480w / -960w / -1440w suffixes for responsive images).
#
#  Usage examples (run from the project root):
#    pwsh ./optimize-media.ps1                       # do everything
#    pwsh ./optimize-media.ps1 -Images               # images only
#    pwsh ./optimize-media.ps1 -Videos               # videos only
#    pwsh ./optimize-media.ps1 -DryRun               # show planned work
#    pwsh ./optimize-media.ps1 -Force                # re-encode existing outputs
#
#  Required tools (install once):
#    ffmpeg      - winget install Gyan.FFmpeg
#    cwebp       - winget install Google.WebpCodec   (provides cwebp.exe)
#    avifenc     - choco install libavif    OR        scoop install libavif
#                  (optional; falls back to ffmpeg+libaom-av1 if absent)
# ============================================================================

[CmdletBinding()]
param(
    [switch]$Images,
    [switch]$Videos,
    [switch]$DryRun,
    [switch]$Force,
    [switch]$NoAvif,
    [switch]$NoWebm,

    # Quality knobs - sane defaults for web photography
    [int]$WebpQuality   = 80,    # 0..100
    [int]$AvifQuality   = 55,    # 0..100 (higher = better, ~50-60 sweet spot)
    [int]$VideoCrfMp4   = 28,    # 23 = high, 28 = good, 32 = small
    [int]$VideoCrfWebm  = 32,    # VP9 CRF (30-35 typical)
    [string]$VideoMaxHeight = '720',  # cap at 720p - these are decorative

    # Responsive widths for images. The original aspect ratio is preserved.
    [int[]]$ImageWidths = @(480, 960, 1440)
)

$ErrorActionPreference = 'Stop'
$RunAll = -not ($Images -or $Videos)
if ($RunAll) { $Images = $true; $Videos = $true }

$Root = $PSScriptRoot
if (-not $Root) { $Root = (Get-Location).Path }

Write-Host ""
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host " optimize-media.ps1  (non-destructive)" -ForegroundColor Cyan
Write-Host " Project root: $Root" -ForegroundColor Cyan
if ($DryRun) { Write-Host " MODE: DRY RUN - nothing will be written" -ForegroundColor Yellow }
if ($Force)  { Write-Host " MODE: FORCE - existing outputs will be overwritten" -ForegroundColor Yellow }
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host ""

# ---------------------------------------------------------------------------
# Tool detection
# ---------------------------------------------------------------------------
function Test-Tool($name) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    return [bool]$cmd
}

$HasFfmpeg  = Test-Tool 'ffmpeg'
$HasCwebp   = Test-Tool 'cwebp'
$HasAvifenc = Test-Tool 'avifenc'

Write-Host "Tools detected:" -ForegroundColor White
Write-Host ("  ffmpeg  : {0}" -f ($(if ($HasFfmpeg)  {'OK'} else {'MISSING'})))
Write-Host ("  cwebp   : {0}" -f ($(if ($HasCwebp)   {'OK'} else {'MISSING (will fall back to ffmpeg)'})))
Write-Host ("  avifenc : {0}" -f ($(if ($HasAvifenc) {'OK'} else {'MISSING (will fall back to ffmpeg+libaom-av1, slower)'})))
Write-Host ""

if ($Videos -and -not $HasFfmpeg) {
    Write-Error "Video optimization requires ffmpeg. Install with: winget install Gyan.FFmpeg"
}
if ($Images -and -not ($HasCwebp -or $HasFfmpeg)) {
    Write-Error "Image optimization requires cwebp or ffmpeg."
}

# ---------------------------------------------------------------------------
# Stats accumulators
# ---------------------------------------------------------------------------
$Stats = @{
    ImagesProcessed = 0
    ImagesSkipped   = 0
    VideosProcessed = 0
    VideosSkipped   = 0
    BytesIn         = 0L
    BytesOut        = 0L
}

function Add-Stat($key, $value) { $Stats[$key] += $value }

function Format-Bytes($b) {
    if ($b -lt 1KB) { return "$b B" }
    if ($b -lt 1MB) { return "{0:N1} KB" -f ($b / 1KB) }
    return "{0:N2} MB" -f ($b / 1MB)
}

function Invoke-Tool($exe, $argList) {
    if ($DryRun) {
        Write-Host "    DRY: $exe $($argList -join ' ')" -ForegroundColor DarkGray
        return $true
    }
    # Use the call operator (&) so PowerShell quotes path-args with spaces correctly.
    # Redirect stderr through merge so we capture failure detail without polluting stdout.
    $stderrFile = [System.IO.Path]::GetTempFileName()
    try {
        $null = & $exe @argList 2>$stderrFile
        $exit = $LASTEXITCODE
        if ($exit -ne 0) {
            $err = Get-Content -LiteralPath $stderrFile -Raw -ErrorAction SilentlyContinue
            if ($err) {
                Write-Host ("      [{0} exit {1}] {2}" -f $exe, $exit, ($err.Trim().Split("`n")[-1])) -ForegroundColor DarkRed
            }
        }
        return ($exit -eq 0)
    } finally {
        Remove-Item -LiteralPath $stderrFile -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# IMAGE PIPELINE
# ---------------------------------------------------------------------------
function Convert-Image($srcFile) {
    $dir  = $srcFile.DirectoryName
    $name = [System.IO.Path]::GetFileNameWithoutExtension($srcFile.Name)
    $srcBytes = $srcFile.Length

    foreach ($w in $ImageWidths) {
        $webpOut = Join-Path $dir ("{0}-{1}w.webp" -f $name, $w)
        $avifOut = Join-Path $dir ("{0}-{1}w.avif" -f $name, $w)

        # WebP
        if ($Force -or -not (Test-Path $webpOut)) {
            $ok = $false
            if ($HasCwebp) {
                # cwebp: -resize <w> 0  preserves aspect ratio
                $ok = Invoke-Tool 'cwebp' @('-quiet','-q', $WebpQuality,'-resize',"$w",'0',
                                             $srcFile.FullName,'-o', $webpOut)
            } elseif ($HasFfmpeg) {
                $ok = Invoke-Tool 'ffmpeg' @('-y','-hide_banner','-loglevel','error',
                                              '-i', $srcFile.FullName,
                                              '-vf', "scale='min(${w},iw)':-2",
                                              '-c:v','libwebp','-quality', $WebpQuality,
                                              $webpOut)
            }
            if ($DryRun) { continue }
            if ($ok -and (Test-Path $webpOut)) {
                Add-Stat 'BytesOut' ((Get-Item $webpOut).Length)
                Write-Host ("    + {0}" -f (Split-Path $webpOut -Leaf)) -ForegroundColor Green
            } else {
                Write-Host ("    ! WebP failed for {0} @ {1}w" -f $srcFile.Name, $w) -ForegroundColor Red
            }
        } else {
            Add-Stat 'BytesOut' ((Get-Item $webpOut).Length)
        }

        # AVIF (skipped when -NoAvif)
        if ($NoAvif) { continue }
        if ($Force -or -not (Test-Path $avifOut)) {
            $ok = $false
            if ($HasAvifenc) {
                # avifenc quality: 0 (worst) - 100 (best); --min/--max control range
                $ok = Invoke-Tool 'avifenc' @('--min','15','--max','45','--speed','6',
                                                '-q', $AvifQuality,
                                                $srcFile.FullName, $avifOut)
                # avifenc has no built-in resize; downsize via ffmpeg first if needed
                if ($ok -and $w -ne 0) {
                    # Re-resize through ffmpeg if avifenc kept full res
                    $tmp = [System.IO.Path]::GetTempFileName() + '.png'
                    Invoke-Tool 'ffmpeg' @('-y','-hide_banner','-loglevel','error',
                                            '-i', $srcFile.FullName,
                                            '-vf', "scale=${w}:-2", $tmp) | Out-Null
                    if (Test-Path $tmp) {
                        Remove-Item $avifOut -ErrorAction SilentlyContinue
                        Invoke-Tool 'avifenc' @('--min','15','--max','45','--speed','6',
                                                  '-q', $AvifQuality, $tmp, $avifOut) | Out-Null
                        Remove-Item $tmp -ErrorAction SilentlyContinue
                    }
                }
            } elseif ($HasFfmpeg) {
                # libaom-av1 still encoding - slower but works
                $ok = Invoke-Tool 'ffmpeg' @('-y','-hide_banner','-loglevel','error',
                                              '-i', $srcFile.FullName,
                                              '-vf', "scale='min(${w},iw)':-2",
                                              '-c:v','libaom-av1','-still-picture','1',
                                              '-crf', [string](63 - [int]($AvifQuality * 0.45)),
                                              '-b:v','0',
                                              $avifOut)
            }
            if ($DryRun) { continue }
            if ($ok -and (Test-Path $avifOut)) {
                Add-Stat 'BytesOut' ((Get-Item $avifOut).Length)
                Write-Host ("    + {0}" -f (Split-Path $avifOut -Leaf)) -ForegroundColor Green
            } else {
                Write-Host ("    ! AVIF failed for {0} @ {1}w" -f $srcFile.Name, $w) -ForegroundColor Yellow
            }
        } else {
            Add-Stat 'BytesOut' ((Get-Item $avifOut).Length)
        }
    }
    Add-Stat 'BytesIn' $srcBytes
    Add-Stat 'ImagesProcessed' 1
}

# ---------------------------------------------------------------------------
# VIDEO PIPELINE
# ---------------------------------------------------------------------------
function Convert-Video($srcFile) {
    $dir  = $srcFile.DirectoryName
    $name = [System.IO.Path]::GetFileNameWithoutExtension($srcFile.Name)
    $srcBytes = $srcFile.Length

    # 1) Optimised MP4 (re-encode at lower bitrate, capped resolution).
    #    Saved with .opt.mp4 suffix so the original .mp4 is untouched.
    $mp4Out = Join-Path $dir ("{0}.opt.mp4" -f $name)
    if ($Force -or -not (Test-Path $mp4Out)) {
        $ok = Invoke-Tool 'ffmpeg' @('-y','-hide_banner','-loglevel','error',
                                       '-i', $srcFile.FullName,
                                       '-vf', "scale='min(iw,trunc(oh*iw/ih/2)*2):min($VideoMaxHeight,ih)'",
                                       '-c:v','libx264','-preset','slow','-crf', $VideoCrfMp4,
                                       '-pix_fmt','yuv420p',
                                       '-movflags','+faststart',
                                       '-an',  # decorative - drop audio
                                       $mp4Out)
        if ($DryRun) { } elseif ($ok -and (Test-Path $mp4Out)) {
            Add-Stat 'BytesOut' ((Get-Item $mp4Out).Length)
            Write-Host ("    + {0}" -f (Split-Path $mp4Out -Leaf)) -ForegroundColor Green
        } else {
            Write-Host ("    ! MP4 re-encode failed for {0}" -f $srcFile.Name) -ForegroundColor Red
        }
    } else {
        Add-Stat 'BytesOut' ((Get-Item $mp4Out).Length)
    }

    # 2) WebM (VP9) sibling (skipped when -NoWebm)
    $webmOut = Join-Path $dir ("{0}.webm" -f $name)
    if (-not $NoWebm -and ($Force -or -not (Test-Path $webmOut))) {
        $ok = Invoke-Tool 'ffmpeg' @('-y','-hide_banner','-loglevel','error',
                                       '-i', $srcFile.FullName,
                                       '-vf', "scale='min(iw,trunc(oh*iw/ih/2)*2):min($VideoMaxHeight,ih)'",
                                       '-c:v','libvpx-vp9','-crf', $VideoCrfWebm,'-b:v','0',
                                       '-row-mt','1','-deadline','good','-cpu-used','2',
                                       '-an',
                                       $webmOut)
        if ($DryRun) { } elseif ($ok -and (Test-Path $webmOut)) {
            Add-Stat 'BytesOut' ((Get-Item $webmOut).Length)
            Write-Host ("    + {0}" -f (Split-Path $webmOut -Leaf)) -ForegroundColor Green
        } else {
            Write-Host ("    ! WebM failed for {0}" -f $srcFile.Name) -ForegroundColor Red
        }
    } elseif (-not $NoWebm -and (Test-Path $webmOut)) {
        Add-Stat 'BytesOut' ((Get-Item $webmOut).Length)
    }

    # 3) Poster JPG (first frame) for use in <video poster="...">
    $posterOut = Join-Path $dir ("{0}.poster.jpg" -f $name)
    if ($Force -or -not (Test-Path $posterOut)) {
        $ok = Invoke-Tool 'ffmpeg' @('-y','-hide_banner','-loglevel','error',
                                       '-i', $srcFile.FullName,
                                       '-vf', "select=eq(n\,0),scale='min(iw,1280):-2'",
                                       '-frames:v','1','-q:v','5',
                                       $posterOut)
        if ($DryRun) { } elseif ($ok -and (Test-Path $posterOut)) {
            Add-Stat 'BytesOut' ((Get-Item $posterOut).Length)
            Write-Host ("    + {0}" -f (Split-Path $posterOut -Leaf)) -ForegroundColor Green
        }
    } else {
        Add-Stat 'BytesOut' ((Get-Item $posterOut).Length)
    }

    Add-Stat 'BytesIn' $srcBytes
    Add-Stat 'VideosProcessed' 1
}

# ---------------------------------------------------------------------------
# RUN - IMAGES
# ---------------------------------------------------------------------------
if ($Images) {
    Write-Host ""
    Write-Host "--- IMAGES --------------------------------------------------------" -ForegroundColor Cyan

    $imageDirs = @(
        (Join-Path $Root 'images/image-web'),
        (Join-Path $Root 'images/image-abiliti')
    )

    foreach ($d in $imageDirs) {
        if (-not (Test-Path -LiteralPath $d)) { continue }
        # -LiteralPath avoids $-expansion on filenames; -Filter is fastest
        $files = @()
        $files += Get-ChildItem -LiteralPath $d -File -Filter '*.jpg'  -ErrorAction SilentlyContinue
        $files += Get-ChildItem -LiteralPath $d -File -Filter '*.jpeg' -ErrorAction SilentlyContinue
        $files += Get-ChildItem -LiteralPath $d -File -Filter '*.png'  -ErrorAction SilentlyContinue
        Write-Host ("  Directory: {0}  ({1} files)" -f $d, $files.Count) -ForegroundColor White
        foreach ($f in $files) {
            Write-Host ("  > {0}  ({1})" -f $f.Name, (Format-Bytes $f.Length))
            Convert-Image $f
        }
    }
}

# ---------------------------------------------------------------------------
# RUN - VIDEOS
# ---------------------------------------------------------------------------
if ($Videos) {
    Write-Host ""
    Write-Host "--- VIDEOS --------------------------------------------------------" -ForegroundColor Cyan

    # Videos live in /video AND at project root.
    # -LiteralPath + -Filter avoids $-expansion / wildcard issues in filenames.
    $videoFiles = @()
    $videoDir = Join-Path $Root 'video'
    if (Test-Path -LiteralPath $videoDir) {
        $videoFiles += Get-ChildItem -LiteralPath $videoDir -File -Filter '*.mp4' `
                       | Where-Object { $_.Name -notmatch '\.opt\.mp4$' }
    }
    $videoFiles += Get-ChildItem -LiteralPath $Root -File -Filter '*.mp4' `
                   | Where-Object { $_.Name -notmatch '\.opt\.mp4$' }

    Write-Host ("  Total videos: {0}" -f $videoFiles.Count) -ForegroundColor White
    foreach ($f in $videoFiles) {
        Write-Host ("  > {0}  ({1})" -f $f.Name, (Format-Bytes $f.Length))
        Convert-Video $f
    }
}

# ---------------------------------------------------------------------------
# REPORT
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host " SUMMARY" -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host (" Images processed : {0}" -f $Stats.ImagesProcessed)
Write-Host (" Videos processed : {0}" -f $Stats.VideosProcessed)
Write-Host (" Bytes IN (originals, untouched) : {0}" -f (Format-Bytes $Stats.BytesIn))
Write-Host (" Bytes OUT (new optimised files) : {0}" -f (Format-Bytes $Stats.BytesOut))
if ($Stats.BytesIn -gt 0) {
    $ratio = 1 - ($Stats.BytesOut / $Stats.BytesIn)
    $sign  = if ($ratio -ge 0) {'-'} else {'+'}
    Write-Host (" Net change vs originals          : {0}{1:P1}" -f $sign, [Math]::Abs($ratio))
}
Write-Host ""
Write-Host " Originals are unchanged. Optimised files live next to them." -ForegroundColor Green
Write-Host " Next step: update index.html <img>/<video> to reference them" -ForegroundColor Green
Write-Host " (see optimize-media.README.md for the snippet)." -ForegroundColor Green
Write-Host ""
