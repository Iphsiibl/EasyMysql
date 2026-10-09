# 20 · 锁与死锁：并发下的秩序

> **一句话价值**：知道什么时候会锁表、为什么会死锁，以及两把万能钥匙。

**难度**：⭐⭐⭐⭐　|　**时长**：约 40 分钟　|　**涉及表**：`users`、`orders`、`scores`

## 什么时候你会遇到它

你的程序偶尔卡住不动，日志里全是 `Lock wait timeout exceeded`；或者你收到一条告警：`Deadlock found when trying to get lock`。

锁的账算不清，线上就会长出「莫名其妙的慢查询」和「隔几分钟一次的失败重试」。这篇把每次卡顿的现场都摆出来给你看：谁拿锁、谁在等、等多久、为什么等。

## 本篇你会学到

- [ ] 读锁 / 写锁，以及「写锁为什么互斥」
- [ ] 表锁 vs 行锁（**`UPDATE` 没加 `WHERE` 会锁全表**）
- [ ] 行锁的三种：记录锁、间隙锁、Next-Key Lock
- [ ] 死锁的四个必要条件
- [ ] **两把万能钥匙**：统一加锁顺序、缩短事务
- [ ] 怎么看锁：`SHOW ENGINE INNODB STATUS` / `performance_schema.data_locks`

---

## 1. 锁是什么：两个人抢同一把椅子

一把椅子只能坐一个人，先坐下的人不站起来，第二个就只能干等。数据库把这件事写成了制度：**锁（Lock）**就是「我先用着，用完还你」的占位牌。

MySQL 里两种最基础的锁：

- **读锁（Shared Lock，共享锁）**：好几个人可以同时拿，互相不挡
- **写锁（Exclusive Lock，排他锁）**：拿到的人独占，别人再想读想写都得排队

你马上会想到：那我平时满天飞的 `SELECT` 岂不是天天在排队？**一次都没有** —— 普通 `SELECT` 不加锁，它走 MVCC 读快照（第 19 篇的原话：读的人看自己事务开始时的那份数据）。真正伸手拿写锁的是 `UPDATE`、`DELETE`、`INSERT`，以及你显式写的 `SELECT ... FOR UPDATE`。

## 2. 写锁互斥：一次实测（本篇的地基）

开两个窗口。窗口 1 先动手，那句 `balance + 0` 是故意的：**数据一点都不改，只为把 1 号行的写锁攥在手里**：

```sql
-- 窗口 1
START TRANSACTION;
UPDATE users SET balance = balance + 0 WHERE id = 1;
SELECT NOW(6) AS 持有写锁起始时刻 FROM DUAL;
SELECT SLEEP(8);
ROLLBACK;
SELECT NOW(6) AS 已释放写锁时刻 FROM DUAL;
```

```sql
-- 窗口 2（在窗口 1 停住期间执行）
SELECT NOW(6) AS 普通读的时刻 FROM DUAL;
SELECT balance AS 普通读到 FROM users WHERE id = 1;
START TRANSACTION;
SELECT NOW(6) AS 开始抢写锁的时刻 FROM DUAL;
UPDATE users SET balance = balance + 1 WHERE id = 1;
SELECT NOW(6) AS 抢到写锁的时刻 FROM DUAL;
ROLLBACK;
SELECT balance AS 演示后余额 FROM users WHERE id = 1;
```

```text
+----------------------------+
| 持有写锁起始时刻           |
+----------------------------+
| 2026-10-08 14:05:59.106733 |
+----------------------------+
+----------+
| SLEEP(8) |
+----------+
|        0 |
+----------+
+----------------------------+
| 已释放写锁时刻             |
+----------------------------+
| 2026-10-08 14:06:07.108632 |
+----------------------------+
```

```text
+----------------------------+
| 普通读的时刻               |
+----------------------------+
| 2026-10-08 14:06:01.247355 |
+----------------------------+
+--------------+
| 普通读到     |
+--------------+
|      6201.78 |
+--------------+
+----------------------------+
| 开始抢写锁的时刻           |
+----------------------------+
| 2026-10-08 14:06:01.247835 |
+----------------------------+
+----------------------------+
| 抢到写锁的时刻             |
+----------------------------+
| 2026-10-08 14:06:07.109632 |
+----------------------------+
+-----------------+
| 演示后余额      |
+-----------------+
|         6201.78 |
+-----------------+
```

