# 21 · 备份与恢复：先假设数据库会消失

> **一句话价值**：亲手跑通一遍「备份 → 删 → 恢复 → 数行数」，让你手里那份 `.sql` 文件不再是自我安慰。

**难度**：⭐⭐　|　**时长**：约 40 分钟　|　**涉及表**：全部 8 张

## 什么时候你会遇到它

课程设计交作业的前一晚，你想把表结构改漂亮点，在终端里敲了 `DROP DATABASE school;` —— 手一抖少打了几个字，回车已经按下去了。数据没了，回收站里没有这一项，`Ctrl+Z` 也管不了数据库。

备份这件事最气人的地方是：**它只在出事那天显出价值，而那天你已经来不及补做了。**

## 本篇你会学到

- [ ] 逻辑备份、物理备份、binlog 三种方式**各自什么时候用**
- [ ] `mysqldump` 那串参数里 `--single-transaction`、`--databases` 到底改了什么
- [ ] 只备份表结构、只备份数据的两条命令
- [ ] 一次完整的**备份 → 删 → 恢复 → 校验行数**演练（本篇主菜）
- [ ] 用 binlog 把数据**恢复到某个时间点**
- [ ] 每天凌晨 3 点自动备份：Windows 计划任务 + Linux cron 各一份

---

## 1. 先选型：你要的是哪一种备份

| 方式 | 白话 | 工具 | 什么时候用 | 代价 |
|---|---|---|---|---|
| **逻辑备份**（logical backup） | 把数据重新写成一条条 `CREATE TABLE`、`INSERT` | `mysqldump` | 中小库、跨版本搬家、想打开看懂内容 | 恢复要重插一遍数据，慢 |
| **物理备份**（physical backup） | 直接复制数据文件 | 文件快照、`XtraBackup` | 上 TB 的大库、要求快 | 只能在同版本同平台用，挑不出一张表 |
| **binlog 增量**（binary log，二进制日志） | 记下全量备份之后的每一次改动 | `mysqlbinlog` | 全量 + 增量 = 回到任意时间点 | 只能补全量之后的部分 |

本仓库 8 张表、100 多万行，**逻辑备份够用，而且备份文件你打得开、看得懂** —— 后面全用 `mysqldump`。真到了生产库里几个 TB，才轮到物理备份出场。

## 2. 全量备份：一条命令

在本机 PowerShell 里跑（`--result-file` 让 mysqldump **自己写文件**，完全不经过 shell，绕开了后面要讲的编码坑）：

```powershell
docker exec easy-mysql mysqldump -uroot -peasy123 --single-transaction --databases easy_mysql --result-file=/tmp/easy_mysql_full.sql
docker cp easy-mysql:/tmp/easy_mysql_full.sql "$env:TEMP\easy_mysql_full.sql"
Get-Item "$env:TEMP\easy_mysql_full.sql" | Select-Object Length
```

```text
  Length
  ------
53885944
```

（`mysqldump: [Warning] Using a password ...` 这行是 stderr 的密码警告，下同，不再贴。）

53 MB 是 8 张表 100 多万行的全部内容。**这串参数逐个拆开：**

| 参数 | 干了什么 | 少了它会怎样 |
|---|---|---|
| `--single-transaction` | 开一个一致性快照事务（`START TRANSACTION WITH CONSISTENT SNAPSHOT`）再导出，**不锁表** | 80 万行导到一半被别人的写入插队，备份内容前后不一致 |
| `--databases easy_mysql` | 备份里带上建库语句，见下面的输出 | 只有表，没有 `CREATE DATABASE` |
| `--result-file=/tmp/...` | mysqldump 直接写容器内的文件 | 得靠 shell 重定向，PowerShell 会写成 UTF-16（见「常见错误」错误做法 1） |
| `--routines`（本库没用上） | 把存储过程、函数一起带走 | 你写的过程不会被备份，本库没有自定义过程，加不加都一样 |

