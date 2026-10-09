# lab · 实验环境操作手册

这里是整个仓库的**地基**。教程里所有的表和数据都靠这份环境跑起来。

```
lab/
├── docker-compose.yml   # MySQL 8.0 + Adminer 图形界面
├── init/
│   ├── 01-schema.sql    # 建 8 张表
│   └── 02-data.sql      # 造 80 万行数据（约 20 秒）
├── queries/             # 每篇教程一个配套实验文件
├── verify-queries.ps1   # 一键检查所有实验文件还能不能跑
└── .data/               # 数据库数据文件（已 gitignore，别提交）
```

---

## 方案一：Docker（推荐，一条命令）

### 启动

```powershell
cd lab
docker compose up -d
```

第一次会拉取镜像，等 1~2 分钟。之后每次启动只要几秒。

看到 `easy-mysql Healthy` 就成功了。

### 连上数据库

**方式 A：图形界面（新手推荐）**

浏览器打开 <http://localhost:8080>，填：

| 输入框 | 填什么 |
|---|---|
| 系统 | MySQL |
| 服务器 | `easy-mysql` |
| 用户名 | `root` |
| 密码 | `easy123` |
| 数据库 | `easy_mysql`（可选） |

**方式 B：命令行**

```powershell
docker exec -it easy-mysql mysql -uroot -peasy123 -t
```

进去后试一句：

```sql
SELECT VERSION();
SELECT COUNT(*) FROM students;   -- 应该返回 200
```

### 停止

```powershell
docker compose stop      # 停止，数据保留
docker compose down      # 删容器，数据保留
docker compose down -v   # ★ 连数据一起删（重置用这个）
```

### 数据存在哪

在 `lab/.data/` 目录（已在 `.gitignore` 里）。删掉它就等于重置数据库。

---

## 方案二：不用 Docker 的两条路

### Windows 免安装版

1. 官网下载 <https://dev.mysql.com/downloads/mysql/> 选 **MySQL Community Server - ZIP Archive**
2. 解压到 `C:\mysql`，目录里直接有 `bin` 文件夹
3. 创建配置文件 `C:\mysql\my.ini`：

   ```ini
   [mysqld]
   basedir=C:/mysql
   datadir=C:/mysql/data
   port=3306
   character-set-server=utf8mb4
   [client]
   default-character-set=utf8mb4
   ```

4. 管理员身份打开 PowerShell，初始化并启动：

   ```powershell
   cd C:\mysql\bin
   .\mysqld.exe --initialize-insecure
   .\mysqld.exe --console
   ```

5. 另开一个窗口连进去：

   ```powershell
   cd C:\mysql\bin
   .\mysql.exe -uroot -p --default-character-set=utf8mb4
   ```

6. 然后手动执行 `init/01-schema.sql` 和 `init/02-data.sql` 两个文件

> ⚠️ 免安装版不会自动跑 init 脚本，得自己把文件导入客户端执行。

### 在线沙盒（只想看，不想装）

用官方的 <https://playground.mysql.com/> 或 <https://onecompiler.com/mysql>。

> ⚠️ 沙盒不能造 20 万行数据，所以第 13 篇之后的实验需要自己造数据：
> 打开仓库的 `lab/init/02-data.sql`，把最后的自检语句换成
> `SELECT COUNT(*) FROM orders;` 逐段跑，或者先只跑到 5000 行的小数据集。

---

## 重置数据库

改了 `init/` 里的文件之后，脚本**不会自动重跑**（Docker 的 init 脚本只在数据目录为空时执行一次）。重置方法：

```powershell
cd lab
docker compose down -v
# Windows 下 .data 有时会残留，删掉
if (Test-Path .data) { Remove-Item -Recurse -Force .data }
docker compose up -d
```

等 30 秒左右（造数据要 20 秒），然后验证：

```sql
SELECT 'students' AS t, COUNT(*) AS n FROM students
UNION ALL SELECT 'orders', COUNT(*) FROM orders
UNION ALL SELECT 'order_items', COUNT(*) FROM order_items;
-- 期望：200 / 200000 / 600000
```

---

## 检查实验文件还能不能跑

改了任何 SQL 之后跑一遍：

```powershell
powershell -ExecutionPolicy Bypass -File lab/verify-queries.ps1
```

期望输出最后一行是 `错误总数 4（4 条为预期内的演示用错误）`。这 4 条是**故意写错的语句**，分别在：

| 文件 | 行 | 演示什么 |
|---|---|---|
| `10-demo-types.sql` | 183 | 字符串金额转 DECIMAL 失败 |
| `11-demo-constraints.sql` | 158 | 超出范围的分数被拦截 |
| `18-demo-transaction.sql` | 119 | 错误语句（`balanc` 拼错）导致事务回滚 |
| `23-demo-errors.sql` | 32 | 报错速查篇：`==` 语法错误示范（文件靠 `--force` 跑完） |

只要错误数还是 4，就说明没引入新问题。超过 4 说明你改坏了什么。

---

## 备份与恢复（第 21 篇的内容，先自己练一遍）

> 这里的命令和 [docs/21-backup-restore.md](../docs/21-backup-restore.md) 一致，都是本机实测过的。
> **两个不要碰**：PowerShell 的 `>` 会把文件存成 UTF-16、`Get-Content` 管道会按 GBK 转码，
> 两条路都会把中文 SQL 搞坏 —— 一律用 `--result-file` 让 mysqldump 自己写文件，再 `docker cp` 出来。

