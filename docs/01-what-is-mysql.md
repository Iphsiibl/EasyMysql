# 01 · MySQL 是什么：从零把它跑起来

> **一句话价值**：在自己电脑上把 MySQL 跑起来，用客户端连上它，并且确认连的确实是它。

**难度**：⭐　|　**时长**：约 20 分钟　|　**涉及表**：无

## 什么时候你会遇到它

你写了第一个网页作业，页面能跑，一点「保存」就报错；或者你拿别人给的数据库脚本去导，满屏红色英文。这些事的起点是同一件事：你的程序要读写数据库，而你电脑上压根没有跑起来的数据库。

## 本篇你会学到

- [ ] 数据库和 MySQL 到底什么关系，为什么不拿 Excel 凑合
- [ ] 为什么必须先有一个「服务器程序」，客户端才有活干
- [ ] 用 Docker 一行命令把 MySQL 跑起来
- [ ] host、port、user、password 四个连接参数各管什么
- [ ] 连上之后，怎么确认连的是它

---

## 正文

### 1. 数据库不是 Excel，它是一个一直醒着的进程

Excel 文件躺在硬盘上，谁打开谁改，两个人同时改，后保存的那个把先保存的覆盖掉。而且程序想改其中一行，得把整个文件读进来、改完、再整个写回去。**这就是「文件型」的死法。**

MySQL 的做法是：让一个程序常驻在内存里，替所有人管着硬盘上那堆文件。这个程序叫**服务器（server）**，进程名 `mysqld`。你手里的 `mysql` 命令行、图形界面 Navicat、网页版 Adminer，统统叫**客户端（client）**，它们只会做一件事：把你说的话送给服务器，再把服务器的回答带回来。

服务器是一直醒着的，它知道现在有谁连着自己。跑一遍这个实验，先在窗口 A 执行：

```sql
SELECT SLEEP(10);
```

这条会卡住 10 秒不返回。趁它卡着，在窗口 B（另开一个终端，连的是同一个服务器）执行：

```sql
SELECT Id, User, Host, db, Command, Time, State, Info
FROM information_schema.PROCESSLIST
WHERE Info LIKE 'SELECT SLEEP%';
```

```text
+------+------+-----------+------------+---------+------+------------+------------------+
| Id   | User | Host      | db         | Command | Time | State      | Info             |
+------+------+-----------+------------+---------+------+------------+------------------+
| 2677 | root | localhost | easy_mysql | Query   |    2 | User sleep | SELECT SLEEP(10) |
+------+------+-----------+------------+---------+------+------------+------------------+
```

逐列读一遍：`Id` 是连接编号，`Command` 为 `Query` 表示这条语句正在执行，`Time` 是它已经跑了 2 秒，`State` 里的 `User sleep` 是你那句 `SLEEP(10)` 造成的等待（不是连接闲着），`Info` 就是正在执行的语句原文。

**这行不是你窗口 B 查出来的，是窗口 A 正在跑的那条。** 服务器手里同时攥着两个客户端：一个让它挂着，另一个照样秒回。你换成 Adminer 网页点一下查询，拿到的还是同一份数据。Excel 给不了你这个，所以数据库必须是客户端-服务器（client-server）结构。

> ⚠️ 你的 `Id`、`Time` 肯定和我不一样，这不重要。重要的是你能看到**另一条连接**。

### 2. 一行命令把它跑起来

这个仓库的 `lab/` 已经把配置写好了，你只要执行：

```powershell
cd lab
docker compose up -d
```

```text
 Container easy-mysql Running 
 Container easy-mysql-adminer Running 
 Container easy-mysql Waiting 
 Container easy-mysql Healthy 
```

我这台机器上容器早就建好了，所以显示 `Running`；你第一次跑会看到 `Pulled`、`Created`、`Started`，跑完同样停在 `Healthy` —— 那是 `docker-compose.yml` 里的健康检查（每 5 秒 `mysqladmin ping` 一次）通过了。

确认它真的活着：

```powershell
docker ps
```