打开文件看头部，`--databases` 的效果一目了然：

```powershell
docker exec easy-mysql sh -c "grep -a -n 'CREATE DATABASE\|^USE ' /tmp/easy_mysql_full.sql"
```

```text
22:CREATE DATABASE /*!32312 IF NOT EXISTS*/ `easy_mysql` /*!40100 DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci */ /*!80016 DEFAULT ENCRYPTION='N' */;
24:USE `easy_mysql`;
```

**恢复这份文件时，MySQL 会先建库再 USE 过去** —— 这正是第 4 节演练里要绕开的东西。

## 3. 只备份结构，或只备份数据

同一份数据可以拆成两半卖：

```powershell
# 只要表结构，一行数据都不要
docker exec easy-mysql mysqldump -uroot -peasy123 --no-data easy_mysql students --result-file=/tmp/students_schema.sql
docker exec easy-mysql sh -c "grep -a -c 'CREATE TABLE' /tmp/students_schema.sql; grep -a -c 'INSERT INTO' /tmp/students_schema.sql"

# 只要数据，连建表语句都不带
docker exec easy-mysql mysqldump -uroot -peasy123 --no-create-info easy_mysql students --result-file=/tmp/students_data.sql
docker exec easy-mysql sh -c "grep -a -c 'CREATE TABLE' /tmp/students_data.sql; grep -a -c 'INSERT INTO' /tmp/students_data.sql"
```

```text
1
0
0
1
```

结构文件里长这样（注释、字段类型、索引，一个 `INSERT` 都没有）：

```powershell
docker exec easy-mysql sh -c "sed -n '25,34p' /tmp/students_schema.sql"
```

```sql
CREATE TABLE `students` (
  `id` int unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `name` varchar(30) NOT NULL COMMENT '姓名',
  `gender` enum('男','女') NOT NULL DEFAULT '男' COMMENT '性别',
  `class_name` varchar(30) NOT NULL COMMENT '班级',
  `birth_date` date NOT NULL COMMENT '出生日期',
  `city` varchar(30) NOT NULL DEFAULT '未知' COMMENT '城市',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_students_name` (`name`)
