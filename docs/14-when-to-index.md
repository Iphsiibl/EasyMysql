# 14 · 哪些该建索引，哪些不该：一张决策表

> **一句话价值**：拿到一个字段，能立刻判断该不该给它建索引、建成什么类型。

**难度**：⭐⭐⭐　|　**时长**：约 30 分钟　|　**涉及表**：`orders`、`orders_slow`、`students`

## 什么时候你会遇到它

你给表的每个字段都加了索引，结果表膨胀到 2 倍，`INSERT` 慢了一截，`EXPLAIN` 显示 `key = NULL` 索引根本没用上。

该建的没建，不该建的建了一堆。这篇给你一张能直接套的决策表。

## 本篇你会学到

- [ ] 该建索引的三类字段：主键、外键、WHERE/ORDER BY 里反复出现的字段
- [ ] **不该建**的情况（低区分度字段、写多读少的表）
- [ ] 联合索引的顺序为什么重要（最左前缀）
- [ ] 索引失效的 8 种写法（背下来能省很多时间）
- [ ] 索引不是越多越好：真实的取舍演示

---

## 1. 主菜：`status` 到底要不要建索引

先问数据自己。`orders` 表的 `status` 一共 4 个值，每个值正好占四分之一：

```sql
SELECT status, COUNT(*) AS cnt FROM orders GROUP BY status;
```

```text
+-----------+-------+
| status    | cnt   |
+-----------+-------+
| created   | 50000 |
| paid      | 50000 |
| shipped   | 50000 |
| cancelled | 50000 |
+-----------+-------+
```

`orders` 上确实有一个以 `status` 打头的索引，用它查一次：

```sql
EXPLAIN SELECT * FROM orders WHERE status = 'paid';
```

```text
+----+-------------+--------+------------+------+---------------------------+---------------------------+---------+-------+-------+----------+-----------------------+
| id | select_type | table  | partitions | type | possible_keys             | key                       | key_len | ref   | rows  | filtered | Extra                 |
+----+-------------+--------+------------+------+---------------------------+---------------------------+---------+-------+-------+----------+-----------------------+
|  1 | SIMPLE      | orders | NULL       | ref  | idx_orders_status_created | idx_orders_status_created | 1       | const | 95652 |   100.00 | Using index condition |
+----+-------------+--------+------------+------+---------------------------+---------------------------+---------+-------+-------+----------+-----------------------+
```

`type = ref`、`key` 也真的用上了，看起来很美 —— 但盯住 **`rows = 95652`**：全表 199430 行，这条查询要读**一半**。

换个字段对照：

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

同样是 `ref`，一个读 95652 行，一个读 29 行。

**判断该不该建索引，别问「这个字段常不常用」，看 `EXPLAIN` 的 `rows` 读出来是多少。** `status` 单独建索引，只是把「全表扫」换成「扫半张表」，空间还白花了。但它待在联合索引里当第一列依然有用（第 5 节）。

## 2. 区分度：一个除法决定建不建

**区分度（selectivity）** = `COUNT(DISTINCT 列) / COUNT(*)`，越接近 1 越值得建。`orders` 六个字段一次算完：

```sql
SELECT 'user_id' AS 字段, COUNT(DISTINCT user_id) AS 不同值, COUNT(*) AS 总行数,
       ROUND(COUNT(DISTINCT user_id)/COUNT(*),4) AS 区分度 FROM orders
UNION ALL SELECT 'product_id', COUNT(DISTINCT product_id), COUNT(*),
       ROUND(COUNT(DISTINCT product_id)/COUNT(*),4) FROM orders
UNION ALL SELECT 'status', COUNT(DISTINCT status), COUNT(*),
       ROUND(COUNT(DISTINCT status)/COUNT(*),4) FROM orders
UNION ALL SELECT 'quantity', COUNT(DISTINCT quantity), COUNT(*),
       ROUND(COUNT(DISTINCT quantity)/COUNT(*),4) FROM orders
UNION ALL SELECT 'amount', COUNT(DISTINCT amount), COUNT(*),
       ROUND(COUNT(DISTINCT amount)/COUNT(*),4) FROM orders
UNION ALL SELECT 'created_at', COUNT(DISTINCT created_at), COUNT(*),
       ROUND(COUNT(DISTINCT created_at)/COUNT(*),4) FROM orders;
```

