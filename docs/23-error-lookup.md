# 23 · 常见报错速查表：报错不用慌，翻表查

> **一句话价值**：拿到任何一条 MySQL 报错，三段拆开、按码翻表，两分钟知道谁错了、改哪一行。

**难度**：⭐　|　**时长**：约 20 分钟　|　**涉及表**：全部

## 什么时候你会遇到它

脚本跑到一半，屏幕糊上一层 `ERROR 1064 (42000) at line 1`。你把这句复制进搜索框，翻三页全是英文博客，人家报的错和你的上下文对不上 —— 二十分钟过去了，SQL 还停在原地。

其实这条报错把自己拆开就是三段，三段分别告诉你**谁报的、错在哪一行、错在哪个词**。

## 本篇你会学到

- [ ] 一条报错的三段结构，以及怎么用 `at line N` 找回脚本里那一行
- [ ] 一张 18 行的速查表，**每行都是本机跑出来的原话**
- [ ] 错误码分段不用背，一条 SQL 现场核对
- [ ] 从报错关键词反查错误码
- [ ] 想看更多线索时的三个入口
- [ ] `1064` 最容易踩的两个坑

---

## 1. 拆一条报错：三段读法

配套实验文件故意写错了 11 处，用下面这条命令一次跑出来（`--force` 让客户端出错后接着跑；标准输入重定向这条路才吃 `--force`，`source` 不吃，文末有对照。`2>&1` 是把 stderr 并进 stdout，否则报错和查询结果会各走各的缓冲，交错顺序乱跳）：

```powershell
docker cp lab/queries/23-demo-errors.sql easy-mysql:/tmp/
docker exec easy-mysql sh -c "mysql -uroot -peasy123 --force --default-character-set=utf8mb4 easy_mysql < /tmp/23-demo-errors.sql 2>&1"
```

