[CmdletBinding()]
param(
    [switch]$PrepareOnly,
    [string]$SourceFolder
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$photoDirectory = Join-Path $repoRoot 'photos'
$dataDirectory = Join-Path $repoRoot 'data'
if (-not $SourceFolder) { $SourceFolder = Join-Path $repoRoot 'Photo inbox' }

function Write-DisplayCopy {
    param($Image, [int]$MaximumEdge, [string]$Destination)
    $scale = [Math]::Min(1.0, $MaximumEdge / [double][Math]::Max($Image.Width, $Image.Height))
    $width = [Math]::Max(1, [int][Math]::Round($Image.Width * $scale))
    $height = [Math]::Max(1, [int][Math]::Round($Image.Height * $scale))
    $bitmap = New-Object Drawing.Bitmap($width, $height)
    $graphics = $null
    $encoderParameters = $null
    $temporaryPath = $Destination + '.tmp'
    try {
        $graphics = [Drawing.Graphics]::FromImage($bitmap)
        $graphics.Clear([Drawing.Color]::White)
        $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.DrawImage($Image, 0, 0, $width, $height)
        $codec = [Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
        $encoderParameters = New-Object Drawing.Imaging.EncoderParameters(1)
        $encoderParameters.Param[0] = New-Object Drawing.Imaging.EncoderParameter([Drawing.Imaging.Encoder]::Quality, [long]87)
        $bitmap.Save($temporaryPath, $codec, $encoderParameters)
        Move-Item -LiteralPath $temporaryPath -Destination $Destination -Force
    }
    finally {
        if ($graphics) { $graphics.Dispose() }
        if ($encoderParameters) { $encoderParameters.Dispose() }
        $bitmap.Dispose()
        if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force }
    }
    return @{ Width = $width; Height = $height }
}

function Invoke-RepositoryGit {
    param([string[]]$GitArguments)
    # Windows PowerShell wraps native stderr (including normal Git progress) as errors.
    $ErrorActionPreference = 'Continue'
    $result = & $script:gitExecutable -C $repoRoot @GitArguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw (($result | Out-String).Trim()) }
    return $result | ForEach-Object { $_.ToString() }
}

