#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Interaktívny PowerShell skript na stage a commit Git zmien.

.DESCRIPTION
    Skript vypíše zoznam zmenených súborov, umožní vybrať súbory na stajgovanie,
    načíta commit message a spustí `git commit`.
#>

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Error "git not found in PATH. Install Git or add it to PATH."
    exit 1
}

$inside = & git rev-parse --is-inside-work-tree 2>$null
if ($LASTEXITCODE -ne 0 -or $inside -ne 'true') {
    Write-Error "Not inside a git repository. Run this inside a repo."
    exit 1
}

$statusRaw = & git status --porcelain
if (-not $statusRaw) {
    Write-Host "No changes to commit." -ForegroundColor Green
    exit 0
}

$lines = $statusRaw -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
$files = @()
foreach ($line in $lines) {
    if ($line.Length -ge 4) {
        $path = $line.Substring(3)
        $files += $path
    }
}

Write-Host "Changed files:" -ForegroundColor Cyan
for ($i = 0; $i -lt $files.Count; $i++) {
    Write-Host ("[{0}] {1}" -f ($i+1), $files[$i])
}

$sel = Read-Host "Select files to stage (comma-separated numbers), 'a' for all, 's' to stage partially by path, or 'c' to cancel"
if ($sel -match '^[Cc]') {
    Write-Host "Cancelled." -ForegroundColor Yellow
    exit 0
}

if ($sel -match '^[Aa]') {
    & git add -A
} elseif ($sel -match '^[Ss]') {
    $manual = Read-Host "Enter file paths to add (space-separated)"
    if ($manual) {
        $paths = $manual -split '\s+' | Where-Object { $_ -ne '' }
        foreach ($p in $paths) {
            & git add -- "$p"
        }
    } else {
        Write-Error "No paths provided. Aborting."
        exit 1
    }
} else {
    $indices = @()
    foreach ($token in ($sel -split ',')) {
        $t = $token.Trim()
        if ($t -ne '') {
            $ok = [int]::TryParse($t,[ref]$null)
            if ($ok) { $indices += [int]$t }
        }
    }
    if ($indices.Count -eq 0) {
        Write-Error "No valid selection. Aborting."
        exit 1
    }
    foreach ($idx in $indices) {
        if ($idx -ge 1 -and $idx -le $files.Count) {
            $f = $files[$idx - 1]
            & git add -- "$f"
        } else {
            Write-Error "Index $idx out of range."
        }
    }
}

Write-Host "`nStaged files:" -ForegroundColor Cyan
$stagedRaw = & git diff --staged --name-only
Write-Host $stagedRaw

$staged = $stagedRaw -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }

# Lightweight config to remember username across runs
$configPath = Join-Path $PSScriptRoot 'config.json'
function Read-Config() {
    if (Test-Path $configPath) {
        try { return (Get-Content $configPath -Raw | ConvertFrom-Json) } catch { return @{} }
    }
    return @{}
}
function Save-Config($obj) {
    $json = $obj | ConvertTo-Json -Depth 5
    $json | Out-File -FilePath $configPath -Encoding UTF8
}

# Support a special mode to start a new task branch:
# Usage: .\commit.ps1 start
$StartTask = $false
if ($args.Count -gt 0) {
    if ($args[0].ToLower() -in @('start','--start-task','-s')) { $StartTask = $true }
}

$config = Read-Config
if ($StartTask) {
    if (-not $config.username) {
        $u = Read-Host "Zadajte užívateľské meno (uložím pre budúce použitie)"
        if (-not $u) { Write-Error "Username required."; exit 1 }
        $config.username = $u
        Save-Config $config
        Write-Host "Užívateľské meno uložené." -ForegroundColor Green
    }
    $user = $config.username
    $ticket = Read-Host "Zadajte číslo US alebo bugu (napr. 1234 alebo BUG-12)"
    if (-not $ticket) { Write-Error "Ticket required. Aborting."; exit 1 }
    $safeUser = ($user -replace '\s+','_' -replace '[^A-Za-z0-9_\-]','').ToLower()
    $safeTicket = $ticket -replace '\s+','_' -replace '[^A-Za-z0-9_\-]',''
    $branchName = "users/$safeUser/$safeTicket"
    Write-Host "Vytváram a prepínam na branch: $branchName" -ForegroundColor Cyan
    & git checkout -b $branchName
    if ($LASTEXITCODE -ne 0) { Write-Error "Failed to create/checkout branch $branchName"; exit 1 }
    Write-Host "Branch created: $branchName" -ForegroundColor Green
    exit 0
}