```text
id	code	name	note	grade
1	1	a	x	good
ERROR 1064 (42000) at line 32: You have an error in your SQL syntax; check the manual that corresponds to your MySQL server version for the right syntax to use near '== 1' at line 1
ERROR 1054 (42S22) at line 35: Unknown column 'nam' in 'field list'
ERROR 1146 (42S02) at line 38: Table 'easy_mysql.order_detail' doesn't exist
ERROR 1049 (42000) at line 41: Unknown database 'no_such_database'
ERROR 1062 (23000) at line 44: Duplicate entry '1' for key 'err_probe.uk_code'
ERROR 1048 (23000) at line 47: Column 'code' cannot be null
ERROR 1366 (HY000) at line 50: Incorrect integer value: 'abc' for column 'code' at row 1
ERROR 1264 (22003) at line 53: Out of range value for column 'code' at row 1
ERROR 1406 (22001) at line 56: Data too long for column 'name' at row 1
ERROR 1265 (01000) at line 59: Data truncated for column 'grade' at row 1
ERROR 1452 (23000) at line 62: Cannot add or update a child row: a foreign key constraint fails (`easy_mysql`.`scores`, CONSTRAINT `fk_scores_student` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`))
报错之后还剩几行
1
students行数	scores行数
200	2000
收尾
临时表已清理
```

（第一行 `mysql: [Warning] Using a password ...` 是 stderr 的密码警告，下同，不再贴。）

拿第一行拆成三段：

| 段 | 内容 | 说什么 |
|---|---|---|
| ① 错误码 | `ERROR 1064` | 拿去翻表的钥匙，1064 = 语法错误 |
| ② SQLSTATE | `(42000)` | 标准五位分类码，`42` 开头都是「语法或权限」类，驱动程序用它做分支判断 |
| ③ 位置 | `at line 32` + `near '== 1'` | 你提交的第 32 行，出错片段是 `== 1` |

`at line N` 数的是**你这次交进去的文本**的行号：`-e` 里的语句永远是 line 1，跑文件数的就是文件行号。把那一行捞出来看：

```powershell
docker exec easy-mysql sh -c "sed -n '32p' /tmp/23-demo-errors.sql"
```

```text
SELECT * FROM err_probe WHERE code == 1;
```

一眼看到 `==`：SQL 里比较相等写 `=`，`==` 是 C 系语言的习惯。

> `mysql` 客户端的三种跑法我都试了（`-e` 单句、`source` 跑文件、标准输入喂文件），打出来的都是干巴巴的一句 `ERROR 1064 ...`，**谁也不会在出错字符下面画 `^` 箭头** —— 那是 gcc、Python 的待遇。MySQL 只给你 `at line N` 和 `near '...'` 两样，所以才需要上面那条 `sed -n '32p'` 把原文捞出来自己看。

## 2. 速查表（本篇主要交付物）

表里 18 行原话，全部是这台机器上跑出来的：

| 错误（原话照抄） | 常见原因 | 怎么修 |
|---|---|---|
| `ERROR 2003 (HY000): Can't connect to MySQL server on '127.0.0.1:3399' (111)` | 服务没起，或端口写错 | `docker ps` 看端口映射；2003 是**客户端**报的，压根没连上 |
| `ERROR 1045 (28000): Access denied for user 'root'@'localhost' (using password: YES)` | 密码错，或 `@host` 对不上（第 22 篇第 4 节） | 核对密码；再看报错里的 host 是不是你的落点 |
| `ERROR 1044 (42000) at line 1: Access denied for user 'ro_demo'@'%' to database 'mysql'` | 账号对这个库没权限 | 换有权限的库，或 `GRANT` 该库的权限 |
| `ERROR 1142 (42000) at line 1: DELETE command denied to user 'ro_demo'@'localhost' for table 'users'` | 库在表在，缺这一项操作权限 | 权限不够，找授账号的人 |
| `ERROR 1049 (42000) at line 41: Unknown database 'no_such_database'` | 库名拼错，或库还没建 | `SHOW DATABASES;` 对一遍 |
| `ERROR 1054 (42S22) at line 35: Unknown column 'nam' in 'field list'` | 列名拼错 | `DESC 表名;` 逐字对 |
| `ERROR 1146 (42S02) at line 38: Table 'easy_mysql.order_detail' doesn't exist` | 表名拼错，或连错库 | `SHOW TABLES;`；注意报错里带了当前库名 |
| `ERROR 1064 (42000) at line 32: You have an error in your SQL syntax; check the manual that corresponds to your MySQL server version for the right syntax to use near '== 1' at line 1` | 语法错：多符号、少引号、关键字拼错 | 看 `near` 片段 + 第 6 节两个坑 |
| `ERROR 1062 (23000) at line 44: Duplicate entry '1' for key 'err_probe.uk_code'` | 撞唯一键 | 换一个值，或先查再插 |
| `ERROR 1048 (23000) at line 47: Column 'code' cannot be null` | `NOT NULL` 的列插了 `NULL` | 给它一个值，或改列定义 |
| `ERROR 1366 (HY000) at line 50: Incorrect integer value: 'abc' for column 'code' at row 1` | 类型不匹配，严格模式直接拒 | 改传入的值，或改列类型 |
| `ERROR 1366 (HY000) at line 1: Incorrect string value: '\xFF' for column 'c' at row 1` | 塞进来的内容编码不合法（这字节 utf8mb4 表示不了） | 查数据来源的编码 |
| `ERROR 1264 (22003) at line 53: Out of range value for column 'code' at row 1` | 数值超出字段范围（`TINYINT UNSIGNED` 最大 255） | 扩列类型，或修数据 |
| `ERROR 1406 (22001) at line 56: Data too long for column 'name' at row 1` | 字符串超过列宽 | 加大 `VARCHAR` 或改 `TEXT` |
| `ERROR 1265 (01000) at line 59: Data truncated for column 'grade' at row 1` | 值不在 `ENUM` 列表里 | 核对枚举值 |

锁相关的两条在第 20 篇实测过，原话一并放进来：

