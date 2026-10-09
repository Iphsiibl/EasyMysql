# 16 · 慢查询优化实战：把完整流程走一遍

> **一句话价值**：学会一套可复用的「找慢 SQL → 分析 → 优化 → 验证」流程。

**难度**：⭐⭐⭐⭐　|　**时长**：约 40 分钟　|　**涉及表**：`orders`、`orders_slow`、`order_items`

## 什么时候你会遇到它

接口要 2 秒，监控告警点名了你负责的接口。你打开代码，几十条 SQL，看哪条都眼熟。这时候缺的不是灵感，是**方法论**：先抓住那条真凶，再动刀，每动一刀都留下前后对照的数字。

## 本篇你会学到

- [ ] 慢查询日志的完整打开方式：开日志、调阈值、从日志里挑出真凶
- [ ] 「症状 → 原因 → 药方」对照表，5 种常见病一次记牢
- [ ] 三个实战的改法和真实前后对照：深分页、批量写入、`COUNT(*)`
- [ ] 怎么判断一条 SQL 值不值得优化（0.4 毫秒的查询别碰）

## 1. 第 1 步：抓 —— 没有日志，你连改哪条都不知道

慢查询日志（slow query log）把超过 `long_query_time` 的语句**原文**记下来。先看四个开关：

```sql
SHOW VARIABLES LIKE 'slow_query_log';
SHOW VARIABLES LIKE 'slow_query_log_file';
SHOW VARIABLES LIKE 'long_query_time';
SHOW VARIABLES LIKE 'log_output';
```

```text
+----------------+-------+
| Variable_name  | Value |
+----------------+-------+
| slow_query_log | ON    |
+----------------+-------+
+---------------------+--------------------------------------+
| Variable_name       | Value                                |
+---------------------+--------------------------------------+
| slow_query_log_file | /var/lib/mysql/63cfcab4c3db-slow.log |
+---------------------+--------------------------------------+
+-----------------+----------+
| Variable_name   | Value    |
+-----------------+----------+
| long_query_time | 0.200000 |
+-----------------+----------+
+---------------+-------+
| Variable_name | Value |
+---------------+-------+
| log_output    | FILE  |
+---------------+-------+
```

阈值 0.2 秒、写文件。想把指定的几条 SQL 强行塞进日志，把**当前会话**的阈值调到 0，跑完立刻恢复：

```sql
SET @old_lqt = @@SESSION.long_query_time;
SET SESSION long_query_time = 0;
-- ……跑你要抓的那几条 SQL……
SET SESSION long_query_time = @old_lqt;
```

日志是文件，得去容器里看（文件名以你上面 `SHOW VARIABLES` 的输出为准）：

```powershell
docker exec easy-mysql tail -n 40 /var/lib/mysql/<容器ID>-slow.log
```

实验第 1 节抓到的 4 条候选，原文如下：

```text
# Time: 2026-10-08T03:08:50.373850Z
# User@Host: root[root] @ localhost []  Id:  1263
# Query_time: 0.031127  Lock_time: 0.000002 Rows_sent: 1  Rows_examined: 200000
SET timestamp=1791428930;
SELECT COUNT(*) FROM orders WHERE amount > 5000;
# Time: 2026-10-08T03:08:50.389925Z
# User@Host: root[root] @ localhost []  Id:  1263
# Query_time: 0.015238  Lock_time: 0.000002 Rows_sent: 10  Rows_examined: 100010
SET timestamp=1791428930;
SELECT id, user_id, amount FROM orders ORDER BY id LIMIT 100000, 10;
# Time: 2026-10-08T03:08:50.457170Z
# User@Host: root[root] @ localhost []  Id:  1263
# Query_time: 0.066558  Lock_time: 0.000002 Rows_sent: 10  Rows_examined: 50010
SET timestamp=1791428930;
SELECT id, amount FROM orders WHERE status = 'paid' ORDER BY amount DESC LIMIT 10;
# Time: 2026-10-08T03:08:50.846036Z
# User@Host: root[root] @ localhost []  Id:  1263
# Query_time: 0.388116  Lock_time: 0.000002 Rows_sent: 1  Rows_examined: 800000
SET timestamp=1791428930;
SELECT COUNT(*) FROM orders o JOIN order_items i ON i.order_id = o.id;
```