# Generate commit message based on staged files
function Generate-CommitMessage($files) {
    $count = $files.Count
    if ($count -eq 0) { return @{ Subject = ""; Body = "" } }
    if ($count -eq 1) {
        $name = [System.IO.Path]::GetFileName($files[0])
        $subject = "Update $name"
        $body = "Modified file: $name"
        return @{ Subject = $subject; Body = $body }
    }
    $dirs = $files | ForEach-Object { Split-Path $_ -Parent } | Where-Object { $_ -ne '' } | Select-Object -Unique
    $exts = $files | ForEach-Object { [System.IO.Path]::GetExtension($_).TrimStart('.') } | Where-Object { $_ -ne '' } | Group-Object | Sort-Object Count -Descending | ForEach-Object { $_.Name }
    $subject = "Update $count files"
    if ($dirs.Count -le 3) { $subject += " in " + ($dirs -join ', ') }
    elseif ($dirs.Count -gt 0) { $subject += " across multiple directories" }
    if ($exts.Count -gt 0) { $subject += " ($([string]::Join(', ', $exts[0..([Math]::Min(2,$exts.Count-1))])) )" }
    $body = "Files changed:`n" + ($files -join "`n")
    return @{ Subject = $subject; Body = $body }
}

$gen = Generate-CommitMessage $staged
Write-Host "`nNavrhovaná commit správa (predvolená):" -ForegroundColor Cyan
Write-Host "Subject: $($gen.Subject)" -ForegroundColor White
Write-Host "Body:`n$($gen.Body)" -ForegroundColor DarkGray

# Ask for username on first commit (and remember it)
if (-not $config.username) {
    $u = Read-Host "Zadajte užívateľské meno (uložím pre budúce použitie)"
    if ($u) { $config.username = $u; Save-Config $config; Write-Host "Užívateľské meno uložené." -ForegroundColor Green }
}

# Allow user to edit or accept message
$choice = Read-Host "Akceptovať správu? (y = áno, e = upraviť, c = zrušiť)"
if ($choice -match '^[Cc]') {
    Write-Host "Cancelled." -ForegroundColor Yellow
    exit 0
}
if ($choice -match '^[Ee]') {
    $newSubject = Read-Host "Zadajte subject (nadpis)"
    if ($newSubject -ne '') { $gen.Subject = $newSubject }
    Write-Host "Zadajte body správy (zanechajte prázdne pre použitie automatického)"
    $newBody = Read-Host "Body"
    if ($newBody -ne '') { $gen.Body = $newBody }
}

# Ask action: commit-only or commit+push to current branch
Write-Host "\nVyberte akciu:" -ForegroundColor Cyan
Write-Host "[1] Len commit"
Write-Host "[2] Commit a push (pushne aktuálnu lokálnu branch na origin)"
$act = Read-Host "Zadajte 1 alebo 2 (alebo 'c' pre cancel)"
if ($act -match '^[Cc]') { Write-Host "Cancelled." -ForegroundColor Yellow; exit 0 }

function Do-Commit($subject, $body) {
    if ($body -ne '') {
        & git commit -m $subject -m $body
    } else {
        & git commit -m $subject
    }
    return $LASTEXITCODE
}

if ($act -eq '2') {
    $current = (& git rev-parse --abbrev-ref HEAD).Trim()
    if (-not $current) { Write-Error "Unable to determine current branch"; exit 1 }
    $code = Do-Commit $gen.Subject $gen.Body
    if ($code -ne 0) { Write-Error "Commit failed"; exit 1 }
    Write-Host "Pushing current branch $current to origin" -ForegroundColor Cyan
    & git push -u origin $current
    if ($LASTEXITCODE -eq 0) { Write-Host "Pushed successfully." -ForegroundColor Green } else { Write-Error "Push failed"; exit 1 }
} else {
    $code = Do-Commit $gen.Subject $gen.Body
    if ($code -eq 0) { Write-Host "Committed successfully." -ForegroundColor Green } else { Write-Error "Commit failed"; exit 1 }
}