| 错误（原话照抄） | 常见原因 | 怎么修 |
|---|---|---|
| `ERROR 1205 (HY000) at line 6: Lock wait timeout exceeded; try restarting transaction` | 等别人的锁超时了（默认 50 秒） | 自己 `ROLLBACK`，再看谁攥着锁 |
| `ERROR 1213 (40001) at line 5: Deadlock found when trying to get lock; try restarting transaction` | 两个事务互相等，被 InnoDB 挑一个回滚 | 重试事务 + 统一加锁顺序 |

外键那条也别漏（实验第 11 处错误）：

| 错误（原话照抄） | 常见原因 | 怎么修 |
|---|---|---|
| ``ERROR 1452 (23000) at line 62: Cannot add or update a child row: a foreign key constraint fails (`easy_mysql`.`scores`, CONSTRAINT `fk_scores_student` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`))`` | 子表要写入的父行不存在 | 先把父行插进去，或修外键值 |

## 3. 错误码分段：一条 SQL 自己核对

分段不用背，服务器自己就有全量名单。下面这条可以直接粘进 Adminer 或 mysql client：

```sql
SELECT ERROR_NUMBER DIV 1000 AS seg, COUNT(*) AS cnt,
       MIN(ERROR_NUMBER) AS lo, MAX(ERROR_NUMBER) AS hi
FROM performance_schema.events_errors_summary_global_by_error
GROUP BY ERROR_NUMBER DIV 1000
ORDER BY seg;
```

命令行里这样跑：

```powershell
docker exec easy-mysql mysql -uroot -peasy123 -t -e "SELECT ERROR_NUMBER DIV 1000 AS seg, COUNT(*) AS cnt, MIN(ERROR_NUMBER) AS lo, MAX(ERROR_NUMBER) AS hi FROM performance_schema.events_errors_summary_global_by_error GROUP BY ERROR_NUMBER DIV 1000 ORDER BY seg;"
```

```text
+------+-----+-------+-------+
| seg  | cnt | lo    | hi    |
+------+-----+-------+-------+
| NULL |   1 |  NULL |  NULL |
|    1 | 780 |  1004 |  1887 |
|    3 | 696 |  3000 |  3999 |
|    4 | 165 |  4000 |  4168 |
|   10 | 793 | 10000 | 10999 |
|   11 | 934 | 11000 | 11999 |
|   12 | 935 | 12000 | 12998 |
|   13 | 932 | 13000 | 13999 |
|   14 |  94 | 14000 | 14094 |
+------+-----+-------+-------+
```

照这张实测图分段：

| 段 | 这套 MySQL 8.0.46 里的条数 | 装的是什么 | 例子 |
|---|---|---|---|
| 1000–1999 | 780 | SQL、权限、表、约束的**服务端**老错误，日常九成报错在这里 | 1064、1045、1146、1205 |
| 2000–2999 | **0** | 服务端一条都没有 —— 这一段是 **mysql 客户端自己编的**，全是「连不上」 | 2003、2013 |
| 3000–3999 | 696 | MySQL 8.0 新加的服务端错误（文件、触发器、外键深度） | 3000 `ER_FILE_CORRUPT` |
| 4000–4168 | 165 | 错误日志、审计这类运维向错误 | 4001 `ER_DA_NO_ERROR_LOG_PARSER_CONFIGURED` |
| 10000–14094 | 3688 | 内部与引擎消息：10000 段解析器/启动，12000–13000 段 InnoDB（`ER_IB_MSG_*`），14000 段复制与审计 | 13000 `ER_IB_MSG_UNDO_TRUNCATE_COMPLETE` |

**看到 2003 别去服务端日志里找**：它压根没走到服务器；看到 `12xxx` 也别慌，多半是 InnoDB 吐的内部消息，不一定是你的 SQL 有毛病。

## 4. 反查：从关键词找错误码

只记得英文单词、不记得码时，照这张表对：

| 报错里的关键词 | 错误码 |
|---|---|
| `Unknown column` | `1054` |
| `doesn't exist`（主语是表） | `1146` |
| `Unknown database` | `1049` |
| `You have an error in your SQL syntax` | `1064` |
| `Access denied` | `1045`（密码/host）、`1044`（库） |
| `command denied to user` | `1142` |
| `Duplicate entry` | `1062` |
| `cannot be null` | `1048` |
| `Incorrect integer value` / `Incorrect string value` | `1366` |
| `Out of range value` | `1264` |
| `Data too long for column` | `1406` |
| `Data truncated for column` | `1265` |
| `foreign key constraint fails` | `1452` |
| `Lock wait timeout exceeded` | `1205` |
| `Deadlock found` | `1213` |

## 5. 想看更多：三个入口

**入口一：`SHOW WARNINGS`** —— 只看报错会漏掉「不报错但改了你的数据」的情况。下面这条在非严格模式下插一个超长字符串，语句成功，警告留下来了：

```powershell
docker exec easy-mysql mysql -uroot -peasy123 -t easy_mysql -e "SET sql_mode=''; CREATE TEMPORARY TABLE wprobe (c VARCHAR(3) NOT NULL); INSERT INTO wprobe VALUES ('abcdef'); SHOW WARNINGS; DROP TEMPORARY TABLE wprobe;"
```

```text
+---------+------+----------------------------------------+
| Level   | Code | Message                                |
+---------+------+----------------------------------------+
| Warning | 1265 | Data truncated for column 'c' at row 1 |
+---------+------+----------------------------------------+
```

**入口二：`SHOW ENGINE INNODB STATUS\G`** —— 锁、死锁、事务看这个（报告只留最近一次，出事抓紧取）。我这台机器上刚用第 20 篇第 5 节的办法重新触发了一次死锁（容器重启过，报告是空的），原话：

```powershell
docker exec easy-mysql mysql -uroot -peasy123 -e "SHOW ENGINE INNODB STATUS\G"
```

```text
LATEST DETECTED DEADLOCK
------------------------
2026-10-09 10:08:00 134842600732224
*** (1) TRANSACTION:
TRANSACTION 27507, ACTIVE 3 sec starting index read
mysql tables in use 1, locked 1
LOCK WAIT 3 lock struct(s), heap size 1128, 2 row lock(s)
MySQL thread id 361, OS thread handle 134842919372352, query id 2354 localhost root updating
UPDATE users SET balance = balance WHERE id = 2

*** (1) HOLDS THE LOCK(S):
RECORD LOCKS space id 5 page no 6 n bits 264 index PRIMARY of table `easy_mysql`.`users` trx id 27507 lock_mode X locks rec but not gap
Record lock, heap no 2 PHYSICAL RECORD: n_fields 10; compact format; info bits 0
 0: len 8; hex 0000000000000001; asc         ;;
```

（只截了开头这一段，完整的报告里还有 `*** (2) TRANSACTION`、「在等谁的锁」和收尾的 `*** WE ROLL BACK TRANSACTION (2)` —— 被牺牲的是 2 号窗口，第 20 篇第 5 节逐行讲过。）

**入口三：服务端日志** —— 客户端断线、启动参数、复制问题，话是服务器自己说的，得去日志里听：

```powershell
docker logs easy-mysql --tail 5
```

```text
2026-10-09T01:46:21.093981Z 0 [Warning] [MY-011810] [Server] Insecure configuration for --pid-file: Location '/var/run/mysqld' in the path is accessible to all OS users. Consider choosing a different directory.
2026-10-09T01:46:21.144432Z 0 [System] [MY-011323] [Server] X Plugin ready for connections. Bind-address: '::' port: 33060, socket: /var/run/mysqld/mysqlx.sock
2026-10-09T01:46:21.144675Z 0 [System] [MY-010931] [Server] /usr/sbin/mysqld: ready for connections. Version: '8.0.46'  socket: '/var/run/mysqld/mysqld.sock'  port: 3306  MySQL Community Server - GPL.
2026-10-09T02:00:28.690534Z 230 [Warning] [MY-013360] [Server] Plugin sha256_password reported: ''sha256_password' is deprecated and will be removed in a future release. Please use caching_sha2_password instead'
2026-10-09T02:01:49.967040Z 266 [Warning] [MY-013360] [Server] Plugin sha256_password reported: ''sha256_password' is deprecated and will be removed in a future release. Please use caching_sha2_password instead'
```

日志行自带时间戳和 `MY-xxxx` 编号，报障时把编号一起贴出去，比只贴一句「连不上」有用得多。前三行是容器今天启动时留下的 —— 服务几点起的、版本多少、监听哪个口，日志自己会说。**日志随时在追加，你跑出来的内容和我不会一样**，认格式就行。

## 6. 关于 1064 的两个误区

**误区一：`at line 32` 是表里的第 32 行。**
它是**你这次提交的文本**的行号。`-e` 单句跑永远是 `at line 1`，跑文件才数文件行号 —— 所以第 1 节的 `sed -n '32p'` 才能把那一行捞出来。`near '...'` 只给出来错点附近的一小段，不是完整语句；MySQL 服务端报错也不带 `^`，两样凑起来就是它的全部定位信息。

**误区二：1064 一定是你把 SQL 打错了。**
编码也会制造 1064。第 21 篇「错误做法 2」那条 `near '??'` 的 1064，原因是 `Get-Content` 按 GBK 读了 UTF-8 的备份文件，中文全变 `??` 才交给 mysql —— SQL 本身一个字都没敲错。命令行里带中文列名是同一件事的另一个入口：

```powershell
docker exec easy-mysql mysql -uroot -peasy123 -t -e "SELECT 1 AS 恢复备份后;"
```

回的是 `ERROR 1064 (42000)`，`near` 后面半截是转坏的字节 —— 转坏成什么样取决于你控制台的编码，各人看到的乱码都不一样，所以不贴原文。原因问服务器自己：

```powershell
docker exec easy-mysql mysql -uroot -peasy123 -t -e "SHOW VARIABLES LIKE 'character_set_client';"
```

```text
+----------------------+--------+
| Variable_name        | Value  |
+----------------------+--------+
| character_set_client | latin1 |
+----------------------+--------+
```

这趟连接客户端自报的字符集是 `latin1`，它按 latin1 校验你发来的字节，中文必然过不了关。加 `--default-character-set=utf8mb4` 再跑同一条命令：

```powershell
docker exec easy-mysql mysql -uroot -peasy123 -t --default-character-set=utf8mb4 -e "SELECT 1 AS 恢复备份后;"
```

```text
+-----------------+
| 恢复备份后      |
+-----------------+
|               1 |
+-----------------+
```

**所以看到 1064 的顺序是**：先看 `near` 里有没有 `??` 或不认识的字节（编码问题），再用 `sed -n 'Np'` 捞出那一行看语法，都对完了再去搜。

## 三个必须记住的结论

1. **报错三段读**：`ERROR 码`（查表） + `(SQLSTATE)`（给驱动看的） + `at line N / near '...'`（`sed -n 'Np'` 捞原文）
2. **分段背不下来就现场查**：`performance_schema.events_errors_summary_global_by_error` 一条 SQL 给出全部段位，2000 段是客户端专用
3. **`SHOW WARNINGS` 看暗坑，`SHOW ENGINE INNODB STATUS` 看锁，`docker logs` 听服务器自己说话**

## 常见错误

### 错误一：`doesn't exist` 先分清主语是表还是库

`ERROR 1146` 的主语是**表**，`ERROR 1049` 的主语是**库**，两个都叫「不存在」，但含义不同——库名可以拼错，表名也可以拼错，还有第三种：你连错了库。触发一遍看事实：

```powershell
docker exec easy-mysql mysql -uroot -peasy123 -t -e "USE easy_mysql; SELECT * FROM order_detail;"
```

```text
ERROR 1146 (42S02) at line 1: Table 'easy_mysql.order_detail' doesn't exist
```

报错里带了当前库名 `easy_mysql`，顺手核对一遍：

```powershell
docker exec easy-mysql mysql -uroot -peasy123 -t -e "USE easy_mysql; SHOW TABLES; SELECT COUNT(*) FROM students WHERE id = 999999;"
```

```text
+----------------------+
| Tables_in_easy_mysql |
+----------------------+
| bad_design_demo      |
| courses              |
| order_items          |
| orders               |
| orders_slow          |
| scores               |
| students             |
| users                |
+----------------------+
+----------+
| COUNT(*) |
+----------+
|        0 |
+----------+
```

八张表里没有 `order_detail`——它是文档 16 里被 `order_items` 取代的旧名字，打错了就该报 1146；而 `COUNT(*)` 返回 0 是合法结果，不是报错。**「查不到」和「报错」是两件事**：前者给你空结果集，后者在 stderr 上甩一行 `ERROR`。

### 错误二：`foreign key constraint fails` 要分清「父行不在」和「子行还在」

同样是 `1452`，方向相反的两种事故都用它。第一种：要写入的引用目标不存在——

```powershell
docker exec easy-mysql mysql -uroot -peasy123 -t -e "USE easy_mysql; INSERT INTO scores (student_id, course_id, score, exam_date) VALUES (999999, 1, 88.00, '2026-01-01');"
```

```text
ERROR 1452 (23000) at line 1: Cannot add or update a child row: a foreign key constraint fails (`easy_mysql`.`scores`, CONSTRAINT `fk_scores_student` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`))
```

报错把**约束名、子表、父表、父列**全写清楚了：`students` 里没有 999999 号学生，`scores` 就插不进这一行。父行查证：

```powershell
docker exec easy-mysql mysql -uroot -peasy123 -t --default-character-set=utf8mb4 -e "USE easy_mysql; SELECT COUNT(*) AS 父行数 FROM students WHERE id = 999999; SELECT COUNT(*) AS scores行数 FROM scores;"
```

```text
+-----------+
| 父行数    |
+-----------+
|         0 |
+-----------+
+--------------+
| scores行数   |
+--------------+
|         2000 |
+--------------+
```

第二种方向是删除父行时才现身：`scores` 里还挂着这个学生的行，`students` 就删不动，同样是这条 1452，但话要反着听——**「子行还在」**。处理顺序永远是先清子行（或先改子行的外键值），再动父行。

## 动手练

- [ ] 故意触发上表里 5 种报错，把原话抄进你的错误笔记
- [ ] 每次报错先别搜，先读懂错误码

<details>
<summary>5 种报错的触发方式</summary>

```powershell
docker cp lab/queries/23-demo-errors.sql easy-mysql:/tmp/
docker exec easy-mysql sh -c "mysql -uroot -peasy123 --force --default-character-set=utf8mb4 easy_mysql < /tmp/23-demo-errors.sql"
```

这份文件里有 11 条，挑前 5 条抄：`1064`（第 32 行 `==`）、`1054`（第 35 行列名 `nam`）、`1146`（第 38 行表名）、`1049`（第 41 行库名）、`1062`（第 44 行唯一键）。

</details>

## 配套实验

```powershell
docker cp lab/queries/23-demo-errors.sql easy-mysql:/tmp/
docker exec easy-mysql mysql -uroot -peasy123 -t -e "source /tmp/23-demo-errors.sql"
```

> 同一个文件换 `source` 跑，**只出 1 条报错就停**：
>
> ```text
> ERROR 1064 (42000) at line 32 in file: '/tmp/23-demo-errors.sql': You have an error in your SQL syntax; check the manual that corresponds to your MySQL server version for the right syntax to use near '== 1' at line 1
> ```
>
> `--force` 管不到 `source` 这条客户端内部命令，只有标准输入（第 1 节那条 `<`）才会把 11 条全放出来。实验表用 `CREATE TEMPORARY TABLE` 建，会话一关自动消失，`easy_mysql` 里不会留下任何东西。

## 下一篇

[附录 A1 · 常用 SQL 速查表](A1-sql-cheatsheet.md)
