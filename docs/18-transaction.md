# 18 · 事务与 ACID：一次转账为什么不能只扣钱

> **一句话价值**：用「转账」理解事务，写出第一条 `START TRANSACTION` / `COMMIT` / `ROLLBACK`，并亲手造一次回滚。

**难度**：⭐⭐⭐　|　**时长**：约 35 分钟　|　**涉及表**：`users`

## 什么时候你会遇到它

你给同学转账，程序执行了 `UPDATE` 扣款，然后网络断了 —— 钱扣了，对方没收到。你以为数据库会自动把「扣钱」和「加钱」当成一件事，**它不会**：默认设置下每条 `UPDATE` 单独生效，第一条执行完就已经落盘了。

这篇用你自己的库把事故重演一遍，再把 ACID 四个字母拆开讲给你。

## 本篇你会学到

- [ ] ACID 四个字母分别在解决什么问题
- [ ] `START TRANSACTION` / `COMMIT` / `ROLLBACK` 的完整流程
- [ ] **手动造一次回滚**，看事务里的中间态
- [ ] 报错之后事务到底回滚了没有（**大多数人猜错**）
- [ ] `SAVEPOINT` 部分回滚
- [ ] `autocommit` 是什么，为什么关掉它必须改回来
- [ ] 事务的代价：锁、刷盘、长事务
- [ ] InnoDB 和 MyISAM 的实况对比（本环境 `SHOW ENGINES`）

---

## 1. 先复现事故：钱是怎么「只扣一半」的

MySQL 默认 `autocommit = 1`，**每条语句自己就是一个事务，执行完立刻落盘**。照下面的顺序跑（单个窗口就行）：

```sql
SELECT id, balance FROM users WHERE id IN (1, 2);
UPDATE users SET balance = balance - 100 WHERE id = 1;   -- 执行完立刻生效
UPDATE users SET balance = balanc + 100 WHERE id = 2;    -- 故意把列名拼错
```

```text
+----+---------+
| id | balance |
+----+---------+
|  1 | 6201.78 |
|  2 | 5086.48 |
+----+---------+
```

```text
ERROR 1054 (42S22) at line 1: Unknown column 'balanc' in 'field list'
```

程序崩在第二条，客户端退出。**开一个新窗口**再查：

```sql
SELECT id, username, balance FROM users WHERE id IN (1, 2);
```

```text
+----+------------+---------+
| id | username   | balance |
+----+------------+---------+
|  1 | user_00001 | 6101.78 |
|  2 | user_00002 | 5086.48 |
+----+------------+---------+
```

**1 号白扣了 100，2 号一分没多。** 这就是「一次转账只扣钱」的现场。此时你没有任何办法 `ROLLBACK` —— 第一条 `UPDATE` 在报错之前就单独提交了。这不是 bug，是 `autocommit = 1` 的既定行为。

补救只能手工再来一笔反向转账：`UPDATE users SET balance = balance + 100 WHERE id = 1;`

## 2. ACID 四个字母，用一笔转账说人话

不抄定义，四个字母对应你刚才看到的四个问题：

**A · 原子性（Atomicity）**：「扣 100」和「加 100」必须当成**一步**，要么都成，要么都不成。下面的实验里一个 `ROLLBACK` 就把两步同时抹掉了 —— 这就是原子性。

**C · 一致性（Consistency）**：事务怎么折腾，账必须是平的。这张表 5000 人的余额总和是一条红线，任何一笔转账只能是「从这里挪到那里」，不许凭空多也不许凭空少：

```sql
SELECT COUNT(*), SUM(balance) FROM users;
```

```text
+----------+--------------+
| COUNT(*) | SUM(balance) |
+----------+--------------+
|     5000 |  25114527.71 |
+----------+--------------+
```

**I · 隔离性（Isolation）**：你事务里改了一半的东西，**别的窗口看不见**。我开了两个会话实测：会话 1 扣了 100 但不提交，停在那里；会话 2 查到的是 ——

```sql
-- 会话 2
SELECT id, balance FROM users WHERE id IN (1, 2);
```

```text
+----+---------+
| id | balance |
+----+---------+
|  1 | 6201.78 |
|  2 | 5086.48 |
+----+---------+
```

还是没扣款的旧值。隔离性让你的中间态对别人隐身，**具体隔到什么程度，是第 19 篇的全部内容**。

**D · 持久性（Durability）**：`COMMIT` 之后就落盘，断电也不丢。看参数就知道它下了多大本钱：

```sql
SELECT @@innodb_flush_log_at_trx_commit AS 每次提交刷盘,
       @@innodb_lock_wait_timeout AS 锁等待超时秒;
```