try {
    Add-Type -AssemblyName System.Drawing
    if (-not (Test-Path -LiteralPath $SourceFolder -PathType Container)) {
        throw 'The Photo inbox folder could not be found. Create it beside Publish website.cmd, then copy your photos into it.'
    }
    $sourceRoot = (Get-Item -LiteralPath $SourceFolder).FullName.TrimEnd('\')
    New-Item -ItemType Directory -Force -Path $photoDirectory, $dataDirectory | Out-Null
    $supported = @('.jpg', '.jpeg', '.png', '.bmp', '.tif', '.tiff')
    $allFiles = @(Get-ChildItem -LiteralPath $sourceRoot -Recurse -File | Sort-Object FullName)
    $files = @($allFiles | Where-Object { $supported -contains $_.Extension.ToLowerInvariant() })
    $unsupported = @($allFiles | Where-Object { $supported -notcontains $_.Extension.ToLowerInvariant() -and $_.Name -notin @('Thumbs.db', 'Desktop.ini') })
    if ($unsupported.Count -gt 0) {
        Write-Host ('Skipping {0} unsupported file(s). Export HEIC and RAW photos as JPEG first.' -f $unsupported.Count) -ForegroundColor Yellow
    }
    $entries = New-Object 'System.Collections.Generic.List[object]'
    Write-Host 'Preparing your photographs. Originals stay untouched.' -ForegroundColor Cyan
    foreach ($file in $files) {
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $displayPath = Join-Path $photoDirectory ($hash + '.jpg')
        $thumbPath = Join-Path $photoDirectory ($hash + '-thumb.jpg')
        $image = $null
        try {
            # Decode from bytes so files in a OneDrive folder are not held open during processing.
            $imageStream = New-Object IO.MemoryStream(,[IO.File]::ReadAllBytes($file.FullName))
            try {
                $image = [Drawing.Image]::FromStream($imageStream, $true, $true)
                # Respect camera/phone orientation, then export a fresh bitmap without EXIF/GPS metadata.
                if ($image.PropertyIdList -contains 274) {
                    $orientation = [BitConverter]::ToUInt16($image.GetPropertyItem(274).Value, 0)
                    switch ($orientation) {
                        2 { $image.RotateFlip([Drawing.RotateFlipType]::RotateNoneFlipX) }
                        3 { $image.RotateFlip([Drawing.RotateFlipType]::Rotate180FlipNone) }
                        4 { $image.RotateFlip([Drawing.RotateFlipType]::Rotate180FlipX) }
                        5 { $image.RotateFlip([Drawing.RotateFlipType]::Rotate90FlipX) }
                        6 { $image.RotateFlip([Drawing.RotateFlipType]::Rotate90FlipNone) }
                        7 { $image.RotateFlip([Drawing.RotateFlipType]::Rotate270FlipX) }
                        8 { $image.RotateFlip([Drawing.RotateFlipType]::Rotate270FlipNone) }
                    }
                }
                $displayScale = [Math]::Min(1.0, 2400 / [double][Math]::Max($image.Width, $image.Height))
                $thumbScale = [Math]::Min(1.0, 1000 / [double][Math]::Max($image.Width, $image.Height))
                $displaySize = @{ Width = [Math]::Max(1, [int][Math]::Round($image.Width * $displayScale)); Height = [Math]::Max(1, [int][Math]::Round($image.Height * $displayScale)) }
                $thumbSize = @{ Width = [Math]::Max(1, [int][Math]::Round($image.Width * $thumbScale)); Height = [Math]::Max(1, [int][Math]::Round($image.Height * $thumbScale)) }
                if (-not (Test-Path -LiteralPath $displayPath)) { $displaySize = Write-DisplayCopy $image 2400 $displayPath }
                if (-not (Test-Path -LiteralPath $thumbPath)) { $thumbSize = Write-DisplayCopy $image 1000 $thumbPath }
                $relativeFolder = $file.DirectoryName.Substring($sourceRoot.Length).TrimStart('\')
                $album = if ($relativeFolder) { $relativeFolder -replace '\\', ' / ' } else { 'Journal' }
                $title = ($file.BaseName -replace '[_-]+', ' ').Trim()
                $entries.Add([ordered]@{
                    id = $hash
                    title = $title
                    album = $album
                    src = 'photos/' + $hash + '.jpg'
                    thumb = 'photos/' + $hash + '-thumb.jpg'
                    width = $displaySize.Width
                    height = $displaySize.Height
                    thumbWidth = $thumbSize.Width
                    thumbHeight = $thumbSize.Height
                })
            }
            finally {
                if ($image) { $image.Dispose() }
                $imageStream.Dispose()
            }
        }
        catch { throw ('Could not prepare "{0}". Try exporting it as a standard JPEG. Details: {1}' -f $file.Name, $_.Exception.Message) }
    }
    if ($files.Count -eq 0 -and $unsupported.Count -gt 0) { throw 'No supported photos were found. Export your photos as JPEG, copy them into Photo inbox, and try again.' }
    $manifest = [ordered]@{ photos = @($entries.ToArray()) }
    $json = ConvertTo-Json -InputObject $manifest -Depth 6
    $manifestPath = Join-Path $dataDirectory 'photos.json'
    $manifestTemporaryPath = $manifestPath + '.tmp'
    [IO.File]::WriteAllText($manifestTemporaryPath, $json + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $manifestTemporaryPath -Destination $manifestPath -Force
    $totalBytes = (Get-ChildItem -LiteralPath $photoDirectory -File | Measure-Object Length -Sum).Sum
    if (-not $totalBytes) { $totalBytes = 0 }
    $sizeMB = [Math]::Round($totalBytes / 1MB, 1)
    Write-Host ('Ready: {0} photograph(s). Display copies use {1} MB.' -f $entries.Count, $sizeMB) -ForegroundColor Green
    if ($totalBytes -gt 800MB) { Write-Host 'Your display copies are approaching the free hosting size limit. Consider a smaller selection before publishing.' -ForegroundColor Yellow }
    if ($totalBytes -gt 950MB) { throw 'Display copies are too close to the 1 GB hosting limit. Please reduce the selection before publishing.' }
    if ($PrepareOnly) { Write-Host 'Prepared locally. Nothing was uploaded.'; exit 0 }
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot '.git'))) { throw 'This folder is not connected to GitHub. Open the cloned mush folder from GitHub Desktop.' }
    $gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($gitCommand) { $script:gitExecutable = $gitCommand.Source }
    else {
        $desktopGit = Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA 'GitHubDesktop\app-*\resources\app\git\cmd\git.exe') -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($desktopGit) { $script:gitExecutable = $desktopGit.FullName }
        else { throw 'Git could not be found. Open GitHub Desktop to publish the prepared changes with Commit to main, then Push origin.' }
    }
    $branch = [string](Invoke-RepositoryGit -GitArguments @('branch', '--show-current'))
    if ($branch.Trim() -ne 'main') { throw 'Please switch to the main branch in GitHub Desktop before publishing.' }
    $remote = [string](Invoke-RepositoryGit -GitArguments @('remote', 'get-url', 'origin'))
    if ($remote.Trim() -notmatch '^(https://github\.com/YammyCookie/mush(?:\.git)?/?|git@github\.com:YammyCookie/mush(?:\.git)?)$') { throw 'The GitHub destination is not YammyCookie/mush. Check the repository in GitHub Desktop.' }
    Write-Host 'Checking GitHub for newer changes...'
    Invoke-RepositoryGit -GitArguments @('fetch', 'origin', 'main') | Out-Host
    $behind = [int]([string](Invoke-RepositoryGit -GitArguments @('rev-list', '--count', 'HEAD..FETCH_HEAD'))).Trim()
    if ($behind -gt 0) { throw 'There are newer changes on GitHub. Open GitHub Desktop and review/pull them before trying Publish again. Your prepared photos are still here.' }
    # Explicit paths keep the original Photo inbox and unrelated local files out of uploads.
    $publishPaths = @('index.html', 'assets/style.css', 'assets/gallery.js', 'assets/favicon.svg', 'data/photos.json', 'photos', '.nojekyll', '.gitignore', 'scripts/Publish-Website.ps1', 'Publish website.cmd', 'Prepare photos.cmd', 'START HERE.txt')
    Invoke-RepositoryGit -GitArguments (@('add', '--') + $publishPaths) | Out-Host
    $stagedPaths = @(Invoke-RepositoryGit -GitArguments @('diff', '--cached', '--name-only'))
    foreach ($stagedPath in $stagedPaths) {
        if ($stagedPath -notmatch '^(index\.html|assets/(style\.css|gallery\.js|favicon\.svg)|data/photos\.json|photos/[a-f0-9]{64}(?:-thumb)?\.jpg|\.nojekyll|\.gitignore|scripts/Publish-Website\.ps1|Publish website\.cmd|Prepare photos\.cmd|START HERE\.txt)$') {
            throw 'Other files are already selected for commit. Review them in GitHub Desktop, then try again.'
        }
    }
    if ($stagedPaths.Count -gt 0) {
        Invoke-RepositoryGit -GitArguments @('commit', '-m', ('Update photography portfolio ({0} photographs)' -f $entries.Count)) | Out-Host
    }
    Invoke-RepositoryGit -GitArguments @('push', 'origin', 'main') | Out-Host
    Write-Host ''
    Write-Host 'Uploaded successfully. GitHub Pages may take a few minutes to update.' -ForegroundColor Green
    Write-Host 'https://yammycookie.github.io/mush/'
}
catch {
    Write-Host ''
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host 'Your original photographs have not been changed.'
    exit 1
}