### 备份

```powershell
# 全部数据（--result-file 在容器内写文件，完全不经 shell 重定向）
docker exec easy-mysql mysqldump -uroot -peasy123 --single-transaction --databases easy_mysql --result-file=/tmp/easy_mysql_full.sql
docker cp easy-mysql:/tmp/easy_mysql_full.sql "$env:TEMP\easy_mysql_full.sql"

# 只备份表结构
docker exec easy-mysql mysqldump -uroot -peasy123 --no-data easy_mysql --result-file=/tmp/schema.sql

# 只备份某一张表的数据
docker exec easy-mysql mysqldump -uroot -peasy123 --no-create-info easy_mysql orders --result-file=/tmp/orders.sql
```

### 恢复

把 dump 文件送进容器，用 `source` 执行 —— 全程字节原样传递：

```powershell
docker cp "$env:TEMP\easy_mysql_full.sql" easy-mysql:/tmp/
docker exec easy-mysql mysql -uroot -peasy123 --default-character-set=utf8mb4 -e "source /tmp/easy_mysql_full.sql"
```

> ⚠️ 恢复演练**别对 `easy_mysql` 本体做**，建个 `easy_mysql_restore` 演练库，练完 `DROP DATABASE easy_mysql_restore`。
> 完整的「备份 → 删 → 恢复 → 校验行数」演练见第 21 篇第 4 节。

### 定时备份（Windows 计划任务）

```powershell
# backup.ps1 —— 同样走 --result-file，不碰 `>`
docker exec easy-mysql mysqldump -uroot -peasy123 --single-transaction --databases easy_mysql --result-file=/tmp/backup.sql
docker cp easy-mysql:/tmp/backup.sql "E:\backup\mysql-$(Get-Date -Format yyyyMMdd-HHmm).sql"
```

```powershell
schtasks /create /tn "MySQL Backup" /tr "powershell -File E:\backup\backup.ps1" /sc daily /st 03:00
```

### 用 binlog 恢复到某个时间点

本环境已开启 binlog（`--log-bin=binlog`），文件挂在 `lab\.data\` 下。注意 **`mysqlbinlog` 不在容器里**，用本机装的那份（免安装版见上文）：

```powershell
docker exec easy-mysql mysql -uroot -peasy123 -e "SHOW BINARY LOGS;"   # 先看有哪些文件
$binlog = "lab\.data\binlog.000003"
cmd /c "mysqlbinlog --start-datetime=""2026-10-09 10:21:37"" --stop-datetime=""2026-10-09 10:21:40"" $binlog > $env:TEMP\pitr.sql"
```

时间窗口换成你自己的事故时间；完整的「回到误删前」演练见第 21 篇第 6 节。

---

## 常用排查

| 现象 | 原因 | 解决 |
|---|---|---|
| `failed to connect to the docker API` | Docker Desktop 没启动 | 启动 Docker Desktop |
| `Image mysql:8.0 Pulling` 卡住 | 网络拉不动镜像 | 见下方「国内网络」 |
| `dependency failed to start: container easy-mysql is unhealthy` | init 脚本报错 | `docker logs easy-mysql` 看最后 20 行 |
| 首次启动很慢（1~2 分钟） | 正在造 80 万行数据 | 正常，等 `docker compose logs -f mysql` 出现 `ready for connections` |
| 查出来的中文是乱码 | 客户端字符集不对 | 连接时加 `--default-character-set=utf8mb4` |
| `lower_case_table_names=2` 警告 | Windows 文件系统不区分大小写 | 无害，忽略 |

### 国内网络：拉不动镜像

```powershell
# 配一个镜像源，然后重新拉取
docker pull docker.m.daocloud.io/library/mysql:8.0
docker tag  docker.m.daocloud.io/library/mysql:8.0 mysql:8.0

docker pull docker.m.daocloud.io/library/adminer:4
docker tag  docker.m.daocloud.io/library/adminer:4 adminer:4

docker compose up -d
```

打完 tag 之后 `docker-compose.yml` 一个字都不用改。

### 看日志

```powershell
docker logs easy-mysql --tail 50        # 启动过程
docker exec easy-mysql ls /var/lib/mysql/   # 有没有 binlog / 慢日志
```

---

## init 脚本里的一个重要细节

`init/01-schema.sql` 第 11 行是 `SET NAMES utf8mb4;`，**千万别删**。

MySQL 官方镜像的 entrypoint 调用 `mysql` 客户端时**没有带** `--default-character-set`
（见 `/usr/local/bin/docker-entrypoint.sh` 第 258 行），客户端会退回 latin1。
结果就是脚本里的中文被当成 latin1 再转成 utf8mb4，存进去是**双重编码的乱码**：

```
'男'  →  3 个字符，HEX = C3A5C2A5C2B3
```

连 `ENUM('男','女')` 的定义本身都会变坏，导致后面插入正常的中文时报
`ERROR 1265: Data truncated for column 'gender'`。

`SET NAMES utf8mb4;` 相当于告诉客户端「这个文件里的字节是 utf8mb4」。
这个坑很隐蔽，值得单独写一篇，候选标题：**《我在 Docker 里造数据，中文全变成了乱码》**。
