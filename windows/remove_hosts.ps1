# Project 446: remove "127.0.0.1 gc.project446.com" from the Windows hosts file.
#
# ASCII only on purpose: Windows PowerShell 5.1 reads BOM-less scripts as ANSI.
# Removes our record, our marker and repairs a glued record from old versions
# (e.g. "127.0.0.1 localhost127.0.0.1 gc.project446.com" -> "127.0.0.1 localhost").
#
# Exit codes: 0 = removed, 10 = nothing found, 1 = error.

$ErrorActionPreference = 'Stop'

try {
    $path = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
    if (-not (Test-Path -LiteralPath $path)) { exit 1 }

    $exactPattern = '^\s*127\.0\.0\.1\s+gc\.project446\.com\s*$'
    $gluedSuffix  = '\s*127\.0\.0\.1\s+gc\.project446\.com\s*$'
    $marker       = '^\s*#\s*project446-bridge\s*$'

    $lines   = [System.IO.File]::ReadAllLines($path)
    $result  = New-Object 'System.Collections.Generic.List[string]'
    $changed = $false

    foreach ($line in $lines) {
        if ($line -match $marker) {
            $changed = $true
            continue
        }

        if ($line -match $exactPattern) {
            $changed = $true
            continue
        }

        if ($line -match $gluedSuffix) {
            $prefix = ($line -replace $gluedSuffix, '').TrimEnd()
            $changed = $true
            if ($prefix.Length -eq 0) { continue }
            if ($prefix.Trim() -match '^#+$') { continue }
            $result.Add($prefix)
            continue
        }

        $result.Add($line)
    }

    if ($changed) {
        [System.IO.File]::WriteAllLines($path, $result)
    }

    if ($changed) { exit 0 }
    exit 10
}
catch {
    exit 1
}