```text
+--------------------+--------------------+
| 每次提交刷盘       | 锁等待超时秒       |
+--------------------+--------------------+
|                  1 |                 50 |
+--------------------+--------------------+
```

`1` 表示每次提交都把日志刷到磁盘 —— 换来持久性，付出的是每次提交一次磁盘 I/O。

## 3. 手动实验：BEGIN、中间态、ROLLBACK（本篇核心）

```sql
SELECT id, balance FROM users WHERE id IN (1, 2);   -- 起点
START TRANSACTION;
UPDATE users SET balance = balance - 100 WHERE id = 1;
UPDATE users SET balance = balance + 100 WHERE id = 2;
SELECT id, balance FROM users WHERE id IN (1, 2);   -- 事务里的中间态
ROLLBACK;
SELECT id, balance FROM users WHERE id IN (1, 2);   -- 回到起点
```

```text
+----+---------+
| id | balance |
+----+---------+
|  1 | 6201.78 |
|  2 | 5086.48 |
+----+---------+
+----+---------+
| id | balance |
+----+---------+
|  1 | 6101.78 |
|  2 | 5186.48 |
+----+---------+
+----+---------+
| id | balance |
+----+---------+
|  1 | 6201.78 |
|  2 | 5086.48 |
+----+---------+
```

三张表按顺序是：**起点 → 中间态 → 回滚后**。中间态里 1 号少了、2 号多了，只存在于这个窗口里；一句 `ROLLBACK` 之后和起点一字不差。原子性就是这样工作的。

`START TRANSACTION` 还可以写成 `BEGIN`，效果一样。

## 4. 真的提交：COMMIT

确认中间态没问题，就用 `COMMIT` 落盘：

```sql
START TRANSACTION;
UPDATE users SET balance = balance - 100 WHERE id = 1;
UPDATE users SET balance = balance + 100 WHERE id = 2;
COMMIT;
SELECT id, balance FROM users WHERE id IN (1, 2);
```

```text
+----+---------+
| id | balance |
+----+---------+
|  1 | 6101.78 |
|  2 | 5186.48 |
+----+---------+
```

提交之后就撤不掉了。**为了保持数据集干净，我在实验后又做了一笔 +100 / -100 的反向转账把它抵消** —— 配套实验文件里也是这么写的，你自己的练习也照这个套路还原。

## 5. 报错不会替你回滚（本篇最容易搞错的一点）

把第 1 节那句错误 SQL 放进事务里再跑一遍（配套实验文件用它收尾，交互式窗口里逐条执行）：

```sql
START TRANSACTION;
UPDATE users SET balance = balance - 100 WHERE id = 1;
UPDATE users SET balance = balanc - 100 WHERE id = 2;   -- 报错
SELECT id, balance FROM users WHERE id IN (1, 2);       -- 事务还开着，先看现场
ROLLBACK;
SELECT id, balance FROM users WHERE id IN (1, 2);       -- 自己回滚之后
```

```text
ERROR 1054 (42S22) at line 6: Unknown column 'balanc' in 'field list'
+----+---------+
| id | balance |
+----+---------+
|  1 | 6201.78 |
|  2 | 5086.48 |
+----+---------+
+----+---------+
| id | balance |
+----+---------+
|  1 | 6101.78 |
|  2 | 5086.48 |
+----+---------+
+----+---------+
| id | balance |
+----+---------+
|  1 | 6201.78 |
|  2 | 5086.48 |
+----+---------+
```

看清中间那张表：**报错之后事务并没有自动回滚，1 号还扣着 100。** MySQL 只回滚出错的那一条语句，整个事务要不要撤销，由你决定。你有两条路：

- 写错了 → 自己执行 `ROLLBACK`（第三张表，回到起点）
- 程序直接崩、连接断开 → 服务器会把**没提交**的事务回滚掉（配套实验用 `source` 整体执行时，正是靠这一条保持数据干净的）

所以第 1 节的事故才会发生：`autocommit = 1` 下那条扣款**已经提交**，断开连接也救不回来。

## 6. SAVEPOINT：只撤销一部分

一笔业务里有三步扣款，前两步对、第三步错，只想撤掉出错的第三步：

```sql
SELECT balance AS 扣款前 FROM users WHERE id = 1;
START TRANSACTION;
UPDATE users SET balance = balance - 50 WHERE id = 1;
SAVEPOINT s1;                    -- 存档点 1
UPDATE users SET balance = balance - 50 WHERE id = 1;
SAVEPOINT s2;                    -- 存档点 2
UPDATE users SET balance = balance - 50 WHERE id = 1;
SELECT balance AS 扣了三次后 FROM users WHERE id = 1;
ROLLBACK TO s1;                  -- 回到存档点 1
SELECT balance AS 回滚到s1后 FROM users WHERE id = 1;
COMMIT;
SELECT balance AS 最终 FROM users WHERE id = 1;
```