拆开看时间戳：窗口 2 的普通读在 `06:01.247` 返回 6201.78 —— 窗口 1 明明攥着写锁，**读一点没被挡**，快照读根本不排队。同一毫秒它转头去写，`UPDATE` 一直卡到 `06:07.109` 才返回，正好落在窗口 1 的持锁区间 `59.10 → 07.10` 里，**实打实等了 5.86 秒**。`ROLLBACK` 之后余额还是 6201.78，两边谁也没真改数据。

它卡住的时候，第三个窗口能看到完整的「谁在等谁」：

```sql
-- 窗口 3
SELECT ID, USER, HOST, DB, COMMAND, TIME, STATE, LEFT(INFO, 60) AS SQL片段
FROM information_schema.PROCESSLIST
WHERE DB = 'easy_mysql' AND COMMAND <> 'Sleep' ORDER BY ID;
SELECT * FROM performance_schema.data_lock_waits\G
SELECT OBJECT_SCHEMA, OBJECT_NAME, INDEX_NAME, LOCK_TYPE, LOCK_MODE, LOCK_STATUS, LOCK_DATA
FROM performance_schema.data_locks WHERE OBJECT_NAME = 'users';
```

```text
+------+------+-----------+------------+---------+------+------------+--------------------------------------------------------------+
| ID   | USER | HOST      | DB         | COMMAND | TIME | STATE      | SQL片段                                                      |
+------+------+-----------+------------+---------+------+------------+--------------------------------------------------------------+
| 3247 | root | localhost | easy_mysql | Query   |    4 | User sleep | SELECT SLEEP(8)                                              |
| 3249 | root | localhost | easy_mysql | Query   |    2 | updating   | UPDATE users SET balance = balance + 1 WHERE id = 1          |
| 3250 | root | localhost | easy_mysql | Query   |    0 | executing  | SELECT ID, USER, HOST, DB, COMMAND, TIME, STATE, LEFT(INFO,  |
+------+------+-----------+------------+---------+------+------------+--------------------------------------------------------------+
*************************** 1. row ***************************
                          ENGINE: INNODB
       REQUESTING_ENGINE_LOCK_ID: 131832380387328:6432:5:6:2:131832276377584
REQUESTING_ENGINE_TRANSACTION_ID: 24002
            REQUESTING_THREAD_ID: 3988
             REQUESTING_EVENT_ID: 11
REQUESTING_OBJECT_INSTANCE_BEGIN: 131832276377584
         BLOCKING_ENGINE_LOCK_ID: 131832380386520:30478:5:6:2:131832276371408
  BLOCKING_ENGINE_TRANSACTION_ID: 24001
              BLOCKING_THREAD_ID: 3986
               BLOCKING_EVENT_ID: 7
  BLOCKING_OBJECT_INSTANCE_BEGIN: 131832276371408
+---------------+-------------+------------+-----------+---------------+-------------+-----------+
| OBJECT_SCHEMA | OBJECT_NAME | INDEX_NAME | LOCK_TYPE | LOCK_MODE     | LOCK_STATUS | LOCK_DATA |
+---------------+-------------+------------+-----------+---------------+-------------+-----------+
| easy_mysql    | users       | NULL       | TABLE     | IX            | GRANTED     | NULL      |
| easy_mysql    | users       | NULL       | TABLE     | IX            | GRANTED     | NULL      |
| easy_mysql    | users       | PRIMARY    | RECORD    | X,REC_NOT_GAP | GRANTED     | 1         |
| easy_mysql    | users       | PRIMARY    | RECORD    | X,REC_NOT_GAP | WAITING     | 1         |
+---------------+-------------+------------+-----------+---------------+-------------+-----------+
```

三段各说一件事：

- **`PROCESSLIST`**：窗口 2 的 `STATE` 是 **`updating`**，`TIME = 2` —— 它在同一条 `UPDATE` 上已经站了 2 秒。排查线上卡顿，先看这一列
- **`data_lock_waits`**：事务 `24002` 在等事务 `24001`，**谁堵谁**直接写在两行数字里
- **`data_locks`**：同一个 id = 1 上躺着两行 `X,REC_NOT_GAP`，一行 `GRANTED`（窗口 1 已经拿到），一行 `WAITING`（窗口 2 在排队）

`X,REC_NOT_GAP` 就是**记录锁（Record Lock）**：只锁这一行本身，两边的空隙不管。记住这个字段名，第 4 节和第 5 节还会读到它。

## 3. UPDATE 忘了加 WHERE：一行的锁变成五千行

先看执行计划要扫多少行：

```sql
EXPLAIN UPDATE users SET balance = balance + 1;
EXPLAIN UPDATE users SET balance = balance + 1 WHERE id = 2;
```

