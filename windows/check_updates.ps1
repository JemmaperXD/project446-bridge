# Project 446 bridge: check GitHub for a newer release.
#
# ASCII only on purpose: Windows PowerShell 5.1 reads BOM-less scripts as ANSI.
# Prints exactly one line for the .bat wrappers:
#   UPDATE <current> <latest>
#   OK <current> <latest>
#   ERROR <current>
#
# Result is cached in update_check.txt for 24 hours, so the automatic check in
# start_bridge.bat does not hit GitHub on every game launch.
#
# Exit codes: 0 = up to date, 10 = update available, 1 = check failed.

param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$repo   = 'JemmaperXD/project446-bridge'
$here   = Split-Path -Parent $MyInvocation.MyCommand.Path
$bridge = Join-Path $here 'bridge.py'
$cache  = Join-Path $here 'update_check.txt'

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch { }

function Get-LocalVersion {
    if (-not (Test-Path -LiteralPath $bridge)) { return '0.0.0' }
    $m = Select-String -LiteralPath $bridge -Pattern '^VERSION\s*=\s*"([^"]+)"' |
         Select-Object -First 1
    if ($m) { return $m.Matches[0].Groups[1].Value }
    return '0.0.0'
}

function Compare-Version($a, $b) {
    $pa = ($a -replace '^v', '').Split('.')
    $pb = ($b -replace '^v', '').Split('.')
    $n = [Math]::Max($pa.Count, $pb.Count)
    for ($i = 0; $i -lt $n; $i++) {
        $x = 0
        $y = 0
        if ($i -lt $pa.Count) { [void][int]::TryParse($pa[$i], [ref]$x) }
        if ($i -lt $pb.Count) { [void][int]::TryParse($pb[$i], [ref]$y) }
        if ($x -gt $y) { return 1 }
        if ($x -lt $y) { return -1 }
    }
    return 0
}

$current = Get-LocalVersion
$latest  = $null

try {
    $epoch = [datetime]::SpecifyKind([datetime]'1970-01-01', [DateTimeKind]::Utc)
    $now   = [int]([datetime]::UtcNow - $epoch).TotalSeconds
} catch { $now = 0 }

if (-not $Force -and (Test-Path -LiteralPath $cache)) {
    try {
        $parts = (Get-Content -LiteralPath $cache -Raw).Trim().Split('|')
        if ($parts.Count -ge 2 -and $parts[1]) {
            if ($now - [int]$parts[0] -lt 86400) { $latest = $parts[1] }
        }
    } catch { }
}

if (-not $latest) {
    try {
        $uri = "https://api.github.com/repos/$repo/releases/latest"
        $r = Invoke-RestMethod -Uri $uri -Headers @{ 'User-Agent' = 'project446-bridge' } -TimeoutSec 4
        $latest = [string]$r.tag_name
        if ($latest) {
            try {
                Set-Content -LiteralPath $cache -Value ("{0}|{1}" -f $now, $latest) -Encoding ASCII
            } catch { }
        }
    } catch {
        try {
            $parts = (Get-Content -LiteralPath $cache -Raw).Trim().Split('|')
            if ($parts.Count -ge 2) { $latest = $parts[1] }
        } catch { }
        if (-not $latest) {
            Write-Output ("ERROR {0}" -f $current)
            exit 1
        }
    }
}

if ((Compare-Version $latest $current) -gt 0) {
    Write-Output ("UPDATE {0} {1}" -f $current, $latest)
    exit 10
}

Write-Output ("OK {0} {1}" -f $current, $latest)
exit 0
