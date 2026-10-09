# 15 · EXPLAIN：读懂查询计划

> **一句话价值**：以后遇到慢 SQL，先 `EXPLAIN` 一下，五秒知道问题在哪。

**难度**：⭐⭐⭐　|　**时长**：约 35 分钟　|　**涉及表**：`orders`、`scores`、`order_items`

## 什么时候你会遇到它

`SELECT ...` 跑了 8 秒，你完全不知道它卡在哪。`EXPLAIN` 一下，两行表格告诉你它扫了 20 万行还是只用了索引。

## 本篇你会学到

- [ ] `EXPLAIN` 输出的 12 列各自是什么意思
- [ ] **`type` 列的 8 个值，从好到坏**（`const` → `ref` → `range` → `index` → `ALL`）
- [ ] `rows` 是怎么估算出来的
- [ ] `Extra` 列里最该警惕的三个词：`Using filesort`、`Using temporary`、`Using index`
- [ ] `EXPLAIN FORMAT=JSON` 和 `EXPLAIN ANALYZE`（真跑一遍看实际耗时）

---

## 1. EXPLAIN 怎么用

在 `SELECT` 前面加上 `EXPLAIN` 就行，查询不执行，只给你计划：

```sql
EXPLAIN SELECT * FROM orders WHERE user_id = 42;
```

```text
+----+-------------+--------+------------+------+-----------------+-----------------+---------+-------+------+----------+-------+
| id | select_type | table  | partitions | type | possible_keys   | key             | key_len | ref   | rows | filtered | Extra |
+----+-------------+--------+------------+------+-----------------+-----------------+---------+-------+------+----------+-------+
|  1 | SIMPLE      | orders | NULL       | ref  | idx_orders_user | idx_orders_user | 8       | const |   29 |   100.00 | NULL  |
+----+-------------+--------+------------+------+-----------------+-----------------+---------+-------+------+----------+-------+
```

12 列各自管什么（列序就是 `EXPLAIN` 的输出列序）：

| # | 列名 | 管什么 |
|---:|---|---|
| 1 | `id` | 相同 `id` 的行按顺序执行：1 是最外层，2 是子查询 |
| 2 | `select_type` | `SIMPLE` / `PRIMARY` / `SUBQUERY`，查询是什么类型 |
| 3 | `table` | 这一行在读哪张表（含别名） |
| 4 | `partitions` | 分区号，本库没分区所以全是 `NULL` |
| 5 | `type` | 访问方式，本篇第 3 节的八级表，最重要的列 |
| 6 | `possible_keys` | 优化器考虑过的索引，`NULL` 表示没有可用索引 |
| 7 | `key` | 实际选中的索引，`NULL` 就是没走索引 |
| 8 | `key_len` | 用了联合索引的前几个字节（第 17 篇靠它判断截断） |
| 9 | `ref` | 和谁比：`const` 表示常量，`表名.列` 表示拿前一张表的列来查 |
| 10 | `rows` | **预估**要读多少行，是估算值不是精确值 |
| 11 | `filtered` | 读出来的行里预计有多少百分比能通过 `WHERE` |
| 12 | `Extra` | 额外提示：回表、排序、临时表都写在这里 |

零基础读者先盯 5、7、10 三列：**用什么方式扫（`type`）、用了哪个索引（`key`）、要读多少行（`rows`）**。

## 2. `rows × filtered`：预估是道乘法题

同一条查询，`EXPLAIN` 读出来的信息是连乘关系：

```sql
EXPLAIN SELECT * FROM orders WHERE amount > 5000;
```

```text
+----+-------------+--------+------------+------+---------------+------+---------+------+--------+----------+-------------+
| id | select_type | table  | partitions | type | possible_keys | key  | key_len | ref  | rows   | filtered | Extra       |
+----+-------------+--------+------------+------+---------------+------+---------+------+--------+----------+-------------+
|  1 | SIMPLE      | orders | NULL       | ALL  | NULL          | NULL | NULL    | NULL | 199430 |    33.33 | Using where |
+----+-------------+--------+------------+------+---------------+------+---------+------+--------+----------+-------------+
```

