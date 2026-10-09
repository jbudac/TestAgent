Set-Location $PSScriptRoot\..\
$files = (git diff --staged --name-only) -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
if ($files.Count -eq 0) {
    Write-Host 'No staged files.'
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

Write-Host '---PROPOSED COMMIT MESSAGE---' -ForegroundColor Cyan
Write-Host "Subject: $subject" -ForegroundColor White
Write-Host "Body:`n$body" -ForegroundColor DarkGray