```text
+-----------+
| 扣款前    |
+-----------+
|   6201.78 |
+-----------+
+-----------------+
| 扣了三次后      |
+-----------------+
|         6051.78 |
+-----------------+
+----------------+
| 回滚到s1后     |
+----------------+
|        6151.78 |
+----------------+
+---------+
| 最终    |
+---------+
| 6151.78 |
+---------+
```

`SAVEPOINT` 就是游戏里的存档：6201.78 扣三次到 6051.78，`ROLLBACK TO s1` 回到第一个存档点 —— 只保留第一次的 -50，所以是 6151.78。存档点在 `COMMIT` 或整段 `ROLLBACK` 后全部作废。

（实验做完我还原了那 50 元，`SELECT` 显示回到 6201.78。）

## 7. autocommit：默认开着，关掉必须改回来

同一个「扣 100 再 ROLLBACK」的动作，开关两种状态结果完全不同：

```sql
SELECT @@autocommit AS 默认自动提交;      -- 1
UPDATE users SET balance = balance + 100 WHERE id = 1;
ROLLBACK;
SELECT balance AS ROLLBACK之后 FROM users WHERE id = 1;
UPDATE users SET balance = balance - 100 WHERE id = 1;   -- 补救
SET autocommit = 0;
SELECT @@autocommit AS 关掉以后;          -- 0
UPDATE users SET balance = balance + 100 WHERE id = 1;
ROLLBACK;
SELECT balance AS ROLLBACK之后2 FROM users WHERE id = 1;
SET autocommit = 1;                       -- ★ 改回来
SELECT @@autocommit AS 改回来;             -- 1
SELECT balance AS 最终 FROM users WHERE id = 1;
```

```text
+--------------------+
| 默认自动提交       |
+--------------------+
|                  1 |
+--------------------+
+----------------+
| ROLLBACK之后   |
+----------------+
|        6301.78 |
+----------------+
+--------------+
| 补救之后     |
+--------------+
|      6201.78 |
+--------------+
+--------------+
| 关掉以后     |
+--------------+
|            0 |
+--------------+
+-----------------+
| ROLLBACK之后2   |
+-----------------+
|         6201.78 |
+-----------------+
+-----------+
| 改回来    |
+-----------+
|         1 |
+-----------+
+---------+
| 最终    |
+---------+
| 6201.78 |
+---------+
```

`autocommit = 1` 时 `ROLLBACK` 是空操作：6301.78 撤不掉，只能手工补救。改成 `0` 之后，语句不再自动提交，`ROLLBACK` 才真正生效（6201.78）。

**用完必须 `SET autocommit = 1;` 改回来**，否则同一个窗口里后面的所有修改都会「攒着不提交」——数据别人看不见，锁也一直不放。忘了提交就关窗口，是生产上「事务卡死」的头号原因。

## 8. 事务的代价：别把事务开太大

事务不是免费的，三笔账：

**锁**：事务期间改动的行一直被锁着，别的会话写这一行就得等（第 20 篇整篇都在讲它）。**刷盘**：上面的 `innodb_flush_log_at_trx_commit = 1` 决定了每次提交都要一次磁盘 I/O。**长事务**：趁一个会话把事务开着 6 秒，另开一个窗口查 `information_schema.innodb_trx` 能看到它的实时状态：

```sql
SELECT trx_id, trx_state, trx_started, trx_rows_locked, trx_query
FROM information_schema.innodb_trx;
```

```text
*************************** 1. row ***************************
         trx_id: 23814
      trx_state: RUNNING
    trx_started: 2026-10-08 12:45:15
trx_rows_locked: 1
      trx_query: SELECT SLEEP(6)
```

`trx_rows_locked: 1` —— 这一秒它锁着 1 行，事务不结束，锁就一秒不放。回滚比提交贵得多（要把所有改动挨个撤销），所以：**事务里只放 SQL**，发 HTTP 请求、读文件、循环调接口统统挪到事务外面。

## 9. InnoDB vs MyISAM：谁才有事务

```sql
SELECT ENGINE, SUPPORT, TRANSACTIONS, SAVEPOINTS
FROM information_schema.ENGINES
WHERE ENGINE IN ('InnoDB', 'MyISAM');
```

