# 重置实验环境：删掉所有数据，重新建表造数
# 用法：powershell -ExecutionPolicy Bypass -File reset.ps1

# 注意：这里必须用 Continue。
# PowerShell 5.1 下，docker 把进度信息写到 stderr，
# 配合 ErrorActionPreference="Stop" 会直接终止脚本。
$ErrorActionPreference = "Continue"
Set-Location $PSScriptRoot

Write-Host "==> 停止并删除容器" -ForegroundColor Cyan
docker compose down -v

if (Test-Path ".data") {
    Write-Host "==> 删除残留数据目录 .data" -ForegroundColor Cyan
    Remove-Item -Recurse -Force ".data"
}

Write-Host "==> 重新启动（造 80 万行数据约需 20 秒）" -ForegroundColor Cyan
docker compose up -d

Write-Host "==> 等待数据库就绪" -ForegroundColor Cyan
$ready = $false
for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Seconds 2
    $state = docker inspect --format='{{.State.Health.Status}}' easy-mysql 2>$null
    if ($state -eq "healthy") {
        Write-Host "==> 已就绪，开始校验行数" -ForegroundColor Green
        $ready = $true
        break
    }
}

if (-not $ready) {
    Write-Host "超时未就绪，执行 docker logs easy-mysql 查看原因" -ForegroundColor Red
    exit 1
}

$expect = @{ students = 200; courses = 20; scores = 2000; users = 5000;
             orders = 200000; orders_slow = 200000; order_items = 600000; bad_design_demo = 20 }

$ok = $true
foreach ($t in $expect.Keys) {
    $n = docker exec easy-mysql mysql -uroot -peasy123 -N -B `
         -e "SELECT COUNT(*) FROM easy_mysql.$t;" 2>$null
    if ([int]$n -eq $expect[$t]) {
        Write-Host ("    OK   {0,-16} {1}" -f $t, $n) -ForegroundColor DarkGray
    }
    else {
        Write-Host ("    FAIL {0,-16} 期望 {1}，实际 {2}" -f $t, $expect[$t], $n) -ForegroundColor Red
        $ok = $false
    }
}

if ($ok) {
    Write-Host "`n重置完成。图形界面：http://localhost:8080" -ForegroundColor Green
}
else {
    Write-Host "`n行数对不上，检查 lab/init/ 里的脚本" -ForegroundColor Red
    exit 1
}