| 字段 | 不同值 | 总行数 | 区分度 | 值不值得单独建 |
|---|---:|---:|---:|---|
| `user_id` | 5000 | 200000 | 0.0250 | ✅ 一个值平均 40 行，`user_id=42` 只有 29 行 |
| `product_id` | 1000 | 200000 | 0.0050 | ⚠️ 一个值平均 200 行，看查询命中多少 |
| `status` | 4 | 200000 | 0.0000 | ❌ 一个值 5 万行（第 1 节实测 95652） |
| `quantity` | 5 | 200000 | 0.0000 | ❌ 同上 |
| `amount` | 163138 | 200000 | 0.8157 | ✅ 几乎不重复，适合等值和范围 |
| `created_at` | 200000 | 200000 | 1.0000 | ✅ 天生的时间范围列（但别拿函数包它，第 9 篇讲过） |

分界线不用背精确数字，记住方向：**接近 1 放心建，接近 0 别单独建**。

## 3. 反例实测：把 7 个字段全加上索引

`orders_slow` 和 `orders` 是双胞胎，唯一区别是它一个二级索引都没有。把 7 个非主键字段**全部**加上索引，看代价：

```sql
ALTER TABLE orders_slow
  ADD INDEX idx_i_user (user_id), ADD INDEX idx_i_product (product_id),
  ADD INDEX idx_i_quantity (quantity), ADD INDEX idx_i_amount (amount),
  ADD INDEX idx_i_status (status), ADD INDEX idx_i_created (created_at),
  ADD INDEX idx_i_updated (updated_at);
```

| `orders_slow` | 只有主键 | 7 个索引全加上 |
|---|---:|---:|
| 表体积（KB） | 12816 | 45184 |
| 插入 2000 行（毫秒，本机实测） | 60.4 | 737.5 |

体积变成 **3.5 倍**，插入从几十毫秒涨到几百毫秒 —— **差一个数量级**（耗时随机器变化，你跑出来数字不会和我一样，记住数量级就行）。

而且这 7 个索引不是都有用。索引加满后再查 `status`：

```sql
EXPLAIN SELECT * FROM orders_slow WHERE status = 'paid';
```

```text
+----+-------------+-------------+------------+------+---------------+--------------+---------+-------+-------+----------+-----------------------+
| id | select_type | table       | partitions | type | possible_keys | key          | key_len | ref   | rows  | filtered | Extra                 |
+----+-------------+-------------+------------+------+---------------+--------------+---------+-------+-------+----------+-----------------------+
|  1 | SIMPLE      | orders_slow | NULL       | ref  | idx_i_status  | idx_i_status | 1       | const | 97212 |   100.00 | Using index condition |
+----+-------------+-------------+------------+------+---------------+--------------+---------+-------+-------+----------+-----------------------+
```

`rows = 97212`：索引"用上了"，照样读半张表 —— **白花的空间，没换来等比例的读取**。实验文件最后把 7 个索引全 `DROP` 掉，体积回到 12816 KB、行数还是 200000。

## 4. 索引失效的 8 种写法

下面每一条都跑了「错误写法 + 正确写法」两次 `EXPLAIN`，完整输出在配套实验第 4 节。先放最有代表性的两组原文。

**① 在索引列上套函数**（`YEAR(created_at) = 2024` 那个坑，第 9 篇讲过它为什么慢，这里看索引的下场）：

```sql
ALTER TABLE orders ADD INDEX idx_tmp_created (created_at);
EXPLAIN SELECT * FROM orders WHERE DATE(created_at) = '2024-07-01';
EXPLAIN SELECT * FROM orders WHERE created_at >= '2024-07-01' AND created_at < '2024-07-02';
ALTER TABLE orders DROP INDEX idx_tmp_created;
```

```text
|  1 | SIMPLE | orders | NULL | ALL  | NULL          | NULL | NULL    | NULL | 199430 |   100.00 | Using where |   ← 套函数：索引整个作废
|  1 | SIMPLE | orders | NULL | range | idx_tmp_created | idx_tmp_created | 5  | NULL |    548 |   100.00 | Using index condition |  ← 改成范围：199430 → 548
```

**⑤ `OR` 连了没索引的列，整条查询跟着陪葬**：