每条都带两个关键数字：`Query_time` 花了多少、`Rows_examined` 读了多少。最后那条读了 80 万行只送 1 行 —— 读写比这么难看，就是头号嫌疑。跑完整个实验再看，第 5 节那条 `CALL ins_one_by_one(2000)`（6.803091 秒）也躺在里面。

按耗时排个序，日志里的狠角色一目了然：

```powershell
docker exec easy-mysql sh -c 'grep Query_time /var/lib/mysql/<容器ID>-slow.log | sort -rn -k3 | head -5'
```

生产环境的标准武器是 `pt-query-digest`（Percona 工具包，能把日志按 SQL 指纹聚合、排出 Top N）。本镜像没装 —— 容器里 `command -v perl` 都查不到，它跑不起来。需要就在容器里 `apt-get install -y percona-toolkit`（要联网）；装不上时上面的 `grep`/`sort` 组合够用了。

## 2. 第 2 步：分析 —— 5 条慢 SQL 的病历

拿到嫌疑名单，逐条 `EXPLAIN`（方法在第 15 篇）。实验第 2 节是 5 条慢 SQL 的原始计划：

慢 SQL ①：`amount` 上没索引，只能全表扫 ——

```text
+----+-------------+--------+------------+------+---------------+------+---------+------+--------+----------+-------------+
| id | select_type | table  | partitions | type | possible_keys | key  | key_len | ref  | rows   | filtered | Extra       |
+----+-------------+--------+------------+------+---------------+------+---------+------+--------+----------+-------------+
|  1 | SIMPLE      | orders | NULL       | ALL  | NULL          | NULL | NULL    | NULL | 199430 |    33.33 | Using where |
+----+-------------+--------+------------+------+---------------+------+---------+------+--------+----------+-------------+
```

慢 SQL ②：深分页，真跑一遍（`EXPLAIN ANALYZE`）——

```text
*************************** 1. row ***************************
EXPLAIN: -> Limit/Offset: 10/100000 row(s)  (cost=5116 rows=10) (actual time=20.6..20.6 rows=10 loops=1)
    -> Index scan on orders using PRIMARY  (cost=5116 rows=100010) (actual time=0.527..17.1 rows=100010 loops=1)
```

慢 SQL ③：`status` 有索引，但 `ORDER BY amount` 不在索引里 ——

```text
+----+-------------+--------+------------+------+---------------------------+---------------------------+---------+-------+-------+----------+---------------------------------------+
| id | select_type | table  | partitions | type | possible_keys             | key                       | key_len | ref   | rows  | filtered | Extra                                 |
+----+-------------+--------+------------+------+---------------------------+---------------------------+---------+-------+-------+----------+---------------------------------------+
|  1 | SIMPLE      | orders | NULL       | ref  | idx_orders_status_created | idx_orders_status_created | 1       | const | 95652 |   100.00 | Using index condition; Using filesort |
+----+-------------+--------+------------+------+---------------------------+---------------------------+---------+-------+-------+----------+---------------------------------------+
```

慢 SQL ④：两个索引都能用，优化器挑了带 filesort 的那个 ——

```text
+----+-------------+--------+------------+------+-------------------------------------------+---------------------------+---------+-------+-------+----------+----------------------------------------------------+
| id | select_type | table  | partitions | type | possible_keys                             | key                       | key_len | ref   | rows  | filtered | Extra                                              |
+----+-------------+--------+------------+------+-------------------------------------------+---------------------------+---------+-------+-------+----------+----------------------------------------------------+
|  1 | SIMPLE      | orders | NULL       | ref  | idx_orders_user,idx_orders_status_created | idx_orders_status_created | 1       | const | 95652 |    49.08 | Using index condition; Using where; Using filesort |
+----+-------------+--------+------------+------+-------------------------------------------+---------------------------+---------+-------+-------+----------+----------------------------------------------------+
```

慢 SQL ⑤：`OR` 的一边没有索引，整条放弃索引 ——

```text
+----+-------------+--------+------------+------+-----------------+------+---------+------+--------+----------+-------------+
| id | select_type | table  | partitions | type | possible_keys   | key  | key_len | ref  | rows   | filtered | Extra       |
+----+-------------+--------+------------+------+-----------------+------+---------+------+--------+----------+-------------+
|  1 | SIMPLE      | orders | NULL       | ALL  | idx_orders_user | NULL | NULL    | NULL | 199430 |    33.34 | Using where |
+----+-------------+--------+------------+------+-----------------+------+---------+------+--------+----------+-------------+
```

