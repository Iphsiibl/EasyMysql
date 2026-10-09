# Structure check: every article 01-23 must have H1 + the fixed section skeleton.
# ASCII-only source (PS 5.1 reads no-BOM files as ANSI).
$ErrorActionPreference = "Continue"
Set-Location (Split-Path $PSScriptRoot)

$miss = 0
$docs = Get-ChildItem docs/*.md | Where-Object { $_.Name -match '^(0[1-9]|1[0-9]|2[0-3])-' } | Sort-Object Name
foreach ($d in $docs) {
    $c = Get-Content $d.FullName -Raw -Encoding UTF8
    $problems = @()
    if ($c -notmatch '(?m)^# [0-9]{2} \u00b7 ') { $problems += "H1" }
    if ($c -notmatch '(?m)^> \*\*') { $problems += "VALUE" }
    # structural markers: folded answers, runnable SQL, real output
    if ($c -notmatch '<details>') { $problems += "details" }
    if ($c -notmatch '```sql') { $problems += "sql-fence" }
    if ($c -notmatch '```text') { $problems += "text-fence" }
    $h2Count = ([regex]::Matches($c, '(?m)^## ')).Count
    if ($h2Count -lt 7) { $problems += ("H2-count=" + $h2Count) }
    if ($problems.Count -gt 0) {
        $miss++
        Write-Host ("STRUCT {0}: {1}" -f $d.Name, ($problems -join ", ")) -ForegroundColor Yellow
    }
}
Write-Host ("structure-issues={0} / files={1}" -f $miss, $docs.Count)