```sql
EXPLAIN SELECT * FROM orders WHERE user_id = 42 OR amount > 5000;
EXPLAIN SELECT id, user_id, amount FROM orders WHERE user_id = 42
UNION ALL
SELECT id, user_id, amount FROM orders WHERE amount > 5000;
```

```text
+----+-------------+--------+------------+------+-----------------+------+---------+------+--------+----------+-------------+
| id | select_type | table  | partitions | type | possible_keys   | key  | key_len | ref  | rows   | filtered | Extra       |
+----+-------------+--------+------------+------+-----------------+------+---------+------+--------+----------+-------------+
|  1 | SIMPLE      | orders | NULL       | ALL  | idx_orders_user | NULL | NULL    | NULL | 199430 |    33.34 | Using where |
+----+-------------+--------+------------+------+-----------------+------+---------+------+--------+----------+-------------+
+----+-------------+--------+------------+------+-----------------+-----------------+---------+-------+--------+----------+-------------+
| id | select_type | table  | partitions | type | possible_keys   | key             | key_len | ref   | rows   | filtered | Extra       |
+----+-------------+--------+------------+------+-----------------+-----------------+---------+-------+--------+----------+-------------+
|  1 | PRIMARY     | orders | NULL       | ref  | idx_orders_user | idx_orders_user | 8       | const |     29 |   100.00 | NULL        |
|  2 | UNION       | orders | NULL       | ALL  | NULL            | NULL            | NULL    | NULL  | 199430 |    33.33 | Using where |
+----+-------------+--------+------------+------+-----------------+-----------------+---------+-------+--------+----------+-------------+
```

八条一起看（全部实测，`type`/`rows` 摘自 `EXPLAIN` 原始输出）：

| # | 写法 | 错误写法的结果 | 改成 |
|---|---|---|---|
| ① | 列上套函数 `DATE(created_at)='...'` | `ALL`，`rows=199430` | 范围：`>= '...' AND < '...'` → `range`，`rows=548` |
| ② | 列上做运算 `user_id + 1 = 43` | `ALL`，`rows=199430` | 运算挪到常量侧：`user_id = 42` → `ref`，`rows=29` |
| ③ | 隐式转换：字符串列比数字 `students.name = 0` | `ALL`，`key=NULL`，`rows=200` | `name = '王伟'` → `const`，`rows=1`；反过来 `user_id = '42'` 索引还在（常量被转成数字） |
| ④ | 前导模糊 `name LIKE '%伟'` | `ALL`，`key=NULL`，`rows=200` | `name LIKE '王%'` → `range`，`rows=20` |
| ⑤ | `OR` 连没索引的列 | `ALL`，`rows=199430` | `UNION ALL` 拆开，第一个分支 `ref`，`rows=29` |
| ⑥ | `user_id != 42` | `ALL`，`rows=199430`（`filtered=94.30`，要读 94% 的行） | 加 `LIMIT 10` 后变成 `range`，扫到 10 条就停 |
| ⑦ | `user_id NOT IN (42,43)` | `ALL`，`rows=199430` | 反转成 `IN` 覆盖的正向条件 |
| ⑧ | 写法没错，但命中一半行：`status IN ('created','paid')` | `ALL`，`key=NULL`，`filtered=97.96` | 这不是写法问题，是区分度问题（第 1 节） |

两个附赠发现，都在实验文件里：

- `user_id = 42 OR status = 'paid'` —— **两边都有索引，照样 `ALL`**：并集覆盖了大半张表，优化器懒得开索引合并；
- `user_id = 42 OR user_id = 43` —— 同一个索引列上的 `OR` 会被改写成 `IN`，`range`，`rows=53`。

## 5. 联合索引预览：`idx_orders_status_created` 的 6 种查询方式

`(status, created_at)` 这个两列索引，六条查询六种下场（完整 6 个 `EXPLAIN` 见配套实验第 5 节，逐条拆解在第 17 篇）：

| 查询 | `type` | `key_len` | `rows` | 白话 |
|---|---|---:|---:|---|
| ① `status = 'paid'` | `ref` | 1 | 95652 | 用上第 1 列 |
| ② `status = 'paid' AND created_at >= '...'` | `range` | 6 | 51674 | 两列全用上（1+5 字节） |
| ③ `created_at >= '...'`（跳过第 1 列） | `ALL` | NULL | 199430 | **最左前缀断了** |
| ④ `status IN ('paid','shipped')` | `ALL` | NULL | 199430 | 一半的行，优化器直接放弃 |
| ⑤ `status + created_at + user_id = 42` | `ref` | 8 | 29 | 有更便宜的 `idx_orders_user` 就换过去 |
| ⑥ ②再加宽（`IN` + 大范围） | `ALL` | NULL | 199430 | 命中太多行，不如全表扫 |