**199430 × 33.33% ≈ 66470**：读 199430 行，其中约 66470 行能通过 `WHERE`。`type=ALL` + 全表行数，这就是「慢」的标准长相。

加个 `LIMIT 10`，扫到 10 行就停：

```text
|  1 | SIMPLE      | orders | NULL       | index | NULL          | PRIMARY | 8       | NULL |   10 |    33.33 | Using where |
```

`rows` 从 199430 掉到 10。再看一例「不用回表」的 —— 要的列都在索引里：

```text
|  1 | SIMPLE      | orders | NULL       | ref  | idx_orders_status_created | idx_orders_status_created | 1       | const | 95652 |   100.00 | Using where; Using index |
```

`Extra` 出现 `Using index` = 覆盖索引（第 13 篇讲的那件事），索引本身就够回答，不回表。

## 3. `type` 八级：本篇最该存下来的一张表

从最好到最差，每一级都在配套实验第 2 节真跑过：

| 等级 | `type` | 含义 | 本库实测 |
|---:|---|---|---|
| 1 | `system` | 表只有 1 行 | 8.0.46 实测没出现（单行表给 `ALL`） |
| 2 | `const` | 主键/唯一索引等值，最多 1 行 | `orders WHERE id = 100` |
| 3 | `eq_ref` | join 时查主键/唯一索引，每行配 1 行 | `o JOIN u ON u.id = o.user_id` |
| 4 | `ref` | 非唯一索引等值 | `orders WHERE user_id = 42` |
| 5 | `range` | 索引范围扫描 | `orders WHERE user_id BETWEEN 40 AND 50` |
| 6 | `index` | 扫完整个二级索引 | `SELECT user_id FROM orders` |
| 7 | `ALL` | 全表扫描，最差 | `orders WHERE amount > 5000` |
| 8 | `NULL` | Select tables optimized away，子查询提前算完 | `WHERE id = (SELECT MAX(id) ...)` |

`eq_ref` 的原文（两张表的计划各占一行，`ref` 列能看出第二行在拿第一行的列去查）：

```text
+----+-------------+-------+------------+--------+-------------------------+---------+---------+----------------------+------+----------+-------------+
| id | select_type | table | partitions | type   | possible_keys           | key     | key_len | ref                  | rows | filtered | Extra       |
+----+-------------+-------+------------+--------+-------------------------+---------+---------+----------------------+------+----------+-------------+
|  1 | SIMPLE      | o     | NULL       | range  | PRIMARY,idx_orders_user | PRIMARY | 8       | NULL                 |  100 |   100.00 | Using where |
|  1 | SIMPLE      | u     | NULL       | eq_ref | PRIMARY                 | PRIMARY | 8       | easy_mysql.o.user_id |    1 |   100.00 | NULL        |
+----+-------------+-------+------------+--------+-------------------------+---------+---------+----------------------+------+----------+-------------+
```

两行的 `id` 都是 1：同一个查询块里的两张表。第二行 `rows = 1`、`ref = easy_mysql.o.user_id` —— 拿 `o.user_id` 去 `users` 主键上查，每行只配 1 行，这是 join 里最理想的形态。

**看 SQL 的习惯：先看 `type` 是不是 `ALL`，再看 `rows` 是不是接近全表行数。** 两个都过了，这条 SQL 基本没大问题。

## 4. 多表查询：每张表各占一行

三表 join，优化器排好的顺序（`u` 全表扫 → 每行查 `o` → 每行查 `i`）：

```sql
EXPLAIN SELECT o.id, i.product_name
FROM users u JOIN orders o ON o.user_id = u.id JOIN order_items i ON i.order_id = o.id
WHERE u.city = '北京' AND o.status = 'paid' AND i.product_name = '显示器';
```