```text
CONTAINER ID   IMAGE       COMMAND                  CREATED        STATUS                 PORTS                                         NAMES
63cfcab4c3db   mysql:8.0   "docker-entrypoint.s…"   5 hours ago    Up 3 hours (healthy)   0.0.0.0:3307->3306/tcp, [::]:3307->3306/tcp   easy-mysql
b9ff335a1641   adminer:4   "entrypoint.sh docke…"   15 hours ago   Up 3 hours             0.0.0.0:8080->8080/tcp, [::]:8080->8080/tcp   easy-mysql-adminer
```

`STATUS` 那个 `(healthy)` 是好信号；`PORTS` 里的 `3307->3306` 是第 4 节的主角，先记住它。第二个容器 Adminer 是图形界面，浏览器打开 <http://localhost:8080> 就能点着查，具体填什么见 [lab/README.md](../lab/README.md) 的「连上数据库」。

现在用命令行连进去（`-it` 是开一个能打字的交互窗口，`-t` 让结果画成表格）：

```powershell
docker exec -it easy-mysql mysql -uroot -peasy123 -t
```

```text
mysql: [Warning] Using a password on the command line interface can be insecure.
Welcome to the MySQL monitor.  Commands end with ; or \g.
Your MySQL connection id is 2591
Server version: 8.0.46 MySQL Community Server - GPL

Copyright (c) 2000, 2026, Oracle and/or its affiliates.

Oracle is a registered trademark of Oracle Corporation and/or its
affiliates. Other names may be trademarks of their respective
owners.

Type 'help;' or '\h' for help. Type '\c' to clear the current input statement.

mysql> 
```

看到 `mysql>` 就进去了。横幅里的 `connection id` 每次都不同，`Server version: 8.0.46` 是服务器报的版本。敲 `exit` 退出。

> 📌 我抓这段横幅时用的是 `docker exec -t ...`（少了 `-i`），因为我这边的终端不是真 TTY；`-i` 只负责把你的键盘接进去，横幅内容一字不差。

### 3. 不想装 Docker：两条路

**路线一：Windows 免安装版。** 官网下 ZIP 包解压到 `C:\mysql`，写个 `my.ini`，跑一次 `mysqld --initialize-insecure`，再手动执行 `lab/init/` 里那两个建表造数的脚本。能用，但没人替你管初始化和环境变量，出问题全靠自己查。步骤照 [lab/README.md](../lab/README.md) 的「方案二」抄即可，这里不复述。

**路线二：在线沙盒。** <https://playground.mysql.com/> 或 <https://onecompiler.com/mysql>，打开就能敲，一行不装。代价有两个：一关页面数据就没了；沙盒给不了你 20 万行的 `orders` 表，所以从第 13 篇（索引）开始的实验你只能看，跑不了。

**我的建议**：装 Docker。本仓库所有输出都是照着 Docker 这套环境抓的，你用同一套环境，才能和我看到一模一样的结果。

### 4. 四个连接参数，逐个说清楚

任何客户端连 MySQL 都要回答四个问题，缺一不可：

| 参数 | 本仓库的值 | 回答什么问题 |
|---|---|---|
| `host` | `127.0.0.1`（宿主机上连）/ `easy-mysql`（容器网络里连） | 服务器在哪台机器上 |
| `port` | `3307`（宿主机上连）/ `3306`（容器网络里连） | 它在哪个端口等你 |
| `user` | `root` | 你是谁 |
| `password` | `easy123` | 凭证，对不上就不放行 |

前两个合起来叫**地址**，后两个合起来叫**身份**。地址错了根本连不上，身份错了服务器会把你顶回来 —— 后者的真实报错原文在文末「常见错误」。

端口这里最容易绕晕，先看服务器自己怎么说：

```sql
SELECT @@port, @@hostname;
```

```text
+--------+--------------+
| @@port | @@hostname   |
+--------+--------------+
|   3306 | 63cfcab4c3db |
+--------+--------------+
```

它说自己在 `3306`，机器名 `63cfcab4c3db` 正是 `docker ps` 里那台容器的 ID。**`3306` 是服务器自己站的门，`3307` 是宿主机上给它开的门**，中间那道转发写在 `docker-compose.yml` 的 `ports: - "3307:3306"` 里。所以在容器外面（你自己的 PowerShell、Navicat）必须填 `3307`，而在容器网络里的 Adminer 填 `easy-mysql` 就走 `3306`。至于 `docker exec` 那条命令 —— 你人已经进容器了，直接就是 `localhost:3306`，所以它连 host、port 都不用写。