五条的病历汇总：

| 慢 SQL | 症状 | 证据 |
|---|---|---|
| ① `amount > 5000` | 缺索引 | `type=ALL`，估扫 199430 行 |
| ② `LIMIT 100000, 10` | 深分页 | 实扫 100010 行，只送 10 行 |
| ③ `status` + `ORDER BY amount` | 排序列不在索引 | `Using filesort`，估扫 95652 行 |
| ④ `status` + `user_id` 范围 + 排序 | 优化器挑了带 filesort 的索引 | `filtered 49.08` + `Using filesort` |
| ⑤ `OR amount` | 一边没索引拖死整条 | `possible_keys` 里有货、`key` 却是 `NULL` |

## 3. 第 3 步：开方 —— 症状 → 原因 → 药方

| 症状 | 原因 | 药方 |
|---|---|---|
| `type=ALL` + 大表 | 缺索引 | 加索引 |
| `Using filesort` | 排序字段没索引 | 联合索引 |
| `Using temporary` | GROUP BY / DISTINCT | 改写 / 提前聚合 |
| 扫描行数 ≫ 返回行数 | 索引区分度差 | 换索引 |
| `OR` 拖后腿 | 部分列无索引 | 改 `UNION ALL` |

表里每一行都能在本仓库找到现场。四条 SQL 逐条开方（第 5 条分页是第 4 节的主角）：

**慢 SQL ①：缺索引 → 加索引**

```text
+------------------+
| 优化前_毫秒 |
+------------------+
|             33.4 |
+------------------+
```

```sql
ALTER TABLE orders ADD INDEX idx_amount (amount);
```

```text
+----+-------------+--------+------------+-------+---------------+------------+---------+------+-------+----------+--------------------------+
| id | select_type | table  | partitions | type  | possible_keys | key        | key_len | ref  | rows  | filtered | Extra                    |
+----+-------------+--------+------------+-------+---------------+------------+---------+------+-------+----------+--------------------------+
|  1 | SIMPLE      | orders | NULL       | range | idx_amount    | idx_amount | 5       | NULL | 83030 |   100.00 | Using where; Using index |
+----+-------------+--------+------------+-------+---------------+------------+---------+------+-------+----------+--------------------------+
```

```text
+------------------+
| 优化后_毫秒 |
+------------------+
|              7.6 |
+------------------+
```

`rows` 从 199430 掉到 83030，`Using index` 表示连回表都省了。实验跑完立刻 `DROP INDEX` —— 第 14 篇量过，索引是拿写入速度换的。

**慢 SQL ③：`Using filesort` → 把排序列包进联合索引**

```text
+---------------------+
| 建索引前_毫秒 |
+---------------------+
|                60.1 |
+---------------------+
```

```sql
ALTER TABLE orders ADD INDEX idx_status_amount (status, amount);
```

```text
+----+-------------+--------+------------+------+---------------------------------------------+-------------------+---------+-------+-------+----------+-----------------------------------------------+
| id | select_type | table  | partitions | type | possible_keys                               | key               | key_len | ref   | rows  | filtered | Extra                                         |
+----+-------------+--------+------------+------+---------------------------------------------+-------------------+---------+-------+-------+----------+-----------------------------------------------+
|  1 | SIMPLE      | orders | NULL       | ref  | idx_orders_status_created,idx_status_amount | idx_status_amount | 1       | const | 98518 |   100.00 | Using where; Backward index scan; Using index |
+----+-------------+--------+------------+------+---------------------------------------------+-------------------+---------+-------+-------+----------+-----------------------------------------------+
```

```text
+---------------------+
| 建索引后_毫秒 |
+---------------------+
|                 1.4 |
+---------------------+
```

`Using filesort` 消失了；`Backward index scan` 表示 `DESC` 排序只要反着扫一遍索引，不需要额外动作。同样跑完即删。

**慢 SQL ④：优化器选错索引 → `FORCE INDEX` 只是止痛**

```sql
EXPLAIN SELECT * FROM orders FORCE INDEX (idx_orders_user)
WHERE status = 'paid' AND user_id BETWEEN 1 AND 100 ORDER BY user_id;
```