```text
+----+-------------+-------+------------+-------+---------------+---------+---------+------+------+----------+-------+
| id | select_type | table | partitions | type  | possible_keys | key     | key_len | ref  | rows | filtered | Extra |
+----+-------------+-------+------------+-------+---------------+---------+---------+------+------+----------+-------+
|  1 | UPDATE      | users | NULL       | index | NULL          | PRIMARY | 8       | NULL | 5070 |   100.00 | NULL  |
+----+-------------+-------+------------+-------+---------------+---------+---------+------+------+----------+-------+
+----+-------------+-------+------------+-------+---------------+---------+---------+-------+------+----------+-------------+
| id | select_type | table | partitions | type  | possible_keys | key     | key_len | ref   | rows | filtered | Extra       |
+----+-------------+-------+------------+-------+---------------+---------+---------+-------+------+----------+-------------+
|  1 | UPDATE      | users | NULL       | range | PRIMARY       | PRIMARY | 8       | const |    1 |   100.00 | Using where |
+----+-------------+-------+------------+-------+---------------+---------+---------+-------+------+----------+-------------+
```

一个 `rows = 5070`，一个 `rows = 1`。InnoDB 没有真正的「表锁」，但全表扫描会把**扫到的每一行都锁上**，五千行全锁住，效果和锁表一模一样。实测：

```sql
-- 窗口 1
START TRANSACTION;
UPDATE users SET balance = balance + 1;      -- ★ 没有 WHERE
SELECT NOW(6) AS 持有全表写锁起始时刻 FROM DUAL;
SELECT SLEEP(6);
ROLLBACK;
SELECT NOW(6) AS 已释放时刻 FROM DUAL;
```

```sql
-- 窗口 2（在窗口 1 停住期间执行）
START TRANSACTION;
SELECT NOW(6) AS 开始抢id2的时刻 FROM DUAL;
UPDATE users SET balance = balance + 1 WHERE id = 2;
SELECT NOW(6) AS 抢到id2的时刻 FROM DUAL;
ROLLBACK;
SELECT balance AS 2号余额 FROM users WHERE id = 2;
```

```text
+--------------------------------+
| 持有全表写锁起始时刻           |
+--------------------------------+
| 2026-10-08 14:06:27.916318     |
+--------------------------------+
+----------+
| SLEEP(6) |
+----------+
|        0 |
+----------+
+----------------------------+
| 已释放时刻                 |
+----------------------------+
| 2026-10-08 14:06:33.979216 |
+----------------------------+
```

```text
+----------------------------+
| 开始抢id2的时刻            |
+----------------------------+
| 2026-10-08 14:06:30.033068 |
+----------------------------+
+----------------------------+
| 抢到id2的时刻              |
+----------------------------+
| 2026-10-08 14:06:33.931853 |
+----------------------------+
+------------+
| 2号余额    |
+------------+
|    5086.48 |
+------------+
```

窗口 2 改的是**另一行**（id = 2），照样从 `30.03` 一直堵到 `33.93`，将近 4 秒。你的「改一行」SQL，被别人的裸 `UPDATE` 拖死，锅在谁身上一目了然。

对照组 —— 窗口 1 加上 `WHERE id = 1`，窗口 2 照旧抢 id = 2，再来一遍：

```sql
-- 窗口 1
START TRANSACTION;
UPDATE users SET balance = balance + 1 WHERE id = 1;   -- 只锁一行
SELECT NOW(6) AS 对照_只锁1号起始时刻 FROM DUAL;
SELECT SLEEP(5);
ROLLBACK;
SELECT NOW(6) AS 对照_已释放时刻 FROM DUAL;
```

```sql
-- 窗口 2
START TRANSACTION;
SELECT NOW(6) AS 对照_开始抢id2的时刻 FROM DUAL;
UPDATE users SET balance = balance + 1 WHERE id = 2;
SELECT NOW(6) AS 对照_抢到id2的时刻 FROM DUAL;
ROLLBACK;
```

```text
+-------------------------------+
| 对照_只锁1号起始时刻          |
+-------------------------------+
| 2026-10-08 14:06:46.583467    |
+-------------------------------+
+----------+
| SLEEP(5) |
+----------+
|        0 |
+----------+
+----------------------------+
| 对照_已释放时刻            |
+----------------------------+
| 2026-10-08 14:06:51.592953 |
+----------------------------+
```

```text
+------------------------------+
| 对照_开始抢id2的时刻         |
+------------------------------+
| 2026-10-08 14:06:48.723018   |
+------------------------------+
+----------------------------+
| 对照_抢到id2的时刻         |
+----------------------------+
| 2026-10-08 14:06:48.723766 |
+----------------------------+
```