在你的电脑上验证 3307 这扇门真的开着（PowerShell 自带命令）：

```powershell
Test-NetConnection -ComputerName 127.0.0.1 -Port 3307 | Select-Object ComputerName, RemotePort, TcpTestSucceeded | Format-List
```

```text
ComputerName     : 127.0.0.1
RemotePort       : 3307
TcpTestSucceeded : True
```

如果你宿主机上装了 `mysql` 客户端，还能从外面实打实连一次，看清楚「我敲的是 3307，对面报的是 3306」（没有 `mysql` 命令就跳过这段，用 Adminer 连效果一样）：

```powershell
mysql -h 127.0.0.1 -P 3307 -uroot -peasy123 --default-character-set=utf8mb4 -t -e "SELECT VERSION() AS version, @@hostname AS host, @@port AS server_port;"
```

```text
+---------+--------------+-------------+
| version | host         | server_port |
+---------+--------------+-------------+
| 8.0.46  | 63cfcab4c3db |        3306 |
+---------+--------------+-------------+
```

`-h` 对应 host，`-P` 对应 port（大写，小写 `-p` 是密码），`-u` 对应 user，密码跟在 `-p` 后面且**中间不能有空格**。

### 5. 验证：连的到底是不是它

连上以后第一句永远是它：

```sql
SELECT VERSION();
```

```text
+-----------+
| VERSION() |
+-----------+
| 8.0.46    |
+-----------+
```

能返回版本号，说明 host、port、user、password 四个参数全对，网络是通的，对面也确实是 MySQL。这句也是配套实验文件的第一句，完整跑下来你会看到服务器的版本、库里有哪些库、端口、字符集、SQL 严格程度、支持哪些存储引擎，以及 `students` 的 200 行数据：

```powershell
docker cp lab/queries/01-demo-connect.sql easy-mysql:/tmp/
docker exec easy-mysql mysql -uroot -peasy123 -t --default-character-set=utf8mb4 easy_mysql -e "source /tmp/01-demo-connect.sql"
```

```text
+---------+
| version |
+---------+
| 8.0.46  |
+---------+
+--------------------+
| Database           |
+--------------------+
| easy_mysql         |
| information_schema |
| mysql              |
| performance_schema |
| sys                |
+--------------------+
+------+----------------+--------------------+
| port | charset_server | collation_server   |
+------+----------------+--------------------+
| 3306 | utf8mb4        | utf8mb4_0900_ai_ci |
+------+----------------+--------------------+
+-----------------------------------------------------------------------------------------------------------------------+
| sql_mode                                                                                                              |
+-----------------------------------------------------------------------------------------------------------------------+
| ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION |
+-----------------------------------------------------------------------------------------------------------------------+
+--------------------+---------+----------------------------------------------------------------+--------------+------+------------+
| Engine             | Support | Comment                                                        | Transactions | XA   | Savepoints |
+--------------------+---------+----------------------------------------------------------------+--------------+------+------------+
| ndbcluster         | NO      | Clustered, fault-tolerant tables                               | NULL         | NULL | NULL       |
| MEMORY             | YES     | Hash based, stored in memory, useful for temporary tables      | NO           | NO   | NO         |
| InnoDB             | DEFAULT | Supports transactions, row-level locking, and foreign keys     | YES          | YES  | YES        |
| PERFORMANCE_SCHEMA | YES     | Performance Schema                                             | NO           | NO   | NO         |
| MyISAM             | YES     | MyISAM storage engine                                          | NO           | NO   | NO         |
| FEDERATED          | NO      | Federated MySQL storage engine                                 | NULL         | NULL | NULL       |
| ndbinfo            | NO      | MySQL Cluster system information storage engine                | NULL         | NULL | NULL       |
| MRG_MYISAM         | YES     | Collection of identical MyISAM tables                          | NO           | NO   | NO         |
| BLACKHOLE          | YES     | /dev/null storage engine (anything you write to it disappears) | NO           | NO   | NO         |
| CSV                | YES     | CSV storage engine                                             | NO           | NO   | NO         |
| ARCHIVE            | YES     | Archive storage engine                                         | NO           | NO   | NO         |
+--------------------+---------+----------------------------------------------------------------+--------------+------+------------+
+---------------+
| students_rows |
+---------------+
|           200 |
+---------------+
```