```

数据文件里只有一条巨大的 `INSERT`（这行有 200 行数据，只截前 44 个字符）：

```powershell
docker exec easy-mysql sh -c "grep -a -n 'INSERT INTO' /tmp/students_data.sql | cut -c1-44"
```

```text
24:INSERT INTO `students` VALUES (1,'赵伟'
```

**什么时候用哪个**：改表结构前留一份 `--no-data`（几十 KB，随手就存）；把造好的数据灌进别人的库用 `--no-create-info`（对方已有表结构时别再 CREATE 一遍）。

## 4. 主菜：完整演练（备份 → 删 → 恢复 → 校验行数）

先划一条红线：**整个演练绝不对 `easy_mysql` 本体动手**。第 2 节那份带 `--databases` 的文件一旦恢复，会把 `easy_mysql` 整个重建 —— 所以演练要用「不带 `--databases`」的备份，恢复到一个**演练库** `easy_mysql_restore`。

**第一步：备份**（顺手清掉上次跑剩下的演练库，这条命令重跑几次都不会报错）

```powershell
docker exec easy-mysql mysqldump -uroot -peasy123 --single-transaction easy_mysql --result-file=/tmp/easy_mysql_tables.sql
docker exec easy-mysql mysql -uroot -peasy123 -e "DROP DATABASE IF EXISTS easy_mysql_restore; CREATE DATABASE easy_mysql_restore CHARACTER SET utf8mb4;"
```

**第二步：恢复（本机 49 秒）**

```powershell
Measure-Command { docker exec easy-mysql mysql -uroot -peasy123 --default-character-set=utf8mb4 easy_mysql_restore -e "source /tmp/easy_mysql_tables.sql" } | Select-Object TotalSeconds
```

```text
TotalSeconds
------------
   49.728154
```

> ⚠️ **这个秒数会随你的机器、磁盘、缓存变化，你的数字不会和我一样。** 值得记住的是数量级：百万行的库，恢复是「分钟级」，备份是「秒级」。

**第三步：数行数，确认真的回来了**（注意数的是**演练库**，本体从头到尾没人碰）

```powershell
docker exec easy-mysql mysql -uroot -peasy123 -t --default-character-set=utf8mb4 -e "SELECT (SELECT COUNT(*) FROM easy_mysql_restore.students) AS students, (SELECT COUNT(*) FROM easy_mysql_restore.users) AS users, (SELECT COUNT(*) FROM easy_mysql_restore.orders) AS orders, (SELECT COUNT(*) FROM easy_mysql_restore.order_items) AS order_items;"
```

```text
+----------+-------+--------+-------------+
| students | users | orders | order_items |
+----------+-------+--------+-------------+
|      200 |  5000 | 200000 |      600000 |
+----------+-------+--------+-------------+
```

再看一眼中文有没有坏（这是最容易翻车的一环）：

```powershell
docker exec easy-mysql mysql -uroot -peasy123 -t --default-character-set=utf8mb4 easy_mysql_restore -e "SELECT name FROM students ORDER BY id LIMIT 3;"
```

```text
+--------+
| name   |
+--------+
| 赵伟   |
| 赵芳   |
| 赵娜   |
+--------+
```

**第四步：故意搞破坏**（只碰演练库）

```powershell
docker exec easy-mysql mysql -uroot -peasy123 -t --default-character-set=utf8mb4 easy_mysql_restore -e "DROP TABLE orders; DELETE FROM users WHERE id <= 100; SELECT (SELECT COUNT(*) FROM users) AS users, (SELECT COUNT(*) FROM order_items) AS order_items;"
```

```text
+-------+-------------+
| users | order_items |
+-------+-------------+
|  4900 |      600000 |
+-------+-------------+
```

`orders` 表没了，`users` 少了 100 行 —— 和真实的事故现场一个样。

**第五步：再恢复一次**

```powershell
Measure-Command { docker exec easy-mysql mysql -uroot -peasy123 --default-character-set=utf8mb4 easy_mysql_restore -e "source /tmp/easy_mysql_tables.sql" } | Select-Object TotalSeconds
docker exec easy-mysql mysql -uroot -peasy123 -t --default-character-set=utf8mb4 easy_mysql_restore -e "SELECT (SELECT COUNT(*) FROM students) AS students, (SELECT COUNT(*) FROM users) AS users, (SELECT COUNT(*) FROM orders) AS orders, (SELECT COUNT(*) FROM order_items) AS order_items;"
```

```text
TotalSeconds
------------
  52.7913969
+----------+-------+--------+-------------+
| students | users | orders | order_items |
+----------+-------+--------+-------------+
|      200 |  5000 | 200000 |      600000 |
+----------+-------+--------+-------------+
```

`DROP TABLE` 是 DDL，事务回滚救不回来，**唯一能救它的就是这份文件**。

**第六步：收尾**

```powershell
docker exec easy-mysql mysql -uroot -peasy123 -t -e "DROP DATABASE easy_mysql_restore; SHOW DATABASES;"
```

```text
+--------------------+
| Database           |
+--------------------+
| easy_mysql         |
| information_schema |
| mysql              |
| performance_schema |
| sys                |
+--------------------+
```

## 5. binlog：把数据恢复到某个时间点

全量备份只解决「回到昨天」，**昨天下午三点之后写进去的数据它管不了**。这就要靠 binlog —— MySQL 会把改过数据的语句按顺序记进一组文件。

本环境已经开着：

```powershell
docker exec easy-mysql mysql -uroot -peasy123 -t -e "SHOW VARIABLES WHERE Variable_name IN ('log_bin', 'binlog_format');"
```

```text
+---------------+-------+
| Variable_name | Value |
+---------------+-------+
| binlog_format | ROW   |
| log_bin       | ON    |
+---------------+-------+
```

```powershell
docker exec easy-mysql mysql -uroot -peasy123 -t -e "SHOW BINARY LOGS;"
```

```text
+---------------+-----------+-----------+
| Log_name      | File_size | Encrypted |
+---------------+-----------+-----------+
| binlog.000001 |       180 | No        |
| binlog.000002 |  41165054 | No        |
| binlog.000003 |       180 | No        |
| binlog.000004 |  13995932 | No        |
| binlog.000005 | 164922154 | No        |
| binlog.000006 | 153896009 | No        |
+---------------+-----------+-----------+
```

> ⚠️ 文件号和大小会随时间变，**以你自己的 `SHOW BINARY LOGS` 末行为准**。末尾那个正在写的文件躺在 `lab/.data/`（`docker-compose.yml` 把数据目录挂载出来了）：

```powershell
Get-ChildItem lab\.data\binlog.0* | Sort-Object Name | Select-Object -Last 1 -ExpandProperty Name
```

```text
binlog.000006
```

读 binlog 要用 `mysqlbinlog`，**它不在容器里**（镜像装的是 `mysql-community-server-minimal`，不带这个工具）：

```powershell
docker exec easy-mysql sh -c "command -v mysqlbinlog || echo 'mysqlbinlog: not found'"
(Get-Command mysqlbinlog).Source
```

```text
mysqlbinlog: not found
C:\tools\mysql\mysql-8.0.27-winx64\bin\mysqlbinlog.exe
```

所以用**本机**的 `mysqlbinlog` 去读挂载出来的文件（本机装过 MySQL 就有；没装的话先按 `lab/README.md` 的 Windows 免安装版装一份）。下面完整走一遍「回到误删前」。

**① 造数据 + 备份这张表**（演练库，不碰本体）：

```powershell
docker exec easy-mysql mysql -uroot -peasy123 -e "CREATE DATABASE IF NOT EXISTS easy_mysql_restore CHARACTER SET utf8mb4;"
docker exec easy-mysql mysql -uroot -peasy123 -t --default-character-set=utf8mb4 easy_mysql_restore -e "CREATE TABLE binlog_drill (id INT UNSIGNED NOT NULL AUTO_INCREMENT, note VARCHAR(40) NOT NULL, PRIMARY KEY (id)) ENGINE=InnoDB; INSERT INTO binlog_drill (note) VALUES ('row-before-backup-1'),('row-before-backup-2'),('row-before-backup-3'); SELECT id, note FROM binlog_drill;"
```

```text
+----+---------------------+
| id | note                |
+----+---------------------+
|  1 | row-before-backup-1 |
|  2 | row-before-backup-2 |
|  3 | row-before-backup-3 |
+----+---------------------+
```

```powershell
docker exec easy-mysql mysqldump -uroot -peasy123 --single-transaction easy_mysql_restore binlog_drill --result-file=/tmp/binlog_drill_backup.sql
```

**② 记下时间点 T_start，写进 3 行新数据，再记下 T_stop**（`SLEEP` 是为了让三个时间点落在不同的一秒里，binlog 的时间精度是秒）：

```powershell
docker exec easy-mysql mysql -uroot -peasy123 -t --default-character-set=utf8mb4 easy_mysql_restore -e "SELECT SLEEP(1.5); SELECT NOW() AS T_start; SELECT SLEEP(1.5); INSERT INTO binlog_drill (note) VALUES ('row-after-backup-1'),('row-after-backup-2'),('row-after-backup-3'); SELECT SLEEP(1.5); SELECT NOW() AS T_stop; SELECT SLEEP(1.5); DROP TABLE binlog_drill;"
```

```text
+------------+
| SLEEP(1.5) |
+------------+
|          0 |
+------------+
+---------------------+
| T_start             |
+---------------------+
| 2026-10-09 10:21:37 |
+---------------------+
+------------+
| SLEEP(1.5) |
+------------+
|          0 |
+------------+
+------------+
| SLEEP(1.5) |
+------------+
|          0 |
+------------+
+---------------------+
| T_stop              |
+---------------------+
| 2026-10-09 10:21:40 |
+---------------------+
+------------+
| SLEEP(1.5) |
+------------+
|          0 |
+------------+
```

> ⚠️ **这两个时间戳是我这次跑出来的，你跑的时候换成你自己的。** 表在 T_stop 之后被 `DROP TABLE` 删掉了 —— 这就是「误删时刻」。

**③ 用时间窗口把这段 binlog 读出来**（`$binlog` 用你上面查到的文件名）：

```powershell
$binlog = "lab\.data\binlog.000006"
cmd /c "mysqlbinlog -v --base64-output=DECODE-ROWS --start-datetime=""2026-10-09 10:21:37"" --stop-datetime=""2026-10-09 10:21:40"" $binlog > $env:TEMP\pitr-read.sql"
Get-Content "$env:TEMP\pitr-read.sql" | Select-String "INSERT INTO|### SET|@1=|@2=|original_commit_timestamp=1791512498689911 \("
```

```text
# original_commit_timestamp=1791512498689911 (2026-10-09 10:21:38.689911 中国标准时间)
### INSERT INTO `easy_mysql_restore`.`binlog_drill`
### SET
###   @1=4
###   @2='row-after-backup-1'
### INSERT INTO `easy_mysql_restore`.`binlog_drill`
### SET
###   @1=5
###   @2='row-after-backup-2'
### INSERT INTO `easy_mysql_restore`.`binlog_drill`
### SET
###   @1=6
###   @2='row-after-backup-3'
```

**窗口之外的事一件都没进来**：备份前的 3 行在 T_start 之前，`DROP TABLE` 在 T_stop 之后。`@1=4` 起步，说明这是**备份之后**新写进去的 3 行。`cmd /c` 是为了用 cmd 的重定向写文件 —— cmd 是字节原样落盘，不碰编码。

> 这行的时区名按本地代码页写进文件（我这里是 GBK），`Get-Content` 默认按 ANSI 读，控制台保持默认编码即可正常显示；被别的程序按 UTF-8 读走才会乱码，SQL 本身不受影响。

**④ 恢复：先全量，再把窗口里的增量灌回去**

```powershell
cmd /c "mysqlbinlog --start-datetime=""2026-10-09 10:21:37"" --stop-datetime=""2026-10-09 10:21:40"" $binlog > $env:TEMP\pitr.sql"
docker cp "$env:TEMP\pitr.sql" easy-mysql:/tmp/pitr.sql
docker exec easy-mysql mysql -uroot -peasy123 -t --default-character-set=utf8mb4 easy_mysql_restore -e "source /tmp/binlog_drill_backup.sql; SELECT COUNT(*) AS 恢复备份后 FROM binlog_drill; source /tmp/pitr.sql; SELECT id, note FROM binlog_drill;"
```

```text
+-----------------+
| 恢复备份后      |
+-----------------+
|               3 |
+-----------------+
+----+---------------------+
| id | note                |
+----+---------------------+
|  1 | row-before-backup-1 |
|  2 | row-before-backup-2 |
|  3 | row-before-backup-3 |
|  4 | row-after-backup-1  |
|  5 | row-after-backup-2  |
|  6 | row-after-backup-3  |
+----+---------------------+
```

**这就是「恢复到某个时间点」的全部原理**：全量备份定一个起点，binlog 从起点重放到你指定的时刻。真实事故里，`--stop-datetime` 填的就是你**发现误操作的那一刻**，晚一分钟，那条 `DELETE` 就也进来了。

**⑤ 收尾**：

```powershell
docker exec easy-mysql mysql -uroot -peasy123 -e "DROP DATABASE easy_mysql_restore;"
Remove-Item "$env:TEMP\pitr.sql", "$env:TEMP\pitr-read.sql"
```

## 6. 定时备份：每天凌晨 3 点

### Windows：计划任务

把下面这段存成 `backup.ps1`（**用英文注释**：Windows PowerShell 5.1 按系统 ANSI 编码读 `.ps1`，你存成无 BOM 的 UTF-8，中文注释会直接把脚本读成语法错误）：

```powershell
# backup.ps1 - mysqldump the whole database every night at 03:00
$ErrorActionPreference = "Stop"
$ts   = Get-Date -Format yyyyMMdd-HHmm
$dump = "easy_mysql-$ts.sql"
$dest = "E:\mysql-backup"                 # 改成你自己的备份目录

New-Item -ItemType Directory -Force $dest | Out-Null

# 1. dump inside the container: --result-file avoids PowerShell's ">" redirection
docker exec easy-mysql mysqldump -uroot -peasy123 --single-transaction --databases easy_mysql --result-file="/tmp/$dump"
if ($LASTEXITCODE -ne 0) { throw "mysqldump failed, backup aborted" }

# 2. copy it out, then remove the temp file inside the container
docker cp "easy-mysql:/tmp/$dump" "$dest\$dump"
docker exec easy-mysql rm "/tmp/$dump"

# 3. keep only the last 7 days
Get-ChildItem $dest -Filter "easy_mysql-*.sql" |
  Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } |
  Remove-Item

