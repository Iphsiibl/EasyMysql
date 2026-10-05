# 13 · 索引是什么：扫 19 万行变成扫 29 行

> **一句话价值**：亲眼看着一次查询从"扫 19 万行"变成"扫 29 行"，并搞懂数据库到底少做了什么。

**难度**：⭐⭐⭐　|　**时长**：约 30 分钟　|　**涉及表**：`orders`、`orders_slow`

## 什么时候你会遇到它

你接手的项目里有一条接口要 3 秒，代码一共 5 行 SQL，看哪行都很眼熟。老同事只说了一句「加个索引试试」，你打开 Navicat 敲了一行 `ALTER TABLE`，3 秒变成 0.05 秒。

那一刻很好用，但下次换张表你又懵了。**索引不是咒语，它有明确的机制。** 这篇就是讲机制。

## 本篇你会学到

- [ ] 数据库没有索引时，**到底在干什么**
- [ ] B+ 树为什么能让 20 万行只查 3 次（附可运行的模拟）
- [ ] 聚簇索引、二级索引、回表分别指什么
- [ ] 索引的代价：占多少空间、写入慢多少
- [ ] 一个流传说得最多的误解：「索引就是存了一份数据」

---

## 1. 先做实验，别听我说

这个仓库里有两张**双胞胎表**：

| | `orders` | `orders_slow` |
|---|---|---|
| 字段 | 一模一样 | 一模一样 |
| 行数 | 200000 | 200000 |
| **二级索引** | 有 | **没有** |

跑这四条，看它们差多少：

```sql
SET profiling = 1;
SELECT COUNT(*) FROM orders_slow WHERE user_id = 42;
SELECT COUNT(*) FROM orders_slow WHERE user_id = 42;
SELECT COUNT(*) FROM orders      WHERE user_id = 42;
SELECT COUNT(*) FROM orders      WHERE user_id = 42;
SHOW PROFILES;
```

```text
+----------+------------+-----------------------------------------------------+
| Query_ID | Duration   | Query                                               |
+----------+------------+-----------------------------------------------------+
|        1 | 0.02550500 | SELECT COUNT(*) FROM orders_slow WHERE user_id = 42 |
|        2 | 0.02104400 | SELECT COUNT(*) FROM orders_slow WHERE user_id = 42 |
|        3 | 0.00061700 | SELECT COUNT(*) FROM orders WHERE user_id = 42      |
|        4 | 0.00021750 | SELECT COUNT(*) FROM orders WHERE user_id = 42      |
+----------+------------+-----------------------------------------------------+
```

> **⚠️ 关于这些数字**：`Duration` 会随你的电脑、磁盘、内存变化，**你的数字不会和我一样**。
> 这很正常。真正值得记住的是下面这个**稳定的数字**。

## 2. 少做了什么？问数据库自己

`EXPLAIN` 就是数据库的执行计划，**它会老实交代自己扫了多少行**：

```sql
EXPLAIN SELECT COUNT(*) FROM orders_slow WHERE user_id = 42;
```

```text
+----+-------------+-------------+------------+------+---------------+------+---------+------+--------+----------+-------------+
| id | select_type | table       | partitions | type | possible_keys | key  | key_len | ref  | rows   | filtered | Extra       |
+----+-------------+-------------+------------+------+---------------+------+---------+------+--------+----------+-------------+
|  1 | SIMPLE      | orders_slow | NULL       | ALL  | NULL          | NULL | NULL    | NULL | 199430 |    10.00 | Using where |
+----+-------------+-------------+------------+------+---------------+------+---------+------+--------+----------+-------------+
```

有索引的那张：

```text
+----+-------------+--------+------------+------+-----------------+-----------------+---------+-------+------+----------+-------------+-----+
| id | select_type | table  | partitions | type | possible_keys   | key             | key_len | ref   | rows | filtered | Extra       |
+----+-------------+--------+------------+------+-----------------+-----------------+---------+-------+------+----------+-------------+-----+
|  1 | SIMPLE      | orders | NULL       | ref  | idx_orders_user | idx_orders_user | 8       | const |   29 |   100.00 | Using index |
+----+-------------+--------+------------+------+-----------------+-----------------+---------+-------+------+----------+-------------+-----+
```

只看 3 列，其余第 15 篇再讲：

| | `orders_slow` | `orders` | 白话 |
|---|---|---|---|
| `type` | `ALL` | `ref` | ALL = 全表挨个看，ref = 查目录 |
| `key` | `NULL` | `idx_orders_user` | 用了哪个索引 |
| **`rows`** | **199430** | **29** | **估算要读多少行** |

