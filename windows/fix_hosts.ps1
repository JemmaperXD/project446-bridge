# Project 446: add or fix "127.0.0.1 gc.project446.com" in the Windows hosts file.
#
# ASCII only on purpose: Windows PowerShell 5.1 reads BOM-less scripts as ANSI.
#
# Why this script exists: the old installer appended the line with
#   >>hosts echo 127.0.0.1 gc.project446.com
# If the hosts file did not end with a newline, the record got glued to the
# last line, e.g. "127.0.0.1 localhost127.0.0.1 gc.project446.com".
# This script splits such a line back and writes a clean record.
#
# Exit codes: 0 = added/fixed, 10 = already present, 1 = error.

$ErrorActionPreference = 'Stop'

try {
    $path = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
    if (-not (Test-Path -LiteralPath $path)) { exit 1 }

    $validPattern  = '^\s*127\.0\.0\.1\s+gc\.project446\.com\s*$'
    $gluedPattern  = '^(?<prefix>.*\S)\s*127\.0\.0\.1\s+gc\.project446\.com\s*$'

    $lines   = [System.IO.File]::ReadAllLines($path)
    $result  = New-Object 'System.Collections.Generic.List[string]'
    $found   = $false
    $changed = $false

    foreach ($line in $lines) {
        if ($line -match $validPattern) {
            if (-not $found) {
                $result.Add('127.0.0.1 gc.project446.com')
                $found = $true
            } else {
                $changed = $true          # drop duplicate
            }
            continue
        }

        if ($line -match $gluedPattern) {
            $prefix = $Matches['prefix'].Trim()
            # Keep the original line, but not a lone "#" left from a
            # commented-out record.
            if ($prefix.Length -gt 0 -and $prefix -notmatch '^#+$') {
                $result.Add($prefix)
            }
            $changed = $true
            continue
        }

        $result.Add($line)
    }

    if (-not $found) {
        $result.Add('127.0.0.1 gc.project446.com')
        $changed = $true
    }

    if ($changed) {
        # WriteAllLines emits CRLF on Windows and always terminates the last line.
        [System.IO.File]::WriteAllLines($path, $result)
    }

    if ($found) { exit 10 }
    exit 0
}
catch {
    exit 1
}