Write-Host "backup done: $dest\$dump"
```

**这份脚本我一模一样跑过**（`$dest` 指到临时目录），输出加 `Get-ChildItem` 清单：

```text
backup done: C:\Users\Windows\AppData\Local\Temp\opencode-backup\mysql-backup\easy_mysql-20261009-0955.sql

Name                           Length
----                           ------
easy_mysql-20261009-0955.sql 53885944
```

（文件名里的时间戳每次都不一样，你看到的肯定和我不同。）注册成计划任务：

```powershell
schtasks /create /tn "MySQL Backup" /tr "powershell -NoProfile -ExecutionPolicy Bypass -File E:\mysql-backup\backup.ps1" /sc daily /st 03:00
```

> ⚠️ **`schtasks` 这条我没有在你机器上执行** —— 我不会替你注册计划任务。脚本本体实测通过，注册命令按 Windows 官方语法给出，你自己决定要不要跑；跑之前先手动执行一次 `backup.ps1`。

### Linux：cron

```bash
#!/bin/bash
# mysql-backup.sh - run every day at 03:00 by cron
set -euo pipefail

TS=$(date +%Y%m%d-%H%M)
DEST=${DEST:-/var/backups/mysql}
DUMP="easy_mysql-$TS.sql"

mkdir -p "$DEST"