```text
+----+-------------+--------+------------+-------+-----------------+-----------------+---------+------+------+----------+------------------------------------+
| id | select_type | table  | partitions | type  | possible_keys   | key             | key_len | ref  | rows | filtered | Extra                              |
+----+-------------+--------+------------+-------+-----------------+-----------------+---------+------+------+----------+------------------------------------+
|  1 | SIMPLE      | orders | NULL       | range | idx_orders_user | idx_orders_user | 8       | NULL |    1 |    33.33 | Using index condition; Using where |
+----+-------------+--------+------------+-------+-----------------+-----------------+---------+------+------+----------+------------------------------------+
```

注意 `rows` 变成了 **1** —— 强制之后估算直接失真，这份 EXPLAIN 已经没法用来下结论，用 `EXPLAIN ANALYZE` 真跑：

```text
*************************** 1. row ***************************
EXPLAIN: -> Sort: orders.user_id  (cost=5295 rows=95652) (actual time=73.4..74.1 rows=10823 loops=1)
    -> Filter: (orders.user_id between 1 and 100)  (cost=5295 rows=95652) (actual time=5.33..70.6 rows=10823 loops=1)
        -> Index lookup on orders using idx_orders_status_created (status='paid'), with index condition: (orders.`status` = 'paid')  (cost=5295 rows=95652) (actual time=5.33..68.2 rows=50000 loops=1)

*************************** 1. row ***************************
EXPLAIN: -> Filter: (orders.`status` = 'paid')  (cost=0.71 rows=0.333) (actual time=0.0629..59.5 rows=10823 loops=1)
    -> Index range scan on orders using idx_orders_user over (1 <= user_id <= 100), with index condition: (orders.user_id between 1 and 100)  (cost=0.71 rows=1) (actual time=0.0295..56.5 rows=43168 loops=1)
```

默认计划实扫 50000 行再 filesort，74.1 毫秒；强制后实扫 43168 行、免掉 filesort，59.5 毫秒 —— 这一次优化器确实选错了。但 `FORCE INDEX` 是绕过优化器的止痛药，不是修复：估算已经失真，收益也只建立在这份数据分布上。为什么会选错、怎么根治，第 17 篇讲透。

**慢 SQL ⑤：`OR` 拖后腿 → 改写 `UNION ALL`**

```text
+----+-------------+--------+------------+------+-----------------+-----------------+---------+-------+--------+----------+-------------+
| id | select_type | table  | partitions | type | possible_keys   | key             | key_len | ref   | rows   | filtered | Extra       |
+----+-------------+--------+------------+------+-----------------+-----------------+---------+-------+--------+----------+-------------+
|  1 | PRIMARY     | orders | NULL       | ref  | idx_orders_user | idx_orders_user | 8       | const |     29 |   100.00 | NULL        |
|  2 | UNION       | orders | NULL       | ALL  | NULL            | NULL            | NULL    | NULL  | 199430 |    33.33 | Using where |
+----+-------------+--------+------------+------+-----------------+-----------------+---------+-------+--------+----------+-------------+
```

第一个分支从全表扫变成 29 行的索引查找；第二个分支（`amount`）还是全表扫 —— 省掉的是「整条查询被 `OR` 一把拖死」这件事，瓶颈（`amount` 没索引）还得靠第 ① 条的药方。

## 4. 实战一：深分页 —— 主键排序和任意列排序，解法不同

```sql
-- (a) 原始：先扫掉前 10 万行
SELECT id, user_id, amount FROM orders ORDER BY id LIMIT 100000, 10;
-- (b) 延迟关联：内层只取主键
SELECT o.* FROM orders o
JOIN (SELECT id FROM orders ORDER BY id LIMIT 100000, 10) t ON t.id = o.id;
-- (c) 书签式：从上一页最后一条的 id 直接往后取
SELECT id, user_id, amount FROM orders WHERE id > 199990 ORDER BY id LIMIT 10;
```

