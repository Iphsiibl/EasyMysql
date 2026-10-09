# =============================================================================
# verify-queries.ps1  批量检查 lab/queries/ 下所有实验文件能否正常执行
#
# 用法：powershell -ExecutionPolicy Bypass -File lab/verify-queries.ps1
#
# 判定标准：
#   允许出现 4 条错误，它们是教程里「故意写错、用来演示数据库拦截脏数据」的语句。
#   任何新增的错误都算失败，退出码返回 1（可以直接接进 CI）。
# =============================================================================

$ErrorActionPreference = "Continue"
Set-Location $PSScriptRoot

# 故意写错的语句白名单：文件名 → 允许的错误条数
$expected = @{
    "10-demo-types.sql"      = 1   # 字符串金额转 DECIMAL 失败
    "11-demo-constraints.sql" = 1   # 分数超范围被拦截
    "18-demo-transaction.sql" = 1   # 错误语句触发回滚
    "23-demo-errors.sql"     = 1   # source 在第一条故意错误处中断（文末有对照说明）
}

$files    = Get-ChildItem "queries\*.sql" | Sort-Object Name
$failures = @()
$totalErr = 0

Write-Host "检查 $($files.Count) 个实验文件 ...`n" -ForegroundColor Cyan

foreach ($f in $files) {
    & docker cp $f.FullName "easy-mysql:/tmp/$($f.Name)" 2>&1 | Out-Null

    # 不传 --default-character-set：每个实验文件应该靠自己的 SET NAMES utf8mb4 工作
    $result = & docker exec easy-mysql mysql -uroot -peasy123 --force `
              -e "source /tmp/$($f.Name)" 2>&1 | Out-String

    $errors  = @(($result -split "`r?`n") | Where-Object { $_ -match "^ERROR" })
    $allowed = if ($expected.ContainsKey($f.Name)) { $expected[$f.Name] } else { 0 }
    $totalErr += $errors.Count

    if ($errors.Count -eq $allowed) {
        Write-Host ("  OK    {0}" -f $f.Name) -ForegroundColor DarkGray
    }
    else {
        Write-Host ("  FAIL  {0}  (期望 {1} 条错误，实际 {2} 条)" -f $f.Name, $allowed, $errors.Count) -ForegroundColor Red
        $errors | ForEach-Object { Write-Host "          $_" -ForegroundColor Red }
        $failures += $f.Name
    }
}

Write-Host ""
if ($failures.Count -eq 0) {
    Write-Host ("全部通过。错误总数 {0}（4 条为预期内的演示用错误）" -f $totalErr) -ForegroundColor Green
    exit 0
}
else {
    Write-Host "有 $($failures.Count) 个文件出现问题：$($failures -join ', ')" -ForegroundColor Red
    exit 1
}