```text
+----+-------------+-------+------------+------+---------------------------------------------------+-----------------+---------+-----------------+------+----------+-------------+
| id | select_type | table | partitions | type | possible_keys                                     | key             | key_len | ref             | rows | filtered | Extra       |
+----+-------------+-------+------------+------+---------------------------------------------------+-----------------+---------+-----------------+------+----------+-------------+
|  1 | SIMPLE      | u     | NULL       | ALL  | PRIMARY                                           | NULL            | NULL    | NULL            | 5070 |    10.00 | Using where |
|  1 | SIMPLE      | o     | NULL       | ref  | PRIMARY,idx_orders_user,idx_orders_status_created | idx_orders_user | 8       | easy_mysql.u.id |   41 |    47.96 | Using where |
|  1 | SIMPLE      | i     | NULL       | ref  | idx_items_order                                   | idx_items_order | 8       | easy_mysql.o.id |    2 |    10.00 | Using where |
+----+-------------+-------+------------+------+---------------------------------------------------+-----------------+---------+-----------------+------+----------+-------------+
```

乘法一路算下去：5070 × 10% ≈ 507 个北京用户 → 每人 41 单、留 47.96% → 每单 2 条明细、留 10%。**`rows` 从上往下连乘，就是优化器对这条查询的全部想象。**

用 `STRAIGHT_JOIN` 强按书写顺序（先查 `orders`）会怎样？配套实验第 4 节跑了：第一行换成 `orders` 走 `idx_orders_status_created` 读 95652 行，`users` 的全表扫被挪到后面 —— **计划顺序真的跟着书写顺序变了，但 `orders` 从每人 41 行变成一次读 95652 行**。优化器默认排的顺序不是随手排的。

## 5. `Using filesort` 是什么

```sql
EXPLAIN SELECT * FROM orders WHERE status = 'paid' ORDER BY amount DESC LIMIT 10;
```

```text
|  1 | SIMPLE      | orders | NULL       | ref  | idx_orders_status_created | idx_orders_status_created | 1       | const | 95652 |   100.00 | Using index condition; Using filesort |
```

**它不是「写到磁盘上排序」**（名字骗人），意思是「`ORDER BY` 的列不在你用的索引里，数据库**没法利用索引里现成的顺序**，得自己再排一次」。要消除它，就把排序列塞进联合索引 —— 第 16、17 篇各给一种做法。

`Extra` 里另外三个词，全部实测：

| `Extra` | 出处（配套实验第 6 节） | 白话 |
|---|---|---|
| `Using index` | `SELECT status, created_at ... WHERE status='paid'` | 覆盖索引，不回表（好事） |
| `Using index condition` | `WHERE status='paid' AND amount > 8000` | 索引下推：先在索引里筛一遍再回表 |
| `Using filesort` | 上面那条 | 排序列不在索引里，自己排 |
| `Using temporary` | `GROUP BY product_id` | 建了临时表分组，`rows=199430` 全表扫 |
| `Backward index scan` | `ORDER BY created_at DESC` | 8.0 反向扫索引，**不是**排序（好事） |
| `Select tables optimized away` | `SELECT MAX(id) FROM orders` | 表都不打开，直接从索引取 |

## 6. 估算不当真：`EXPLAIN ANALYZE` 与 `FORMAT=JSON`

`rows` 是估算，那就真跑一遍看实际值（MySQL 8.0.18+）：

```sql
EXPLAIN ANALYZE SELECT * FROM orders WHERE user_id = 1\G
```

```text
*************************** 1. row ***************************
EXPLAIN: -> Index lookup on orders using idx_orders_user (user_id=1)  (cost=3188 rows=25872) (actual time=2.87..18.7 rows=13364 loops=1)
```

**估算 25872 行，实际 13364 行** —— 差了近一倍（`user_id=1` 是数据倾斜的大用户，第 14 篇讲过）。第二条：

```text
*************************** 1. row ***************************
EXPLAIN: -> Aggregate: count(0)  (cost=26790 rows=1) (actual time=46.5..46.5 rows=1 loops=1)
    -> Filter: (orders.amount > 5000.00)  (cost=20143 rows=66470) (actual time=0.395..44.7 rows=42198 loops=1)
        -> Table scan on orders  (cost=20143 rows=199430) (actual time=0.391..29.7 rows=200000 loops=1)
```

估算 66470，实际 42198。**估算会偏，但量级不会错**（都是「几万行」，没人把它当成 29 行）。