**这就是全部秘密**：同样一句 `WHERE user_id = 42`，一张表要把 199430 行读出来才知道答案，另一张只要读 29 行。**省下的不是算法，是 I/O。**

## 3. 目录为什么能少读：B+ 树的"层层折半"

想象一本 20 万条的通讯录，你没有目录，只能从第一页翻到第 42 条 —— 200000 次比较。

有目录呢？目录告诉你「第 3 组」，你翻到那一组，目录再告诉你「第 2 小条」，一次一次缩小范围。**每一次查找，候选量除以一个固定的数。**

这个"固定的数"叫分支因子。我们模拟一下（假设每个索引节点能放 1000 个键，每个叶子节点放 100 行）：

```sql
WITH RECURSIVE split AS (
    SELECT 0 AS level, 200000 AS nodes
    UNION ALL
    SELECT level + 1, CEIL(nodes / 100) FROM split WHERE nodes > 1
)
SELECT level AS layer, nodes AS node_count FROM split;
```

```text
+-------+------------+
| layer | node_count |
+-------+------------+
|     0 |     200000 |   ← 一行行真实数据
|     1 |       2000 |   ← 索引节点
|     2 |         20 |   ← 索引节点
|     3 |          1 |   ← 索引节点（根）
+-------+------------+
```

20 万行被压成 3 层索引。**从根走到叶子只要 3 步**，而且最上面那几层常年待在内存里，实际磁盘读往往只有 1 次。

这棵"树"就是 **B+ 树**。你现在只需要记住两件事：

- 它的高度增长极慢：每往下一层，候选量就缩小一个数量级（真实 B+ 树的分支因子在 1000 左右），
  所以表就算有 1 亿行，也只要查 3~4 层
- **叶子和内部节点的区别，第 17 篇讲联合索引时会用到**

## 4. 索引里存了什么：一个常见误解

> ❌ **流传说法**：「索引就是偷偷把整张表又存了一份」

**不是的。** 真实的结构是这样：

```
聚簇索引（PRIMARY，id）           ← 叶子节点上直接挂着整行数据
    1  →  {id=1, user_id=7, amount=99.00, ...}   ← 数据就在这里
    2  →  {id=2, user_id=3, amount=15.50,  ...}
    ...
   20万 →  ...

二级索引（idx_orders_user）        ← 叶子节点上只挂「键 + 主键值」
   3   →  id=842          ← 只有一个地址，没有别的列
   3   →  id=1993
  ...
```

所以查 `WHERE user_id = 42` 时，数据库是这样工作的：

1. **先在二级索引里定位**：找到 `user_id = 42` 对应的 29 个 `id`
2. **再回聚簇索引取数据**：拿这 29 个 `id` 去把 `amount`、`status` 这些索引里没有的列读出来 —— **这一步叫「回表」**

**第 2 步是可以跳过的**：如果你要的列索引里已经有了，MySQL 就直接用索引回答你，
不绕这一圈。这种情况叫**覆盖索引**，`EXPLAIN` 的 `Extra` 里会出现 `Using index`。

回表 29 次不算什么。但如果你的条件命中 5 万行，**回表 5 万次**就成了灾难。
判断有没有回表，看 `EXPLAIN` 的 `Extra` 列：

```sql
-- 要所有列 → 需要回表，Extra 是空的
EXPLAIN SELECT * FROM orders WHERE user_id = 42;

-- 只要索引里就有的列 → 不用回表，Extra 出现 Using index
EXPLAIN SELECT id, user_id FROM orders WHERE user_id = 42;
```

```text
|  1 | SIMPLE | orders | NULL | ref | idx_orders_user | idx_orders_user | 8 | const | 29 | 100.00 | NULL        |  ← 要回表
|  1 | SIMPLE | orders | NULL | ref | idx_orders_user | idx_orders_user | 8 | const | 29 | 100.00 | Using index |  ← 不用回表
```

`Using index` = "覆盖索引" = 索引本身就够回答这个问题。**这也是为什么老手总说「不要无脑 `SELECT *`」** —— 明明索引里现成的数据，非要回表绕一圈。

## 5. 亲手给它建一个

现在把索引加到 `orders_slow` 上，让这对双胞胎彻底变成一样的：

```sql
ALTER TABLE orders_slow ADD INDEX idx_user (user_id);

EXPLAIN SELECT COUNT(*) FROM orders_slow WHERE user_id = 42;
```

```text
|  1 | SIMPLE | orders_slow | NULL | ref | idx_user | idx_user | 8 | const | 29 | 100.00 | Using index |
```