`48.723018 → 48.723766`，**0.0007 秒**，等于没等。锁的范围对了，别人就感知不到你。

## 4. 间隙锁：连「不存在的行」都锁住

建一张故意缺号的小表（缺 5）：

```sql
CREATE TABLE demo_gap (id INT PRIMARY KEY) ENGINE=InnoDB;
INSERT INTO demo_gap VALUES (1), (2), (3), (4), (6), (7);   -- 故意缺一个 5
SELECT id FROM demo_gap ORDER BY id;
```

```text
+----+
| id |
+----+
|  1 |
|  2 |
|  3 |
|  4 |
|  6 |
|  7 |
+----+
```

```sql
-- 窗口 1（默认 REPEATABLE READ）
START TRANSACTION;
SELECT id FROM demo_gap WHERE id BETWEEN 3 AND 6 FOR UPDATE;
SELECT NOW(6) AS 间隙锁持有起始时刻 FROM DUAL;
SELECT SLEEP(6);
ROLLBACK;
SELECT NOW(6) AS 间隙锁释放时刻 FROM DUAL;
```

```sql
-- 窗口 2（在窗口 1 停住期间执行）
SELECT NOW(6) AS 开始插入5的时刻 FROM DUAL;
INSERT INTO demo_gap VALUES (5);
SELECT NOW(6) AS 插入成功的时刻 FROM DUAL;
DELETE FROM demo_gap WHERE id = 5;
SELECT id AS 插入后又删掉的表内容 FROM demo_gap ORDER BY id;
```

```text
+----+
|  3 |
|  4 |
|  6 |
+----+
+-----------------------------+
| 间隙锁持有起始时刻          |
+-----------------------------+
| 2026-10-08 14:07:33.006617  |
+-----------------------------+
+----------+
| SLEEP(6) |
+----------+
|        0 |
+----------+
+----------------------------+
| 间隙锁释放时刻             |
+----------------------------+
| 2026-10-08 14:07:39.008641 |
+----------------------------+
```

```text
+----------------------------+
| 开始插入5的时刻            |
+----------------------------+
| 2026-10-08 14:07:35.150522 |
+----------------------------+
+----------------------------+
| 插入成功的时刻             |
+----------------------------+
| 2026-10-08 14:07:39.017798 |
+----------------------------+
+--------------------------------+
| 插入后又删掉的表内容           |
+--------------------------------+
|                              1 |
|                              2 |
|                              3 |
|                              4 |
|                              6 |
|                              7 |
+--------------------------------+
```

id = 5 那行**从来没存在过**，窗口 2 的 `INSERT` 还是从 `35.15` 堵到 `39.01`，等了 3.87 秒。锁不是锁在「行」上，而是锁在「行和行之间的空隙」上。它卡住时的锁清单：

```text
+---------------+-------------+------------+-----------+------------------------+-------------+-----------+
| OBJECT_SCHEMA | OBJECT_NAME | INDEX_NAME | LOCK_TYPE | LOCK_MODE              | LOCK_STATUS | LOCK_DATA |
+---------------+-------------+------------+-----------+------------------------+-------------+-----------+
| easy_mysql    | demo_gap    | NULL       | TABLE     | IX                     | GRANTED     | NULL      |
| easy_mysql    | demo_gap    | NULL       | TABLE     | IX                     | GRANTED     | NULL      |
| easy_mysql    | demo_gap    | PRIMARY    | RECORD    | X                      | GRANTED     | 4         |
| easy_mysql    | demo_gap    | PRIMARY    | RECORD    | X                      | GRANTED     | 6         |
| easy_mysql    | demo_gap    | PRIMARY    | RECORD    | X,REC_NOT_GAP          | GRANTED     | 3         |
| easy_mysql    | demo_gap    | PRIMARY    | RECORD    | X,GAP,INSERT_INTENTION | WAITING     | 6         |
+---------------+-------------+------------+-----------+------------------------+-------------+-----------+
+--------------------+-----------------+
| 等待中的事务       | 持锁的事务      |
+--------------------+-----------------+
|              24027 |           24026 |
+--------------------+-----------------+
```

三种锁一次性集齐：

- **记录锁**：`X,REC_NOT_GAP`，3 号行本身
- **Next-Key Lock**：`LOCK_MODE = X`（不带 `REC_NOT_GAP`）落在 4 和 6 上，**行 + 后面的空隙一起锁**
- **插入意向锁（Insert Intention Lock）**：`X,GAP,INSERT_INTENTION`，状态 `WAITING` —— 窗口 2 的插入排在这条空隙前面，进不来