# 1. dump inside the container, --result-file avoids shell redirection
docker exec easy-mysql mysqldump -uroot -peasy123 --single-transaction --databases easy_mysql --result-file="/tmp/$DUMP"

# 2. copy it out, then remove the temp file inside the container
docker cp "easy-mysql:/tmp/$DUMP" "$DEST/$DUMP"
docker exec easy-mysql rm "/tmp/$DUMP"

# 3. keep only the last 7 days
find "$DEST" -name 'easy_mysql-*.sql' -mtime +7 -delete

echo "backup done: $DEST/$DUMP"
```

```cron
0 3 * * * /usr/local/bin/mysql-backup.sh >> /var/log/mysql-backup.log 2>&1
```

**脚本本体同样实测过**（本机 Git Bash 里跑，`DEST` 指向临时目录），输出加 `ls -l` 打的清单：

```text
backup done: C:/Users/Windows/AppData/Local/Temp/opencode-backup/nix-backup/easy_mysql-20261009-0955.sql
total 52624
-rw-r--r-- 1 Windows 197121 53885944 Oct  9 09:55 easy_mysql-20261009-0955.sql
```

> ⚠️ cron 那一行**没有在本机跑过**（Windows 上没有 cron），按标准 cron 语法给出。在 Git Bash 里试跑这份脚本时有两处 Windows 特有的别扭：`MSYS` 会把 `/tmp/...` 参数改写成 Windows 路径 —— 忘了 `export MSYS_NO_PATHCONV=1` 的话，容器里的 mysqldump 会拿着一个 Windows 路径去找目录：
>
> ```text
> mysqldump: Can't create/write to file 'C:/Users/Windows/AppData/Local/Temp/easy_mysql-20261009-0956.sql' (OS errno 2 - No such file or directory)
> ```
>
> 而 `docker cp` 又只认 Windows 路径，所以 `DEST` 得写成 `C:/Users/...` 这种形式。真 Linux 上两件事都没这回事。

## 7. 没验证过的备份等于没有备份

上面 49 秒的恢复演练，才是这篇真正的交付物。很多人备份做了三年，**一次都没恢复过** —— 备份文件损坏、路径写错、中文乱码、磁盘早满，这些问题全在出事那天才暴露。

三条纪律：

1. **备份完当场恢复一次**，数行数对上才算数（第 4 节的六步）
2. **恢复到别的库去验证**，别拿本体试手
3. **留最近 7 天的文件**，并确保它们在另一块磁盘上（备份和数据同盘 = 硬盘一坏一起走）

## 三个必须记住的结论

1. **先想清楚你要哪种备份**：中小库用 `mysqldump --single-transaction`，大库上物理备份，要「回到某个时间点」必须配 binlog
2. **PowerShell 里备份/恢复别碰 `>` 和 `Get-Content` 管道**：前者存成 UTF-16，后者按 GBK 转码，两条路都会把中文 SQL 搞坏 —— 用 `--result-file` + `docker cp` + `source`
3. **没验证过的备份等于没有备份**：每次备份完，恢复到演练库数一遍行数

## 常见错误

### ❌ 错误做法 1：用 PowerShell 的 `>` 接备份文件

```powershell
docker exec easy-mysql mysqldump -uroot -peasy123 --single-transaction easy_mysql students > "$env:TEMP\bad-redirect.sql"
[System.BitConverter]::ToString([System.IO.File]::ReadAllBytes("$env:TEMP\bad-redirect.sql")[0..15])
```

```text
FF-FE-2D-00-2D-00-20-00-4D-00-79-00-53-00-51-00
```

**为什么错**：开头的 `FF-FE` 是 UTF-16 的 BOM —— Windows PowerShell 5.1 的 `>` 默认按 UTF-16 存，文件里全是 `00` 空字节。这份文件喂给 mysql：

```powershell
docker cp "$env:TEMP\bad-redirect.sql" easy-mysql:/tmp/bad-redirect.sql
docker exec easy-mysql mysql -uroot -peasy123 --default-character-set=utf8mb4 -e "source /tmp/bad-redirect.sql"
```

```text
ERROR: ASCII '\0' appeared in the statement, but this is not allowed unless option --binary-mode is enabled and mysql is run in non-interactive mode. Set --binary-mode to 1 if ASCII '\0' is expected. Query: '??-'.
```

（结尾那截乱码是被转码的 SQL 内容本身。）

**正确做法**：让 mysqldump 自己写文件，别经手 shell —— 第 2 节的 `--result-file` + `docker cp`。

### ❌ 错误做法 2：用 `Get-Content` 管道恢复

先把 `students` 的表结构 dump 成 `$env:TEMP\students_only.sql`，并建一个空的目标库：

```powershell
docker exec easy-mysql mysql -uroot -peasy123 -e "CREATE DATABASE IF NOT EXISTS mojibake_demo CHARACTER SET utf8mb4;"
docker exec easy-mysql mysqldump -uroot -peasy123 --no-data easy_mysql students --result-file=/tmp/students_only.sql
docker cp easy-mysql:/tmp/students_only.sql "$env:TEMP\students_only.sql"
```

然后照错误的做法走一遍（`Get-Content` 没有指定 `-Encoding UTF8`）：

```powershell
Get-Content "$env:TEMP\students_only.sql" | docker exec -i easy-mysql mysql -uroot -peasy123 --default-character-set=utf8mb4 mojibake_demo
```

```text
ERROR 1064 (42000) at line 25: You have an error in your SQL syntax; check the manual that corresponds to your MySQL server version for the right syntax to use near '??) NOT NULL DEFAULT '?? COMMENT '???',
  `class_name` varchar(30) NOT NULL COMM' at line 4