`ALL` 变成 `ref`，`199430` 变成 `29`。本机上这条查询从 **0.02 秒** 变成了 **0.0001 秒**。

顺便看一眼这个索引"值多少钱"。`CARDINALITY` 是**基数**，也就是 MySQL 认为这个索引里有多少个不同的值 —— 优化器做决定时靠的就是这个数字：

```sql
SELECT INDEX_NAME, COLUMN_NAME, CARDINALITY
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = 'easy_mysql' AND TABLE_NAME = 'orders';
```

```text
+---------------------------+-------------+-------------+
| INDEX_NAME                | COLUMN_NAME | CARDINALITY |
+---------------------------+-------------+-------------+
| idx_orders_status_created | status      |           3 |
| idx_orders_status_created | created_at  |      199430 |
| idx_orders_user           | user_id     |        4295 |
| PRIMARY                   | id          |      199430 |
+---------------------------+-------------+-------------+
```

`user_id` 有 4295 个不同的值，**这就是这个索引有用的原因**。
而 `status` 只有 3 个 —— 这样的索引有用吗？第 14 篇回答你。

> 📌 两个细节：
> 1. 联合索引 `idx_orders_status_created` 占了**两行**，因为它建在两个字段上（第 17 篇讲）
> 2. `status` 实际有 4 个值，基数却显示 3 —— 因为**基数是抽样估算的**，不是精确值。
>    把它当"大致参考"就好，别当精确结论。

## 6. 代价：不是白得的

索引是拿**更多存储**换**更少读取**，代价有两块，都是实测：

**空间**（同一份数据，唯一差别是索引）：

```sql
SELECT TABLE_NAME,
       ROUND(DATA_LENGTH/1024)  AS data_kb,
       ROUND(INDEX_LENGTH/1024) AS index_kb,
       ROUND((DATA_LENGTH+INDEX_LENGTH)/1024) AS total_kb
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'easy_mysql' AND TABLE_NAME IN ('orders','orders_slow');
```

```text
+-------------+---------+----------+----------+
| TABLE_NAME  | data_kb | index_kb | total_kb |
+-------------+---------+----------+----------+
| orders      |   12816 |    14336 |    27152 |
| orders_slow |   12816 |        0 |    12816 |
+-------------+---------+----------+----------+
```

**写入**：同样的 2000 行插进同一张表，差别只在于表上有没有那个索引 —— 无索引约 **0.054 秒**，有索引约 **0.065 秒**，慢 **15%~20%**。

还有一个新手常忽略的点：`ALTER TABLE ... ADD INDEX` 本身就花了 **1.14 秒**。20 万行的表要 1 秒，**一个 5 亿行的生产表可能要几个小时** —— 所以加索引要挑时间。

## 三个必须记住的结论

1. **索引省的是 I/O，不是算法**。所以判断索引有没有用，看 `EXPLAIN` 的 `rows`，不要看耗时
2. **索引不等于数据副本**。它只存「键 + 主键」，剩下的要回表取 —— 这就是 `Using index`（覆盖索引）的由来
3. **索引有成本**：空间翻倍、写入慢 15~20%、大表上加索引要很久。加之前先问一句「这个字段真的会被查吗」

## 动手练

- [ ] 在 `orders_slow` 上建索引，重复第 1 节的计时，把你的数字记下来（**你的耗时肯定和我不一样，这正常**）
- [ ] 把索引删掉，再跑一次 `EXPLAIN`，看着 `rows` 变回 199430
- [ ] 建完索引后插 2000 行数据，体会写入的变慢
- [ ] 想一想：`user_id` 上建了索引，为什么查 `user_id = 1` 可能并不快？（提示：跑一下配套实验文件的**第 7 节**，或直接读 [第 14 篇](14-when-to-index.md)）

<details>
<summary>最后一题的答案</summary>

`user_id = 1` 这个用户在本数据集里有 **13364 笔订单**（`user_id` 2、3 号也是这个量级，而 42 号只有 29 笔）。

意思是：用索引定位到 13364 个主键值，然后**回表 13364 次**。索引帮不上多少忙，优化器甚至可能判断"还不如全表扫一遍"。
索引的价值取决于**命中多少行**，这就是**区分度**，下一篇专门讲。
</details>

## 配套实验

```powershell
docker cp lab/queries/13-demo-index.sql easy-mysql:/tmp/
docker exec easy-mysql mysql -uroot -peasy123 -t -e "source /tmp/13-demo-index.sql"
```

> 每一段实验都会自己清理现场（删掉临时索引和测试数据），跑完不会影响后面的文章。

## 下一篇

[14 · 哪些该建索引，哪些不该：一张决策表](14-when-to-index.md)