这就是第 19 篇「RR 压住幻读」的实现细节：范围两端的空隙被 Next-Key Lock 封死，别人插不进新行，幻读自然出不来。

## 5. 手动造一个死锁（本篇高潮）

死锁的四个必要条件是教科书原话：**互斥、持有并等待、不可剥夺、循环等待**。前三个条件 InnoDB 自己已经定死了，你能动的只有第四个 —— 下面这段 SQL 亲手造出循环等待：

```sql
-- 窗口 1：先锁 1 号，睡 4 秒，再要 2 号
START TRANSACTION;
UPDATE users SET balance = balance - 1 WHERE id = 1;
SELECT SLEEP(4);
UPDATE users SET balance = balance - 1 WHERE id = 2;
SELECT NOW(6) AS 窗口1执行完的时刻 FROM DUAL;
ROLLBACK;
```

```sql
-- 窗口 2（在窗口 1 的 SLEEP 期间执行）：先锁 2 号，反手再要 1 号
START TRANSACTION;
UPDATE users SET balance = balance - 1 WHERE id = 2;
UPDATE users SET balance = balance - 1 WHERE id = 1;
SELECT NOW(6) AS 窗口2执行完的时刻 FROM DUAL;
ROLLBACK;
```

```text
+----------+
| SLEEP(4) |
+----------+
|        0 |
+----------+
ERROR 1213 (40001) at line 5: Deadlock found when trying to get lock; try restarting transaction
```

```text
+----------------------------+
| 窗口2执行完的时刻          |
+----------------------------+
| 2026-10-08 14:08:21.720298 |
+----------------------------+
+--------------+
| marker       |
+--------------+
| window2 done |
+--------------+
```

两边互相攥着对方要的东西：窗口 1 拿着 id = 1 在等 id = 2，窗口 2 拿着 id = 2 在等 id = 1。InnoDB 的死锁检测（`@@innodb_deadlock_detect = 1`）在毫秒级反应过来，挑一个事务强制回滚 —— 这次是窗口 1，`at line 5` 正是它那句要 id = 2 的 `UPDATE`。窗口 2 全须全尾地跑完了，余额核对过：1 号还是 6201.78，2 号还是 5086.48，谁都没被扣成。

**死锁不是故障，是两个事务抢顺序抢崩了**；被牺牲的那个要由应用层重新执行一遍。

## 6. 读懂死锁报告：`SHOW ENGINE INNODB STATUS`

出事之后抓紧执行（报告只保留最近一次）：

```sql
SHOW ENGINE INNODB STATUS\G
```

找 `LATEST DETECTED DEADLOCK` 那一段，上面这次实验的完整原文：