```text
*************************** 1. row ***************************
EXPLAIN: -> Limit/Offset: 10/100000 row(s)  (cost=5116 rows=10) (actual time=22.3..22.3 rows=10 loops=1)
    -> Index scan on orders using PRIMARY  (cost=5116 rows=100010) (actual time=0.513..18.4 rows=100010 loops=1)

*************************** 1. row ***************************
EXPLAIN: -> Nested loop inner join  (cost=30123 rows=10) (actual time=18.4..18.4 rows=10 loops=1)
    -> Table scan on t  (cost=5117..5119 rows=10) (actual time=18.4..18.4 rows=10 loops=1)
        -> Materialize  (cost=5117..5117 rows=10) (actual time=18.4..18.4 rows=10 loops=1)
            -> Limit/Offset: 10/100000 row(s)  (cost=5116 rows=10) (actual time=18.4..18.4 rows=10 loops=1)
                -> Covering index scan on orders using PRIMARY  (cost=5116 rows=100010) (actual time=0.914..14.8 rows=100010 loops=1)
    -> Single-row index lookup on o using PRIMARY (id=t.id)  (cost=0.25 rows=1) (actual time=0.00328..0.00333 rows=1 loops=10)

*************************** 1. row ***************************
EXPLAIN: -> Limit: 10 row(s)  (cost=2.26 rows=10) (actual time=0.0191..0.0216 rows=10 loops=1)
    -> Filter: (orders.id > 199990)  (cost=2.26 rows=10) (actual time=0.0187..0.0204 rows=10 loops=1)
        -> Index range scan on orders using PRIMARY over (199990 < id)  (cost=2.26 rows=10) (actual time=0.0177..0.0191 rows=10 loops=1)
```

(a) 扫掉 100010 行才吐 10 行；(b) 延迟关联在本例**没赚** —— 要的列全在主键索引里，内外层都扫了 100010 行；(c) 书签式直接定位 10 行，一个数量级都不止：

| 方案 | 实测耗时 |
|---|---|
| (a) 原始 `LIMIT 100000, 10` | 15.2 毫秒 |
| (c) 书签式 `id > 199990` | 0.3 毫秒 |

按主键分页时，「记住上一页最后一条 `id`」永远是最快解。换个排序列 —— `ORDER BY user_id`（不唯一、不连续），书签式没法用，这次轮到延迟关联发力：

```text
*************************** 1. row ***************************
EXPLAIN: -> Limit/Offset: 10/100000 row(s)  (cost=20143 rows=10) (actual time=127..127 rows=10 loops=1)
    -> Sort: orders.user_id, limit input to 100010 row(s) per chunk  (cost=20143 rows=199430) (actual time=116..123 rows=100010 loops=1)
        -> Table scan on orders  (cost=20143 rows=199430) (actual time=0.551..49.6 rows=200000 loops=1)

*************************** 1. row ***************************
EXPLAIN: -> Nested loop inner join  (cost=30123 rows=10) (actual time=21..21 rows=10 loops=1)
    -> Table scan on t  (cost=5117..5119 rows=10) (actual time=20.9..20.9 rows=10 loops=1)
        -> Materialize  (cost=5117..5117 rows=10) (actual time=20.9..20.9 rows=10 loops=1)
            -> Limit/Offset: 10/100000 row(s)  (cost=5116 rows=10) (actual time=20.9..20.9 rows=10 loops=1)
                -> Covering index scan on orders using idx_orders_user  (cost=5116 rows=100010) (actual time=0.722..17 rows=100010 loops=1)
    -> Single-row index lookup on o using PRIMARY (id=t.id)  (cost=0.25 rows=1) (actual time=0.00848..0.0085 rows=1 loops=10)
```

原始写法全表扫 200000 行再 filesort；延迟关联让内层在 `idx_orders_user` 覆盖索引里只取 `id`（`user_id` 排序跟着索引走，扫 100010 行），外层按主键回表 10 次：

| 方案（按 `user_id` 排序） | 实测耗时 |
|---|---|
| 原始 | 101.6 毫秒 |
| 延迟关联 | 12.2 毫秒 |

**按任意列排序的深分页，延迟关联是标准答案；能拿上一页末尾主键时，书签式更快。**

## 5. 实战二：批量写入 —— 同样 2000 行，差 75 倍

一条条 `INSERT` 依赖自动提交，等于 2000 次日志落盘；攒进一个事务只提交一次。实验里两个存储过程只差一层事务包装：

```sql
DELIMITER $$
CREATE PROCEDURE ins_one_by_one(IN n INT)
BEGIN
  DECLARE i INT DEFAULT 0;
  WHILE i < n DO
    INSERT INTO orders_slow (user_id, product_id, quantity, amount, status, created_at, updated_at)
    VALUES (1, 1, 1, 10.00, 'created', '2024-06-01 12:00:00', '2024-06-01 13:00:00');
    SET i = i + 1;
  END WHILE;
END$$
CREATE PROCEDURE ins_batch_tx(IN n INT)
BEGIN
  DECLARE i INT DEFAULT 0;
  START TRANSACTION;
  WHILE i < n DO
    INSERT INTO orders_slow (user_id, product_id, quantity, amount, status, created_at, updated_at)
    VALUES (1, 1, 1, 10.00, 'created', '2024-06-01 12:00:00', '2024-06-01 13:00:00');
    SET i = i + 1;
  END WHILE;
  COMMIT;
END$$
DELIMITER ;
```