```

**为什么错**：`Get-Content` 没有指定 `-Encoding UTF8`，PowerShell 5.1 按系统 ANSI 编码（中文 Windows 是 GBK）去读这份 UTF-8 文件，中文全变成 `??` 之后才交给 mysql。表根本没建出来：

```powershell
docker exec easy-mysql mysql -uroot -peasy123 -t --default-character-set=utf8mb4 mojibake_demo -e "SELECT COUNT(*) AS 建出来的表数 FROM information_schema.TABLES WHERE TABLE_SCHEMA = 'mojibake_demo';"
```

```text
+--------------------+
| 建出来的表数       |
+--------------------+
|                  0 |
+--------------------+
```

**正确做法**：`docker cp` 把文件送进容器，再用 `source` 执行，全程字节原样传递。演示库和临时文件跑完删干净：

```powershell
docker exec easy-mysql mysql -uroot -peasy123 -e "DROP DATABASE mojibake_demo;"
Remove-Item "$env:TEMP\students_only.sql"
```

### ❌ 错误做法 3：恢复时目标库还没建

```powershell
docker exec easy-mysql mysql -uroot -peasy123 easy_mysql_restore_missing -e "source /tmp/easy_mysql_tables.sql"
```

```text
ERROR 1049 (42000): Unknown database 'easy_mysql_restore_missing'
```

**为什么错**：不带 `--databases` 的备份文件里没有建库语句，mysql 客户端连不上一个不存在的库。

**正确做法**：恢复前先 `CREATE DATABASE xxx CHARACTER SET utf8mb4;`（第 4 节第一步），或者干脆用带 `--databases` 的备份。

## 动手练

- [ ] 完整走一遍「备份 → 删 → 恢复」，把你每一步的行数记进自己的笔记
- [ ] 把 `users` 表的备份单独恢复到一个新库 `easy_mysql_restore` 里（提示：`mysqldump easy_mysql users`）

<details>
<summary>第二题的答案</summary>

```powershell
docker exec easy-mysql mysqldump -uroot -peasy123 --single-transaction easy_mysql users --result-file=/tmp/users_only.sql
docker exec easy-mysql mysql -uroot -peasy123 -e "CREATE DATABASE IF NOT EXISTS easy_mysql_restore CHARACTER SET utf8mb4;"
docker cp easy-mysql:/tmp/users_only.sql "$env:TEMP\users_only.sql"
docker exec easy-mysql mysql -uroot -peasy123 --default-character-set=utf8mb4 easy_mysql_restore -e "source /tmp/users_only.sql"
docker exec easy-mysql rm /tmp/users_only.sql
docker exec easy-mysql mysql -uroot -peasy123 -t easy_mysql_restore -e "SELECT COUNT(*) FROM users; DROP DATABASE easy_mysql_restore;"
```

脚本末尾的 `DROP DATABASE` 别忘 —— 演练完要把演练库删干净。
</details>

## 配套实验

```powershell
docker cp lab/queries/21-demo-backup.sql easy-mysql:/tmp/
docker exec easy-mysql mysql -uroot -peasy123 -t -e "source /tmp/21-demo-backup.sql"
```

> 实验里建的演练库 `easy_mysql_restore` 跑完会自动删掉，不会影响后面的文章。

## 下一篇

[22 · 权限与安全：别用 root 写代码](22-permission-security.md)