```text
+--------+---------+--------------+------------+
| ENGINE | SUPPORT | TRANSACTIONS | SAVEPOINTS |
+--------+---------+--------------+------------+
| InnoDB | DEFAULT | YES          | YES        |
| MyISAM | YES     | NO           | NO         |
+--------+---------+--------------+------------+
```

`TRANSACTIONS = NO` 的意思是 MyISAM **根本不理你**。实测一张 MyISAM 临时表：

```sql
CREATE TABLE t_myisam_demo (id INT PRIMARY KEY) ENGINE=MyISAM;
START TRANSACTION;
INSERT INTO t_myisam_demo VALUES (1);
ROLLBACK;
SELECT COUNT(*) AS 回滚后还剩几行 FROM t_myisam_demo;
DROP TABLE t_myisam_demo;
```

```text
+-----------------------+
| 回滚后还剩几行        |
+-----------------------+
|                     1 |
+-----------------------+
```

`ROLLBACK` 执行了，行还在。**要事务就必须用 InnoDB**（`DEFAULT` 那行的意思是建表不写 `ENGINE=` 时用它）。本仓库八张表全是 InnoDB，你不用做任何选择，但以后看别人的建表语句要多扫一眼 `ENGINE=`。

## 三个必须记住的结论

1. **默认 `autocommit = 1`，每条语句单独提交**。转账拆成两条裸 `UPDATE`，第一条就已经落盘 —— 事故就是这么来的
2. **报错 ≠ 自动回滚**。语句出错只回滚那一条，事务还开着；要么自己 `ROLLBACK`，要么靠断开连接让服务器兜底
3. **事务里只放 SQL**：锁到提交为止、每次提交都刷盘、长事务锁+拖垮回滚 —— 三条代价都得掏钱

## 常见错误

### ❌ 事务关键字拼错

```sql
-- ERROR 1064 (42000): You have an error in your SQL syntax; check the manual that corresponds to your MySQL server version for the right syntax to use near 'TRASACTION' at line 1
START TRASACTION;
```

**为什么错**：`TRASACTION` 不是词，MySQL 直接给你语法错误 —— 后面的语句全都在事务外面裸奔。

**正确做法**：

```sql
START TRANSACTION;   -- 或者写 BEGIN;
```

### ❌ 回滚到一个不存在的存档点

```sql
-- ERROR 1305 (42000): SAVEPOINT s999 does not exist
ROLLBACK TO s999;
```

**为什么错**：存档点属于「当前这个事务」，从没 `SAVEPOINT s999;` 过，或者上一个事务已经 `COMMIT` / `ROLLBACK`（存档点全部作废），都找不到它。

**正确做法**：先 `SAVEPOINT s999;` 再 `ROLLBACK TO s999;`，而且要在同一个事务里。

## 动手练

- [ ] 完成一笔转账并 `COMMIT`，再做一笔反向转账 `COMMIT`；然后单独做一笔 `ROLLBACK`，问自己：**为什么 COMMIT 撤不掉，ROLLBACK 能撤掉？**
- [ ] 故意在两条 `UPDATE` 中间执行一句语法错误的 SQL，观察**报错后事务的真实状态** —— 事务并没有自动回滚，先 `SELECT` 看现场，再手动 `ROLLBACK` 救回来

<details>
<summary>点开看答案</summary>

第 1 题：`COMMIT` 的瞬间事务就结束了，落盘的数据不存在「撤销」一说，只能再做一笔反向业务；`ROLLBACK` 面对的是还没提交的事务，整段撤销后和什么都没发生过一样。配套实验的场景 3 和场景 2 就是这两个对照。

第 2 题：`START TRANSACTION; UPDATE -100; ERROR; SELECT ...` —— 现场那张表显示 1 号是 6101.78，事务没回滚；执行 `ROLLBACK;` 后变回 6201.78。如果当时直接把窗口关了，服务器也会替你回滚（没提交嘛），两种收场数据都是干净的。

</details>

## 配套实验

```powershell
docker cp lab/queries/18-demo-transaction.sql easy-mysql:/tmp/
docker exec easy-mysql mysql -uroot -peasy123 -t -e "source /tmp/18-demo-transaction.sql"
```

> 文件里**故意保留了一条写错的语句**（场景 7 的 `balanc`），它是全文件唯一一条错误，用来演示「报错之后事务的真实状态」。
> 每个场景都从 1 号 / 2 号用户的余额出发，做完自己还原；跑完后 `SELECT COUNT(*), SUM(balance) FROM users;` 必须还是 `5000 / 25114527.71`。

## 下一篇

[19 · 隔离级别与四种并发问题](19-isolation-level.md)