```text
LATEST DETECTED DEADLOCK
------------------------
2026-10-08 14:08:21 131831895766592
*** (1) TRANSACTION:
TRANSACTION 24035, ACTIVE 2 sec starting index read
mysql tables in use 1, locked 1
LOCK WAIT 3 lock struct(s), heap size 1128, 2 row lock(s), undo log entries 1
MySQL thread id 3290, OS thread handle 131831878981184, query id 93681 localhost root updating
UPDATE users SET balance = balance - 1 WHERE id = 1

*** (1) HOLDS THE LOCK(S):
RECORD LOCKS space id 5 page no 6 n bits 264 index PRIMARY of table `easy_mysql`.`users` trx id 24035 lock_mode X locks rec but not gap
Record lock, heap no 3 PHYSICAL RECORD: n_fields 10; compact format; info bits 0
 0: len 8; hex 0000000000000002; asc         ;;
 1: len 6; hex 000000005de3; asc     ] ;;
 2: len 7; hex 010000020421be; asc      ! ;;
 3: len 10; hex 757365725f3030303032; asc user_00002;;
 4: len 17; hex 7573657232406578616d706c652e636f6d; asc user2@example.com;;
 5: len 6; hex e5b9bfe5b79e; asc       ;;
 6: len 1; hex 27; asc ';;
 7: len 1; hex 81; asc  ;;
 8: len 6; hex 80000013dd30; asc      0;;
 9: len 5; hex 99b0468000; asc   F  ;;


*** (1) WAITING FOR THIS LOCK TO BE GRANTED:
RECORD LOCKS space id 5 page no 6 n bits 264 index PRIMARY of table `easy_mysql`.`users` trx id 24035 lock_mode X locks rec but not gap waiting
Record lock, heap no 2 PHYSICAL RECORD: n_fields 10; compact format; info bits 0
 0: len 8; hex 0000000000000001; asc         ;;
 1: len 6; hex 000000005de2; asc     ] ;;
 2: len 7; hex 020000015b0151; asc     [ Q;;
 3: len 10; hex 757365725f3030303031; asc user_00001;;
 4: len 17; hex 7573657231406578616d706c652e636f6d; asc user1@example.com;;
 5: len 6; hex e69dade5b79e; asc       ;;
 6: len 1; hex 20; asc  ;;
 7: len 1; hex 81; asc  ;;
 8: len 6; hex 80000018384e; asc     8N;;
 9: len 5; hex 99b36c8000; asc   l  ;;


*** (2) TRANSACTION:
TRANSACTION 24034, ACTIVE 4 sec starting index read
mysql tables in use 1, locked 1
LOCK WAIT 3 lock struct(s), heap size 1128, 2 row lock(s), undo log entries 1
MySQL thread id 3289, OS thread handle 131831877924416, query id 93684 localhost root updating
UPDATE users SET balance = balance - 1 WHERE id = 2

*** (2) HOLDS THE LOCK(S):
RECORD LOCKS space id 5 page no 6 n bits 264 index PRIMARY of table `easy_mysql`.`users` trx id 24034 lock_mode X locks rec but not gap
Record lock, heap no 2 PHYSICAL RECORD: n_fields 10; compact format; info bits 0
 0: len 8; hex 0000000000000001; asc         ;;
 1: len 6; hex 000000005de2; asc     ] ;;
 2: len 7; hex 020000015b0151; asc     [ Q;;
 3: len 10; hex 757365725f3030303031; asc user_00001;;
 4: len 17; hex 7573657231406578616d706c652e636f6d; asc user1@example.com;;
 5: len 6; hex e69dade5b79e; asc       ;;
 6: len 1; hex 20; asc  ;;
 7: len 1; hex 81; asc  ;;
 8: len 6; hex 80000018384e; asc     8N;;
 9: len 5; hex 99b36c8000; asc   l  ;;


*** (2) WAITING FOR THIS LOCK TO BE GRANTED:
RECORD LOCKS space id 5 page no 6 n bits 264 index PRIMARY of table `easy_mysql`.`users` trx id 24034 lock_mode X locks rec but not gap waiting
Record lock, heap no 3 PHYSICAL RECORD: n_fields 10; compact format; info bits 0
 0: len 8; hex 0000000000000002; asc         ;;
 1: len 6; hex 000000005de3; asc     ] ;;
 2: len 7; hex 010000020421be; asc      ! ;;
 3: len 10; hex 757365725f3030303032; asc user_00002;;
 4: len 17; hex 7573657232406578616d706c652e636f6d; asc user2@example.com;;
 5: len 6; hex e5b9bfe5b79e; asc       ;;
 6: len 1; hex 27; asc ';;
 7: len 1; hex 81; asc  ;;
 8: len 6; hex 80000013dd30; asc      0;;
 9: len 5; hex 99b0468000; asc   F  ;;

*** WE ROLL BACK TRANSACTION (2)
```

逐段读：

- **`*** (1) TRANSACTION` / `*** (2) TRANSACTION`**：两个当事人的当前语句。(1) 的语句是 `... WHERE id = 1`，(2) 的语句是 `... WHERE id = 2` —— 对照上面的 SQL，**(1) 是窗口 2，(2) 是窗口 1**
- **`HOLDS`**：(1) 的锁记录里 `hex ...0002` 是 id = 2，(2) 的锁记录里 `hex ...0001` 是 id = 1 —— **各自攥着对方要的那行**
- **`WAITING`**：(1) 在等 `hex ...0001`（id = 1），(2) 在等 `hex ...0002`（id = 2）—— **循环等待闭合**，每行结尾的 `waiting` 字样就是证据
- **`lock_mode X locks rec but not gap`**：争的是记录锁，不是间隙
- **结尾那一行 `*** WE ROLL BACK TRANSACTION (2)`**：被牺牲的是 (2)，也就是窗口 1 —— 和第 5 节里打印 `ERROR 1213` 的那个窗口严丝合缝

线上排查时，把 `UPDATE ... WHERE id = 1` 这句现成的 SQL 直接拿去代码里搜，写错加锁顺序的地方当场现形。

## 7. 预防死锁的三条铁律

**第一条：所有事务按同一顺序加锁（两把万能钥匙之一）。** 让窗口 1 和窗口 2 都按 id 从小到大一次锁完：

