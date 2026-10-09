Set-Location $PSScriptRoot\..\

$files = (git diff --staged --name-only) -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
if ($files.Count -eq 0) {
    Write-Host 'No staged files to commit.'
    exit 0
}

if ($files.Count -eq 1) {
    $name = [System.IO.Path]::GetFileName($files[0])
    $subject = "Update $name"
    $body = "Modified file: $name"
} else {
    $dirs = $files | ForEach-Object { Split-Path $_ -Parent } | Where-Object { $_ -ne '' } | Select-Object -Unique
    $exts = $files | ForEach-Object { [System.IO.Path]::GetExtension($_).TrimStart('.') } | Where-Object { $_ -ne '' } | Group-Object | Sort-Object Count -Descending | ForEach-Object { $_.Name }
    $subject = "Update $($files.Count) files"
    if ($dirs.Count -le 3 -and $dirs.Count -gt 0) { $subject += ' in ' + ($dirs -join ', ') }
    elseif ($dirs.Count -gt 0) { $subject += ' across multiple directories' }
    if ($exts.Count -gt 0) { $subject += ' (' + (($exts | Select-Object -First 3) -join ', ') + ')' }
    $body = "Files changed:`n" + ($files -join "`n")
}

$msgFile = [IO.Path]::GetTempFileName()
Set-Content -Path $msgFile -Value $subject -Encoding utf8
Add-Content -Path $msgFile -Value "`n" -Encoding utf8
Add-Content -Path $msgFile -Value $body -Encoding utf8

Write-Host "Committing with message:" -ForegroundColor Cyan
Write-Host "Subject: $subject" -ForegroundColor White

git commit -F $msgFile
$commitCode = $LASTEXITCODE
if ($commitCode -ne 0) {
    Write-Error "Commit failed (exit code $commitCode)"
    Remove-Item $msgFile -ErrorAction SilentlyContinue
    exit $commitCode
}

$current = (git rev-parse --abbrev-ref HEAD).Trim()
if (-not $current) {
    Write-Error "Unable to determine current branch"
    Remove-Item $msgFile -ErrorAction SilentlyContinue
    exit 1
}

Write-Host "Pushing branch: $current" -ForegroundColor Cyan
git push -u origin $current
$pushCode = $LASTEXITCODE
Remove-Item $msgFile -ErrorAction SilentlyContinue
if ($pushCode -eq 0) {
    Write-Host "Pushed successfully." -ForegroundColor Green
    exit 0
} else {
    Write-Error "Push failed (exit code $pushCode)"
    exit $pushCode
}