```text
+----------------------------+
| 逐条插入2000行_毫秒 |
+----------------------------+
|                     6803.9 |
+----------------------------+
+----------------------------+
| 攒批事务2000行_毫秒 |
+----------------------------+
|                       90.8 |
+----------------------------+
```

6803.9 → 90.8 毫秒，差 75 倍 —— 差的全是提交开销。导入类任务先 `START TRANSACTION` 再循环插，是收益最大的一招。插完立刻清场，行数回到基线：

```text
+-----------------+
| 插入后行数 |
+-----------------+
|          204000 |
+-----------------+
+-----------------+
| 删除后行数 |
+-----------------+
|          200000 |
+-----------------+
+------------------------+---------+----------+----------+
| Table                  | Op      | Msg_type | Msg_text |
+------------------------+---------+----------+----------+
| easy_mysql.orders_slow | analyze | status   | OK       |
+------------------------+---------+----------+----------+
```

## 6. 实战三：`COUNT(*)` 太慢 —— 三个对策

**对策 1：近似值。** `EXPLAIN` 估的行数就是现成的近似值：

```text
+----+-------------+--------+------------+------+---------------+------+---------+------+--------+----------+-------+
| id | select_type | table  | partitions | type | possible_keys | key  | key_len | ref  | rows   | filtered | Extra |
+----+-------------+--------+------------+------+---------------+------+---------+------+--------+----------+-------+
|  1 | SIMPLE      | orders | NULL       | ALL  | NULL          | NULL | NULL    | NULL | 199430 |   100.00 | NULL  |
+----+-------------+--------+------------+------+---------------+------+---------+------+--------+----------+-------+
+--------------+
| 估算行数 |
+--------------+
|       199430 |
+--------------+
+--------------+
| 精确行数 |
+--------------+
|       200000 |
+--------------+
```

估算 199430、精确 200000，差 570 行 —— 仪表盘、告警够用；对账不行。

**对策 2：汇总表。** 每天一行，小表代替 20 万行：

```sql
CREATE TABLE orders_cnt_daily (
  day DATE NOT NULL PRIMARY KEY,
  total INT NOT NULL
) ENGINE=InnoDB;
INSERT INTO orders_cnt_daily (day, total)
SELECT DATE(created_at), COUNT(*) FROM orders GROUP BY DATE(created_at);
```

```text
+----+-------------+------------------+------------+-------+---------------+---------+---------+-------+------+----------+-------+
| id | select_type | table            | partitions | type  | possible_keys | key     | key_len | ref   | rows | filtered | Extra |
+----+-------------+------------------+------------+-------+---------------+---------+---------+-------+------+----------+-------+
|  1 | SIMPLE      | orders_cnt_daily | NULL       | const | PRIMARY       | PRIMARY | 3       | const |    1 |   100.00 | NULL  |
+----+-------------+------------------+------------+-------+---------------+---------+---------+-------+------+----------+-------+
+----+-------------+--------+------------+-------+---------------------------+---------------------------+---------+------+-------+----------+----------------------------------------+
| id | select_type | table  | partitions | type  | possible_keys             | key                       | key_len | ref  | rows  | filtered | Extra                                  |
+----+-------------+--------+------------+-------+---------------------------+---------------------------+---------+------+-------+----------+----------------------------------------+
|  1 | SIMPLE      | orders | NULL       | range | idx_orders_status_created | idx_orders_status_created | 6       | NULL | 22154 |   100.00 | Using where; Using index for skip scan |
+----+-------------+--------+------------+-------+---------------------------+---------------------------+---------+------+-------+----------+----------------------------------------+
```

| `COUNT(*)` 对策 | 实测耗时 |
|---|---|
| 全表扫一遍 | 24.8 毫秒 |
| 查汇总表（`2024-07-01` 当天 `total=548`） | 0.5 毫秒 |