第 ② 条的原文：

```text
+----+-------------+--------+------------+-------+---------------------------+---------------------------+---------+------+-------+----------+-----------------------+
| id | select_type | table  | partitions | type  | possible_keys             | key                       | key_len | ref  | rows  | filtered | Extra                 |
+----+-------------+--------+------------+-------+---------------------------+---------------------------+---------+------+-------+----------+-----------------------+
|  1 | SIMPLE      | orders | NULL       | range | idx_orders_status_created | idx_orders_status_created | 6       | NULL | 51674 |   100.00 | Using index condition |
+----+-------------+--------+------------+-------+---------------------------+---------------------------+---------+------+-------+----------+-----------------------+
```

`key_len = 6` 是 `status` 的 1 字节加 `created_at` 的 5 字节 —— **两列都在索引里，缺一列就是 `key_len = 1`，跳过第 1 列就是 `key = NULL`**。这就是最左前缀，第 17 篇拿三列索引做完整实验。

## 6. 决策表：拿到一个字段照这张表判断

| 字段 / 场景 | 建不建 | 本篇的实测依据 |
|---|---|---|
| 主键、外键、JOIN 键 | **必建** | `user_id = 42` → `rows=29` |
| WHERE 等值、区分度高（`amount`） | 建 | 区分度 0.8157 |
| 时间范围列（`created_at`） | 建，可进联合索引 | 区分度 1.0000；查询写成范围，别套函数 |
| 低区分度列（`status`、`quantity`） | **不单独建**，放进联合索引 | 单独查 `rows=95652` |
| 写多读少、插入为主的表 | 先别加一堆 | 插入慢一个数量级（第 3 节） |
| 「每个字段都建」 | 不行 | 12816 KB → 45184 KB |

## 三个必须记住的结论

1. **判断依据是 `EXPLAIN` 的 `rows`，不是「这个字段熟不熟」**。索引「被用上」不等于「有用」：`status` 走了索引仍要读 95652 行
2. **区分度 = `COUNT(DISTINCT 列)/COUNT(*)`**：接近 1 放心建，接近 0 别单独建 —— 但它可以当联合索引的第一列或第二列
3. **索引有实打实的代价**：体积 3.5 倍、插入慢一个数量级。加之前先问一句「这个字段真的会被查吗」

## 常见错误

### ❌ 删索引时名字记错了

```sql
-- ERROR 1091 (42000): Can't DROP 'idx_not_exist'; check that column/key exists
ALTER TABLE orders DROP INDEX idx_not_exist;
```

**为什么错**：索引名必须和数据库里的名字一字不差，不是列名、不是你想当然的命名。

**正确做法**：动手前先看一眼真实名字：

```sql
SHOW INDEX FROM orders;
```

## 动手练

- [ ] 计算 `orders` 每个字段的区分度，按第 6 节的决策表判断该不该建（SQL 在配套实验第 3 节）
- [ ] 把 4 种「索引失效」的写法各跑一次 `EXPLAIN`（推荐 ①③④⑤），确认 `type` 变成 `ALL`
- [ ] 想一想：`status` 单独建索引不划算，为什么它当 `(status, created_at)` 的第一列就有用？（提示：对比第 5 节的 ① 和 ③，答案在第 17 篇）

<details>
<summary>最后一题的答案</summary>

因为联合索引里 `status` 负责**定位**：先按 `status='paid'` 跳到那一段，段内 `created_at` 天然有序，所以第 ② 条能 `range` 扫到 `key_len=6`。而单独建 `status` 索引，定位完还是半张表。
</details>

## 配套实验

```powershell
docker cp lab/queries/14-demo-when-to-index.sql easy-mysql:/tmp/
docker exec easy-mysql mysql -uroot -peasy123 -t -e "source /tmp/14-demo-when-to-index.sql"
```

> 每一段实验都会自己清理现场（7 个演示索引、临时索引、插入的行全部恢复），跑完不会影响后面的文章。

## 下一篇

[15 · EXPLAIN：读懂查询计划](15-explain.md)
