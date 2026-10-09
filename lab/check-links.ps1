# Check: link text of "next article" section must equal target file's H1 (ASCII-only source; PS 5.1 reads no-BOM files as ANSI)
$ErrorActionPreference = "Continue"
Set-Location (Split-Path $PSScriptRoot)

$docs = Get-ChildItem docs/*.md | Where-Object { $_.Name -notlike '_*' }
$map = @{}
foreach ($d in $docs) {
    $c = Get-Content $d.FullName -Raw -Encoding UTF8
    if ($c -match '(?m)^# (.+)$') { $map[$d.Name] = $Matches[1].Trim() }
}

$checked = 0
$problems = 0
$noNext = @()
foreach ($d in $docs) {
    $c = Get-Content $d.FullName -Raw -Encoding UTF8
    # heading of exactly 3 Han chars (next-article heading) followed by a markdown link
    if ($c -match '(?s)## [\u4e00-\u9fff]{3}\s*\[([^\]]+)\]\(([^)]+\.md)\)') {
        $checked++
        $text = $Matches[1].Trim()
        $target = $Matches[2]
        $expected = $map[$target]
        if (-not $expected) {
            Write-Host ("MISSING-TARGET {0} -> {1}" -f $d.Name, $target) -ForegroundColor Red
            $problems++
        }
        elseif ($text -ne $expected) {
            Write-Host ("MISMATCH {0}" -f $d.Name) -ForegroundColor Yellow
            Write-Host ("   link text: {0}" -f $text)
            Write-Host ("   target H1: {0}" -f $expected)
            $problems++
        }
    }
    else {
        $noNext += $d.Name
    }
}
Write-Host ("checked={0} problems={1}" -f $checked, $problems)
Write-Host ("no-next-link: " + ($noNext -join ", "))