汇总表 `type=const` 扫 1 行；直接按 `created_at` 数当天，优化器只能用 skip scan 估 22154 行。24.8 → 0.5 毫秒，代价是要维护一张每日刷新的表。

**对策 3：缓存。** 计数放 Redis，定时回源重建。本仓库没接缓存，这条不展开。

## 7. 优化前后对照表

计时方法：`SET @t0 = NOW(6)` → 跑查询 → `TIMESTAMPDIFF(MICROSECOND, @t0, NOW(6))`，每条先暖一遍缓存再计时。没用 `SHOW PROFILES`：它是会话级的环形缓冲（默认只留最近 15 条），官方也已把它标为弃用。本篇所有实测：

| 场景 | 动作 | 优化前 | 优化后 |
|---|---|---|---|
| `amount > 5000` 计数 | 加 `idx_amount` | 33.4 ms | 7.6 ms |
| 深分页（按主键排） | 书签式 `id > 上页末尾` | 15.2 ms | 0.3 ms |
| 深分页（按 `user_id` 排） | 延迟关联 | 101.6 ms | 12.2 ms |
| `status` 过滤 + `ORDER BY amount` | 联合索引 `(status, amount)` | 60.1 ms | 1.4 ms |
| `status` + `user_id` 范围 + 排序 | `FORCE INDEX`（止痛，根治在第 17 篇） | 74.1 ms | 59.5 ms |
| 逐条插入 2000 行 | 攒批到一个事务 | 6803.9 ms | 90.8 ms |
| 全表 `COUNT(*)` | 汇总表 | 24.8 ms | 0.5 ms |

数字都是这一轮真实跑出来的，你机器上会不一样 —— 看数量级和方向，别背数字。

## 8. 别过度优化：先问值不值

本仓库大部分查询本来就在 1 毫秒以下：

| 查询 | 实测耗时 |
|---|---|
| `count_users` | 0.9 毫秒 |
| `count_scores` | 0.5 毫秒 |
| `students北京` | 0.4 毫秒 |
| `students王伟` | 0.3 毫秒 |

给这些查询「优化」，省下的是零点几毫秒，付出的是写入变慢（第 14 篇实测：7 个索引把插入拖慢一个数量级）和改写后的维护成本。动手前问三句：这条 SQL 一天跑几次？用户要等多久？优化的代价谁来付？

**毫秒级、低频的查询，放着不动就是最优解。**

## 三个必须记住的结论

1. **先抓再改**：慢查询日志给出「哪条、多慢、扫了多少」；`Rows_examined / Rows_sent` 比值最难看的那条就是头号嫌疑
2. **每改一步都留下前后对照**：同一条 SQL 优化前后各跑一遍（暖缓存再计时），没有数字的优化不算完成
3. **够用就停**：索引拖慢写入、`FORCE INDEX` 只是止痛；把 0.x 毫秒的查询留着别动

## 常见错误

### ❌ 建索引时名字撞了

```sql
ALTER TABLE orders ADD INDEX idx_amount (amount);
-- 第二次执行：
-- ERROR 1061 (42000): Duplicate key name 'idx_amount'
```

**为什么错**：索引名在一张表内必须唯一 —— 上次加的没删，或者两段脚本用了同一个名字。

**正确做法**：动手前先 `SHOW INDEX FROM orders;` 确认现场；要重来先 `DROP INDEX idx_amount ON orders;`。配套实验是自清理的（临时索引用完即删），所以能反复执行、不会撞名。

## 动手练

- [ ] 对 `lab/queries/16-demo-optimize.sql` 里的 5 条慢 SQL 逐条优化，每条记录优化前后的耗时做成表格
- [ ] 造一条 `Using temporary`：跑 `EXPLAIN SELECT product_id, COUNT(*) FROM orders GROUP BY product_id;`（第 15 篇第 6 节的现场），想清楚是改写还是建索引，再动手验证
- [ ] 开放题：数据涨到 200 万行时，书签式分页还会是 0.3 毫秒吗？（提示：它只碰 10 行，行数涨了碰的还是 10 行 —— 前提是 `id` 递增、且拿得到上一页末尾）

<details>
<summary>第 1 题的答案</summary>

5 条的药方和实测方向（数字都是第 3、4 节跑出来的，你记录的绝对值会不同，方向应该一致）：