`FORMAT=JSON` 把优化器的账本摊开（`query_cost` 就是它算的总代价）：

```sql
EXPLAIN FORMAT=JSON SELECT * FROM orders WHERE user_id = 42\G
EXPLAIN FORMAT=JSON SELECT COUNT(*) FROM orders WHERE status='paid' AND created_at >= '2024-07-01'\G
```

```text
*************************** 1. row ***************************
EXPLAIN: {
  "query_block": {
    "select_id": 1,
    "cost_info": {
      "query_cost": "10.15"
    },
    "table": {
      "table_name": "orders",
      "access_type": "ref",
      "possible_keys": [
        "idx_orders_user"
      ],
      "key": "idx_orders_user",
      "used_key_parts": [
        "user_id"
      ],
      "key_length": "8",
      "ref": [
        "const"
      ],
      "rows_examined_per_scan": 29,
      "rows_produced_per_join": 29,
      "filtered": "100.00",
      "cost_info": {
        "read_cost": "7.25",
        "eval_cost": "2.90",
        "prefix_cost": "10.15",
        "data_read_per_join": "1K"
      },
      "used_columns": [
        "id",
        "user_id",
        "product_id",
        "quantity",
        "amount",
        "status",
        "created_at",
        "updated_at"
      ]
    }
  }
}
```

第二条的 `query_cost` 是 **10357.10**（第一条 10.15），差一千倍，用的索引是 `idx_orders_status_created`、`key_length=6`、`rows_examined_per_scan=51674`。优化器不傻，它有账本。

**估算什么时候会彻底失真？统计信息过期的时候。** 实验里把 `order_items` 的统计行数改成 0（模拟批量灌完数据还没 `ANALYZE`）：

```text
+-----------------------+
| 过期后估算行数 |
+-----------------------+
|                     0 |
+-----------------------+
+----+-------------+-------+------------+--------+-----------------+-----------------+---------+-----------------------+------+----------+-------------+
| id | select_type | table | partitions | type   | possible_keys   | key             | key_len | ref                   | rows | filtered | Extra       |
+----+-------------+-------+------------+--------+-----------------+-----------------+---------+-----------------------+------+----------+-------------+
|  1 | SIMPLE      | i     | NULL       | index  | idx_items_order | idx_items_order | 8       | NULL                  |    1 |   100.00 | Using index |
|  1 | SIMPLE      | o     | NULL       | eq_ref | PRIMARY         | PRIMARY         | 8       | easy_mysql.i.order_id |    1 |   100.00 | Using index |
+----+-------------+-------+------------+--------+-----------------+-----------------+---------+-----------------------+------+----------+-------------+
```

计划翻转了：先扫「1 行」的明细表。真跑一遍：

```text
EXPLAIN: -> Aggregate: count(0)  (cost=2131 rows=1) (actual time=541..541 rows=1 loops=1)
    -> Nested loop inner join  (cost=2131 rows=1) (actual time=0.0182..515 rows=600000 loops=1)
        -> Covering index scan on i using idx_items_order  (cost=2130 rows=1) (actual time=0.0099..131 rows=600000 loops=1)
        -> Single-row covering index lookup on o using PRIMARY (id=i.order_id)  (cost=0.35 rows=1) (actual time=420e-6..455e-6 rows=1 loops=600000)
```

**估算 1 行，实际扫 600000 行。** 跑完 `ANALYZE TABLE order_items` 把统计算回来，计划立刻翻回原样，数据一行没动过。

## 7. 慢查询日志：把真凶从代码里揪出来

`EXPLAIN` 看单条，慢查询日志（slow query log）负责**记录**哪条慢：

```sql
SHOW VARIABLES LIKE 'slow_query_log';
SHOW VARIABLES LIKE 'long_query_time';
SHOW VARIABLES LIKE 'slow_query_log_file';
SHOW VARIABLES LIKE 'log_output';
```