```sql
-- 两个窗口执行同一条
START TRANSACTION;
UPDATE users SET balance = balance - 1 WHERE id IN (1, 2) ORDER BY id;
SELECT NOW(6) AS 完成时刻 FROM DUAL;
ROLLBACK;
```

```text
+----------------------------+
| 窗口1完成时刻              |
+----------------------------+
| 2026-10-08 14:10:10.950746 |
+----------------------------+
+------------+
| marker     |
+------------+
| window1 ok |
+------------+
```

```text
+----------------------------+
| 窗口2完成时刻              |
+----------------------------+
| 2026-10-08 14:10:11.913624 |
+----------------------------+
+------------+
| marker     |
+------------+
| window2 ok |
+------------+
```

两个窗口都 `ok`，完成时刻一个 `10.95`、一个 `11.91` —— 晚启动的窗口 2 落后 0.96 秒完成，**它全程都在排队**，谁也没被牺牲。同样一批操作，只是把顺序统一了，结局从 `ERROR 1213` 变成安静地排队。

**第二条：缩短事务（两把万能钥匙之二）。** 持锁时间越短，撞车概率越低。事务里只放 SQL，HTTP 请求、文件读写、循环调接口全部挪到事务外面（第 18 篇的「事务的代价」实测过：锁一直持有到提交为止）。

**第三条：`UPDATE` / `DELETE` 永远带 `WHERE`。** 第 3 节那 4 秒的堵就是它的代价 —— 一行的锁变成五千行，别人想不撞都难。

死锁本身交给 `innodb_deadlock_detect`（实测为 `1`，自动开），你的责任是让循环等待没有机会发生。

## 8. 锁等待超时：等多久算够

不是每次撞车都会被判死锁，多数时候只是**干等**。等多久由 `innodb_lock_wait_timeout` 决定，默认 50 秒。把它调小实测一次：

```sql
-- 窗口 1：开事务锁住 3 号
START TRANSACTION;
SELECT * FROM users WHERE id = 3 FOR UPDATE;
SELECT NOW(6) AS 窗口1锁住3号起始时刻 FROM DUAL;
SELECT SLEEP(8);
ROLLBACK;
SELECT NOW(6) AS 窗口1释放时刻 FROM DUAL;
```

```sql
-- 窗口 2：调小超时，再去抢
SET SESSION innodb_lock_wait_timeout = 3;
SELECT @@innodb_lock_wait_timeout AS 本窗口超时秒 FROM DUAL;
START TRANSACTION;
SELECT NOW(6) AS 开始等待的时刻 FROM DUAL;
UPDATE users SET balance = balance + 1 WHERE id = 3;
SELECT NOW(6) AS 超时后的时刻 FROM DUAL;
ROLLBACK;
SET SESSION innodb_lock_wait_timeout = 50;
SELECT @@innodb_lock_wait_timeout AS 改回默认秒 FROM DUAL;
SELECT balance AS 3号余额 FROM users WHERE id = 3;
```

```text
+--------------------+
| 本窗口超时秒       |
+--------------------+
|                  3 |
+--------------------+
+----------------------------+
| 开始等待的时刻             |
+----------------------------+
| 2026-10-08 14:11:17.354059 |
+----------------------------+
ERROR 1205 (HY000) at line 6: Lock wait timeout exceeded; try restarting transaction
+----------------------------+
| 超时后的时刻               |
+----------------------------+
| 2026-10-08 14:11:20.355790 |
+----------------------------+
+-----------------+
| 改回默认秒      |
+-----------------+
|              50 |
+-----------------+
+------------+
| 3号余额    |
+------------+
|    2162.54 |
+------------+
```

窗口 1 那边的完整输出（`FOR UPDATE` 的结果 + 起止时刻）：

```text
+----+------------+-------------------+--------+-----+--------+---------+---------------------+
| id | username   | email             | city   | age | status | balance | created_at          |
+----+------------+-------------------+--------+-----+--------+---------+---------------------+
|  3 | user_00003 | user3@example.com | 北京   |  19 |      1 | 2162.54 | 2024-08-22 08:00:00 |
+----+------------+-------------------+--------+-----+--------+---------+---------------------+
+-------------------------------+
| 窗口1锁住3号起始时刻          |
+-------------------------------+
| 2026-10-08 14:11:15.208145    |
+-------------------------------+
+----------+
| SLEEP(8) |
+----------+
|        0 |
+----------+
+----------------------------+
| 窗口1释放时刻              |
+----------------------------+
| 2026-10-08 14:11:23.209760 |
+----------------------------+
```