| 慢 SQL | 药方 | 实测对照 |
|---|---|---|
| ① `amount > 5000` 计数 | 加 `idx_amount` | `rows` 199430 → 83030；33.4 → 7.6 ms |
| ② 深分页 | 主键排序用书签式 `id > 上页末尾`；任意列排序用延迟关联 | 15.2 → 0.3 ms；101.6 → 12.2 ms |
| ③ `ORDER BY amount` filesort | 联合索引 `(status, amount)` | `Using filesort` 消失；60.1 → 1.4 ms |
| ④ 优化器选错索引 | `FORCE INDEX` 只是止痛，根治在第 17 篇 | 74.1 → 59.5 ms，且 `rows` 估算失真成 1 |
| ⑤ `OR` 一边没索引 | 拆成 `UNION ALL` | 第一分支从全表扫变 29 行索引查找；`amount` 的瓶颈还得靠 ① 的药方 |

</details>

<details>
<summary>第 2 题的答案</summary>

这条是「按商品分组数订单」，**改写没抓手**（没有冗余列、没有别的表可借力），正解是建覆盖索引让分组直接沿着索引序走。实测：

```sql
EXPLAIN SELECT product_id, COUNT(*) FROM orders GROUP BY product_id;
```

```text
+----+-------------+--------+------------+------+---------------+------+---------+------+--------+----------+-----------------+
| id | select_type | table  | partitions | type | possible_keys | key  | key_len | ref  | rows   | filtered | Extra           |
+----+-------------+--------+------------+------+---------------+------+---------+------+--------+----------+-----------------+
|  1 | SIMPLE      | orders | NULL       | ALL  | NULL          | NULL | NULL    | NULL | 199430 |   100.00 | Using temporary |
+----+-------------+--------+------------+------+---------------+------+---------+------+--------+----------+-----------------+
```

```sql
ALTER TABLE orders ADD INDEX idx_product (product_id);
EXPLAIN SELECT product_id, COUNT(*) FROM orders GROUP BY product_id;
-- 演示完就删
ALTER TABLE orders DROP INDEX idx_product;
```

```text
+----+-------------+--------+------------+-------+---------------+-------------+---------+------+--------+----------+-------------+
| id | select_type | table  | partitions | type  | possible_keys | key         | key_len | ref  | rows   | filtered | Extra       |
+----+-------------+--------+------------+-------+---------------+-------------+---------+------+--------+----------+-------------+
|  1 | SIMPLE      | orders | NULL       | index | idx_product   | idx_product | 4       | NULL | 199430 |   100.00 | Using index |
+----+-------------+--------+------------+-------+---------------+-------------+---------+------+--------+----------+-------------+
```

`Using temporary` 没了 —— 分组顺序和索引顺序一致，不用再起临时表排序；`Using index` 表示 `product_id` 一个索引列就把 `SELECT` 和 `GROUP BY` 全覆盖，连回表都省了。但注意 `rows` 还是 199430：**临时表省得掉，全索引扫省不掉** —— 你要数的就是全部行。索引演示完必须 `DROP`，它是拿写入速度换的（第 14 篇量过）。

</details>

<details>
<summary>第 3 题的参考思路</summary>

还会是零点几毫秒这个数量级。书签式 `WHERE id > 上页末尾 ORDER BY id LIMIT 10` 是主键 B+ 树上的范围扫描，**扫描行数恒为 10**（第 4 节的 `EXPLAIN ANALYZE` 里是 `rows=10 loops=1`）；数据涨到 200 万行，树高从 3 层涨到 4 层，每次定位多读一个页面 —— 量级不变。

两个前提要盯住：`id` 得是递增的（自增主键满足）；得拿得到上一页末尾的 `id`。用户直接跳「第 500 页」这种场景书签式用不上，只能回退深分页 —— 所以产品上常见做法是限制可跳转的页数。

</details>

## 配套实验

```powershell
docker cp lab/queries/16-demo-optimize.sql easy-mysql:/tmp/
docker exec easy-mysql mysql -uroot -peasy123 -t -e "source /tmp/16-demo-optimize.sql"
```

> 实验按「抓 → 分析 → 开方 → 验证」四步走，全程自清理：临时索引（`idx_amount`、`idx_status_amount`）跑完即删、插入的 4000 行删净、存储过程 DROP、`long_query_time` 恢复原值，末尾有全表行数和 `SHOW INDEX` 自检。

## 下一篇

[17 · 联合索引与最左前缀：三个字段只建一个索引](17-composite-index.md)