逐个说清这几个值：`Database` 那栏是我们后面 23 篇的全部舞台 `easy_mysql`（`information_schema`、`mysql`、`performance_schema`、`sys` 是服务器自带的管理库，别动它们）；`charset_server` 是 `utf8mb4`，中文和 emoji 都能存，第 2 篇会讲为什么不是 `utf8`；`sql_mode` 那串现在不用背，只要知道它是「服务器有多严格」的开关；`Engine` 里 `InnoDB` 标着 `DEFAULT`，它撑起了后面所有的事务和索引实验；末尾那句 `200` 说明数据真的造好了。

> 📌 `Database`、`Engine` 两栏的顺序在不同机器上可能不同；你那边要是还装过别的库，`Database` 会比这份长。重点只看两个：`easy_mysql` 在，`students_rows` 是 `200`。

## 三个必须记住的结论

1. **MySQL = 常驻的服务器进程 + 一堆数据文件**。你敲命令的地方永远是客户端，服务器在容器里一直醒着，谁连都用同一份数据
2. **连接就是四个参数**：`host` + `port` 找到机器和那扇门，`user` + `password` 证明你是谁；容器内的 3306 和宿主机上的 3307 是同一台服务器的两扇门
3. **连上先敲 `SELECT VERSION()`**，能返回版本号，四个参数才算全对

## 常见错误

### ❌ 密码写错了

```powershell
docker exec easy-mysql mysql -uroot -peasy_wrong -t -e "SELECT VERSION();"
```

```text
ERROR 1045 (28000): Access denied for user 'root'@'localhost' (using password: YES)
```

**为什么错**：`(using password: YES)` 的意思是「你给我密码了，但不对」。注意 `root@` 后面跟的是**客户端所在的位置**（在容器里连就是 `localhost`），不是你的 Windows 用户名。

**顺带认识另一行**：每次执行命令，你都会看到 `mysql: [Warning] Using a password on the command line interface can be insecure.` —— 这不是报错，是客户端在提醒「密码明文写在命令行里不安全」，**忽略它**，只要下面没有 `ERROR` 就是成功的。

**正确做法**：密码就是 `easy123`，而且 `-p` 和密码之间**不能有空格** —— `-p` 后面空一格，密码就没带上，后面那个 `easy123` 反而被当成了库名：

```powershell
docker exec easy-mysql mysql -uroot -p easy123 -t -e "SELECT VERSION();"
```

```text
Enter password: ERROR 1045 (28000): Access denied for user 'root'@'localhost' (using password: NO)
```

和上面那条对照着看：`using password: YES` 是「密码给了，但不对」，这条 `NO` 是「压根没给」。写成 `-peasy123`，两段紧挨着，才是对的。

## 动手练

- [ ] 用三种方式各连一次数据库（`docker exec` 命令行、浏览器里的 Adminer、宿主机的 `mysql -h 127.0.0.1 -P 3307`），说出它们各自的优势在哪
- [ ] 把 `docker compose down` 和 `docker compose down -v` 各执行一次，观察数据还在不在，解释两者的区别（做完记得 `docker compose up -d` 恢复）

<details>
<summary>第二题的答案</summary>

`down` 删的是容器，`down -v` 额外删 Docker 管理的 volume。而这个仓库的数据文件放在 `lab/.data/`，它是**绑定到宿主机目录**的，所以两者跑完数据都还在，`students` 照样是 200 行。

想真正重置，得连 `lab/.data` 一起删，完整步骤见 [lab/README.md](../lab/README.md) 的「重置数据库」—— 那一节还提醒了 Windows 下 `.data` 常常删不干净。这也是「数据和程序分开存」的好处：容器随便删，数据不受牵连。
</details>

## 配套实验

```powershell
docker cp lab/queries/01-demo-connect.sql easy-mysql:/tmp/
docker exec easy-mysql mysql -uroot -peasy123 -t --default-character-set=utf8mb4 easy_mysql -e "source /tmp/01-demo-connect.sql"
```

> 全是 `SELECT` 和 `SHOW`，只读，跑几遍都不会改变任何东西。

## 下一篇

[02 · 数据库、表、行、列：先搞懂这四个词](02-db-table-row-column.md)