`17.354059 → 20.355790`，**3.002 秒**，说等 3 秒就等 3 秒。注意窗口 1 要到 `23.209760` 才放锁 —— 超时发生在放锁之前，证明是「等腻了」而不是「等到手了」。

三条要点：

1. **超时不等于死锁**：`ERROR 1205` 只是「等腻了」，事务还活着，必须自己 `ROLLBACK`，否则锁继续攥着
2. **`SET SESSION` 只影响当前窗口**：别忘了 `SET SESSION innodb_lock_wait_timeout = 50;` 改回默认；会话一断，新连接看到的本来也是 50：

```text
+-----------------------------+--------------------+--------------+
| 新会话看到的超时秒          | 全局隔离级别       | 自动提交     |
+-----------------------------+--------------------+--------------+
|                          50 | REPEATABLE-READ    |            1 |
+-----------------------------+--------------------+--------------+
```

3. **50 秒别随便调大**：它把故障的暴露时间也拉长了；调小能让排队更早变成显式报错，调大只适合明确知道对方在跑长事务的场景

## 三个必须记住的结论

1. **写锁互斥，读不排队**：普通 `SELECT` 走快照（实测窗口 1 持锁期间读取和动手抢锁都在 `06:01.247` 同一毫秒里完成），写必须排队；卡住时 `PROCESSLIST.STATE = updating` + `data_lock_waits` 两步就能定位谁堵谁
2. **锁的粒度由 SQL 决定**：`UPDATE` 没 `WHERE` → 5070 行全锁；有 `WHERE` → 0.0007 秒放行；RR 下范围查询还会顺手锁空隙（Next-Key Lock），这是幻读被压住的代价与手段
3. **死锁靠「统一顺序 + 短事务 + 必带 WHERE」三条铁律预防**，InnoDB 自动检测并回滚其一（`ERROR 1213`）；干等走 `innodb_lock_wait_timeout`（`ERROR 1205`），超时后自己 `ROLLBACK`

## 常见错误

### ❌ 给超时变量赋一个字符串

```sql
-- ERROR 1232 (42000): Incorrect argument type to variable 'innodb_lock_wait_timeout'
SET SESSION innodb_lock_wait_timeout = 'abc';
```

**为什么错**：`innodb_lock_wait_timeout` 是整数变量，MySQL 在赋值时做类型检查，`'abc'` 转不成整数直接拒收 —— 你的窗口还停在原来的超时值上，后面「3 秒超时」的实验会一直等满 50 秒，看起来就像 SQL 卡死了。

**正确做法**：

```sql
SET SESSION innodb_lock_wait_timeout = 3;    -- 不带引号的数字
```

## 动手练

- [ ] 手动造出一次死锁，把报告里的「事务 1 / 事务 2」两段贴到笔记里
- [ ] 找出你项目里 `UPDATE` 忘了加 `WHERE` 的地方

<details>
<summary>点开看答案</summary>

第 1 题：照第 5 节跑 —— 窗口 1 先锁 1 号再 `SLEEP(4)` 再要 2 号，窗口 2 在这 4 秒里先锁 2 号再要 1 号。`ERROR 1213` 打出来之后立刻 `SHOW ENGINE INNODB STATUS\G`（报告只保留最近一次，慢了就被下一次死锁覆盖）。贴的时候重点标出两行 `HOLDS` 的 `hex ...0001` / `hex ...0002` 和收尾的 `*** WE ROLL BACK TRANSACTION (2)` —— 前者证明循环等待，后者指出谁被牺牲。

第 2 题：搜代码里的 `UPDATE ` 和 `DELETE `，看后面有没有 `WHERE`。没有的那条就是第 3 节里让全表 5070 行陪葬的那颗雷；顺手再看有 `WHERE` 的是不是走索引（`EXPLAIN` 的 `rows` 是不是 1），不走索引照样锁一大片。

</details>

## 配套实验

```powershell
docker cp lab/queries/20-demo-locks.sql easy-mysql:/tmp/
docker exec easy-mysql mysql -uroot -peasy123 -t -e "source /tmp/20-demo-locks.sql"
```

> 文件里标了「窗口 1」「窗口 2」的步骤要开两个终端对照跑（开法见第 19 篇），基线和清理段可以顺序执行。
> 行锁实验在 `users` / `demo_gap` 这些小表上做，别拿 20 万行的 `orders` 练手。跑完后 `SELECT COUNT(*), SUM(balance) FROM users;` 必须还是 `5000 / 25114527.71`，`demo_gap` 要被清理掉，`innodb_lock_wait_timeout` 要回到 50。

## 下一篇

[21 · 备份与恢复：先假设数据库会消失](21-backup-restore.md)