```text
+----------------+-------+
| Variable_name  | Value |
+----------------+-------+
| slow_query_log | ON    |
+----------------+-------+
+-----------------+----------+
| Variable_name   | Value    |
+-----------------+----------+
| long_query_time | 0.200000 |
+-----------------+----------+
+---------------------+--------------------------------------+
| Variable_name       | Value                                |
+---------------------+--------------------------------------+
| slow_query_log_file | /var/lib/mysql/63cfcab4c3db-slow.log |
+---------------------+--------------------------------------+
+---------------+-------+
| Variable_name | Value |
+---------------+-------+
| log_output    | FILE  |
+---------------+-------+
```

阈值 0.2 秒，日志写文件。把阈值调到 0（只影响当前会话），跑一条重的，再恢复原值 —— 实验文件里 `SET @old_lqt = @@SESSION.long_query_time` 先存、末尾先恢复，不会污染后面的文章。

去容器里看日志（文件名以你上面 `SHOW VARIABLES` 的输出为准）：

```powershell
docker exec easy-mysql tail -n 5 /var/lib/mysql/<容器ID>-slow.log
```

刚才那条真的被记下来了（原文）：

```text
# Time: 2026-10-08T02:56:19.650865Z
# User@Host: root[root] @ localhost []  Id:  1109
# Query_time: 0.463562  Lock_time: 0.000003 Rows_sent: 1  Rows_examined: 800000
SET timestamp=1791428179;
SELECT COUNT(*) FROM orders o JOIN order_items i ON i.order_id = o.id;
```

三个数字最有用：**`Query_time` 花了多少、`Rows_examined` 读了多少、`Rows_sent` 送了多少**。读了 80 万行只送 1 行 —— 读写比这么难看，就是下一条要优化的对象，第 16 篇拿它开刀。

`pt-query-digest` 这个镜像里没装（连 `perl` 都没有），装法和替代的 `grep`/`sort` 用法在第 16 篇第 1 节。

## 三个必须记住的结论

1. **先看 `type`，再看 `rows`**：`type=ALL` 且 `rows` 接近全表行数，这条 SQL 就有问题；`ref` + 两位数 `rows` 基本可以放行
2. **`rows` 是估算，`filtered` 是百分比**，两者相乘才是优化器想象的输出行数；估算会偏（25872 vs 13364），但量级不骗人
3. **`Extra` 三个词决定下一步**：`Using filesort`/`Using temporary` 是要处理的（第 16、17 篇），`Using index` 是该保留的（覆盖索引）

## 常见错误

### ❌ EXPLAIN 的格式名写错了

```sql
-- ERROR 1791 (HY000): Unknown EXPLAIN format name: 'XML'
EXPLAIN FORMAT=XML SELECT * FROM orders WHERE id = 1;
```

**为什么错**：MySQL 只认 `TRADITIONAL`（默认表格）和 `JSON` 两种格式，XML 是别的数据库的概念。

**正确做法**：

```sql
EXPLAIN FORMAT=JSON SELECT * FROM orders WHERE id = 1\G
```

## 动手练

- [ ] 找出一条 `type = ALL` 的 SQL 并优化到 `type = ref`（实验第 3 节里现成的靶子：`WHERE amount > 5000` 想办法让它走索引）
- [ ] 制造一条 `Using filesort` 的 SQL，思考怎么改（答案在第 17 篇）
- [ ] 跑一次 `EXPLAIN ANALYZE`，把你机器上的「估算 vs 实际」记下来 —— 数字和我不一样很正常

<details>
<summary>第一题的提示</summary>

`amount` 没有索引，所以只能 `ALL`。给它建索引后 `type` 变 `range`（第 16 篇第 3 节的慢 SQL ① 用的就是这一招），跑完记得 `DROP INDEX`。
</details>

## 配套实验

```powershell
docker cp lab/queries/15-demo-explain.sql easy-mysql:/tmp/
docker exec easy-mysql mysql -uroot -peasy123 -t -e "source /tmp/15-demo-explain.sql"
```

> 实验里唯一的「破坏性」动作是把 `order_items` 的统计行数改成 0 模拟统计过期，段落结束立刻 `ANALYZE TABLE` 恢复 —— 数据一行都没动，末尾有全表行数自检。

## 下一篇

[16 · 慢查询优化实战：把完整流程走一遍](16-optimize-slow-query.md)
