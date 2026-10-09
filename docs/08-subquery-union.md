# 08 · 子查询与 UNION：让 SQL 嵌套起来

> **一句话价值**：学会「用查询的结果当条件」，并知道把多个结果竖着摞起来时该选 UNION 还是 UNION ALL。

**难度**：⭐⭐⭐　|　**时长**：约 30 分钟　|　**涉及表**：`users`、`orders`、`students`、`scores`

## 什么时候你会遇到它

产品说：「给下过单的用户发张券」。你打开 `users` 表翻了一遍 —— 没有 `has_order` 这种字段，「谁下过单」这件事只写在另一张表里。

这时候你需要把**另一张表查出来的结果**当条件用，这就是子查询。它不是炫技，是没得选。

## 本篇你会学到

- [ ] 标量子查询：括号里放一个只返回**一个值**的查询
- [ ] `IN` / `NOT IN` / `EXISTS` / `NOT EXISTS` 的分工
- [ ] `NOT IN` 遇到 NULL 会整条查询吞掉（实测）
- [ ] 派生表：`FROM (子查询)`，把查询结果当表用
- [ ] `UNION`（去重）与 `UNION ALL`（不去重）的代价差在哪
- [ ] 综合实战：找出订单数超过所在城市平均订单数的用户

## 正文

### 1. 标量子查询：把一个值塞进条件

「高于平均分的成绩有哪些？」平均分得先算，而算出来的是**一个值** —— 这种塞在括号里、只返回一个值的查询叫**标量子查询**（scalar subquery）：

```sql
SELECT ROUND(AVG(score),2) AS 全校平均分 FROM scores;
```

```text
+-----------------+
| 全校平均分      |
+-----------------+
|           69.97 |
+-----------------+
```

```sql
SELECT student_id, score FROM scores WHERE score > (SELECT AVG(score) FROM scores) LIMIT 5;
```

```text
+------------+-------+
| student_id | score |
+------------+-------+
|          1 | 80.00 |
|          1 | 96.00 |
|          1 | 94.00 |
|          2 | 79.00 |
|          2 | 72.00 |
+------------+-------+
```

执行顺序符合直觉：**先把括号里的算完，再拿这个值去筛外表**。括号里没引用外表任何列，算完就是个固定值 —— 这类叫**非相关子查询**（non-correlated subquery），整个查询只算一次平均分。

标量子查询有个硬前提：**结果只能有一行一列**。拿会返回多行的查询当标量用，MySQL 直接拒绝：

```sql
SELECT id FROM users WHERE id = (SELECT user_id FROM orders);
```

```text
ERROR 1242 (21000) at line 1: Subquery returns more than 1 row
```

所以标量的位置要么放 `AVG` / `COUNT` / `MAX` 这种必然聚合成一个值的查询，要么自己加 `LIMIT 1` 截成一行。要是需求本来就是「一堆值里有没有我」，那就别硬套标量，用下一节的 `IN`。

### 2. IN：把一整列当条件

回到开头的需求。先看数据长什么样：

```sql
SELECT COUNT(DISTINCT user_id) AS 下过单的用户数, COUNT(*) AS 订单数 FROM orders;
```

```text
+-----------------------+-----------+
| 下过单的用户数        | 订单数    |
+-----------------------+-----------+
|                  5000 |    200000 |
+-----------------------+-----------+
```

```sql
SELECT COUNT(*) AS IN查到的用户数 FROM users
WHERE id IN (SELECT DISTINCT user_id FROM orders);
```

```text
+----------------------+
| IN查到的用户数       |
+----------------------+
|                 5000 |
+----------------------+
```

5000 = `users` 的全部行数 —— **本库每个用户都下过单**，所以这条查询等于没筛。数据长这样，不是 SQL 写错了；反过来看「没有订单的用户」：

```sql
SELECT COUNT(*) AS 没有订单的用户数 FROM users u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
```

```text
+--------------------------+
| 没有订单的用户数         |
+--------------------------+
|                        0 |
+--------------------------+
```

换个真有筛选效果的例子 —— **有不及格成绩的学生**：

```sql
SELECT COUNT(*) AS 有不及格的学生数 FROM students
WHERE id IN (SELECT student_id FROM scores WHERE score < 60);
```

```text
+--------------------------+
| 有不及格的学生数         |
+--------------------------+
|                      197 |
+--------------------------+
```

`IN` 的意思是「我的值出现在你这堆结果里」。子查询里写不写 `DISTINCT` 都行 —— `IN` 只关心**有没有**，不关心你给了几遍。

`IN` 和 `EXISTS` 的另一个差别藏在 NULL 上：`x IN (..., NULL)` 只要你的值不在这堆里，结果就是「不知道」而不是「假」，`NOT IN` 再把这个「不知道」取反，整行就都筛不掉了 —— 下面 3 变 0 的实验正是这么来的。`EXISTS` 只问「能不能查到一行」，子查询里有没有 NULL 与它无关，所以判断「存在 / 不存在」时它天生不怕 NULL。

> 📌 `NOT IN` 有个要命的脾气：子查询里只要混进**一个 NULL**，整条查询一行都不返回。因为 `x NOT IN (..., NULL)` 的结果永远是「不知道」，而不是「真」。实测：

```sql
-- 正常：3 个学生全科及格，一个不及格的都没有
SELECT COUNT(*) FROM students WHERE id NOT IN (SELECT student_id FROM scores WHERE score < 60);
-- 手动往子查询里塞一个 NULL
SELECT COUNT(*) FROM students WHERE id NOT IN (SELECT student_id FROM scores WHERE score < 60 UNION SELECT NULL);
```

```text
+------------+
| COUNT(*)   |
+------------+
|          3 |
+------------+
+------------+
| COUNT(*)   |
+------------+
|          0 |
+------------+
```

3 变 0，不报错、不警告。**生产上要排除数据，优先 `NOT EXISTS`。**

### 3. EXISTS：逐行去右表探一下

同一需求换个写法：

```sql
SELECT COUNT(*) AS EXISTS版学生数 FROM students s
WHERE EXISTS (SELECT 1 FROM scores sc WHERE sc.student_id = s.id AND sc.score < 60);
```

```text
+--------------------+
| EXISTS版学生数     |
+--------------------+
|                197 |
+--------------------+
```

结果和 `IN` 一字不差（197）。语义不同：`IN` 是「我的值在你这堆里」，`EXISTS` 是「你能查到一行，我就算真」——它不关心查到什么，所以子查询里常写 `SELECT 1`。写 `SELECT sc.id` 结果也一样，`EXISTS` 从不看这列的值，只看有没有行返回。

网上流传「EXISTS 一定比 IN 快」，在 MySQL 8 上得打个问号。两条各 `EXPLAIN` 一次：

```sql
EXPLAIN SELECT id FROM users WHERE id IN (SELECT user_id FROM orders);
```

```text
+----+-------------+--------+------------+-------+-----------------+-----------------+---------+---------------------+------+----------+--------------------------------+
| id | select_type | table  | partitions | type  | possible_keys   | key             | key_len | ref                 | rows | filtered | Extra                          |
+----+-------------+--------+------------+-------+-----------------+-----------------+---------+---------------------+------+----------+--------------------------------+
|  1 | SIMPLE      | users  | NULL       | index | PRIMARY         | uk_users_email  | 242     | NULL                | 5070 |   100.00 | Using index                    |
|  1 | SIMPLE      | orders | NULL       | ref   | idx_orders_user | idx_orders_user | 8       | easy_mysql.users.id |   41 |   100.00 | Using index; FirstMatch(users) |
+----+-------------+--------+------------+-------+-----------------+-----------------+---------+---------------------+------+----------+--------------------------------+
```

```sql
EXPLAIN SELECT u.id FROM users u WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
```

```text
+----+-------------+-------+------------+-------+-----------------+-----------------+---------+-------+------+----------+----------------------------+
| id | select_type | table | partitions | type  | possible_keys   | key             | key_len | ref   | rows | filtered | Extra                      |
+----+-------------+-------+------------+-------+-----------------+-----------------+---------+-------+------+----------+----------------------------+
|  1 | SIMPLE      | u     | NULL       | index | PRIMARY         | uk_users_email  | 242     | NULL  | 5070 |   100.00 | Using index                |
|  1 | SIMPLE      | o     | NULL       | ref   | idx_orders_user | idx_orders_user | 8       | easy_mysql.u.id |   41 |   100.00 | Using index; FirstMatch(u) |
+----+-------------+-------+------------+-------+-----------------+-----------------+---------+-------+------+----------+----------------------------+
```

两张执行计划**几乎一模一样**：都是扫 `users` 5070 行（5000 行的实际值 + 估算误差），每个用户拿索引去 `orders` 找 41 行，`FirstMatch` 是 MySQL 把 `IN` 改写成**半连接**（semi join，找到第一条匹配就停）的标记。**MySQL 8 会把这两种写法优化到同一个计划上**，选哪个看可读性，别背「谁更快」的口诀。

### 4. 派生表：子查询当表用

子查询不只能塞进 `WHERE`，塞进 `FROM` 里就是一张**派生表**（derived table，也叫临时表）：先算好一张结果，再在外层查它。

```sql
SELECT t.uid AS 用户id, t.cnt AS 订单数
FROM (SELECT user_id AS uid, COUNT(*) AS cnt FROM orders GROUP BY user_id) t
WHERE t.cnt > 100
ORDER BY t.cnt DESC;
```

```text
+----------+-----------+
| 用户id   | 订单数    |
+----------+-----------+
|        2 |     13365 |
|        3 |     13365 |
|        1 |     13364 |
+----------+-----------+
```

20 万单里只有 3 个「下单狂魔」超过 100 单。派生表有两条规矩，先看不守规矩的样子 —— 忘了加别名：

```sql
SELECT * FROM (SELECT 1 AS a);
```

```text
ERROR 1248 (42000) at line 1: Every derived table must have its own alias
```

错误里的 `derived table` 指的就是 `FROM (SELECT ...)` 这一整块，**每一层都要有自己的名字**。

第二条规矩是**条件放在哪一层**。上面那条是「先聚合，外层再用 `WHERE` 筛」；也可以把条件留在里层，分组时就筛掉：

```sql
SELECT t.uid AS 用户id, t.cnt AS 订单数
FROM (SELECT user_id AS uid, COUNT(*) AS cnt FROM orders GROUP BY user_id HAVING cnt > 100) t
ORDER BY t.cnt DESC;
```

```text
+----------+-----------+
| 用户id   | 订单数    |
+----------+-----------+
|        2 |     13365 |
|        3 |     13365 |
|        1 |     13364 |
+----------+-----------+
```

两种结果一样，但**行是在聚合结束的那一刻定型的** —— 聚合完还想再筛，用外层 `WHERE` 是常规写法，`HAVING` 留给「分组的时候就要」的条件。

派生表写起来随意，代价却落在优化器那边：MySQL 8 会判断这块结果是**直接合并**进外层查询，还是先**物化**（materialize）成一张临时表再查，物化时还可能顺手给它建索引。这个选择你控制不了，能控制的只有两件事 —— 里面少算一点（早点 `GROUP BY`、早点 `HAVING`），外面筛得准一点（`WHERE` 尽量压在索引列上）。

### 5. UNION vs UNION ALL：先想清楚要不要去重

把两个查询的结果**竖着摞起来**，列数、列类型必须对得上：

```sql
SELECT COUNT(*) AS 去重后 FROM (
  SELECT city FROM students GROUP BY city
  UNION
  SELECT city FROM users GROUP BY city) t;

SELECT COUNT(*) AS 不去重 FROM (
  SELECT city FROM students GROUP BY city
  UNION ALL
  SELECT city FROM users GROUP BY city) t;
```

```text
+-----------+
| 去重后    |
+-----------+
|         6 |
+-----------+
+-----------+
| 不去重    |
+-----------+
|        12 |
+-----------+
```

学生那边 6 个城市，用户那边也是这 6 个 —— `UNION` 把重复的合并成 6 行，`UNION ALL` 老老实实摞成 12 行。代价差在动作上：**`UNION` 必须先收齐全部结果、再判断哪些重复（排序或建哈希表），`UNION ALL` 收到就往外吐**。

**判断标准一句话：明知两段不会重复，或者重复了也无所谓，就用 `UNION ALL`。** 唯一要小心的是 `UNION ALL` 不保证输出顺序，要排序自己写 `ORDER BY`（写在最后，对整个合并结果生效）。

`ORDER BY` 的位置不是习惯问题，是语法问题 —— 写在第一段里直接报错：

```sql
SELECT city FROM students GROUP BY city ORDER BY city DESC LIMIT 3 UNION SELECT city FROM users GROUP BY city;
```

```text
ERROR 1064 (42000) at line 1: You have an error in your SQL syntax; check the manual that corresponds to your MySQL server version for the right syntax to use near 'UNION SELECT city FROM users GROUP BY city' at line 1
```

另一条规矩是**各段的列数必须一样，列名以第一段为准**，后面的列按类型合并规则转换。所以两段最好一开始就选同类的列，别一段扔 id、一段扔用户名，合并出来的类型不见得是你要的。

### 6. 综合实战：订单数超过所在城市平均订单数的用户

套路题，拆成两步。先看每个城市的人均订单数：

```sql
SELECT city, ROUND(AVG(cnt),2) AS 人均订单数, COUNT(*) AS 有单用户数
FROM (SELECT u.city, o.user_id, COUNT(*) AS cnt
      FROM users u JOIN orders o ON o.user_id = u.id
      GROUP BY u.city, o.user_id) t
GROUP BY city ORDER BY 人均订单数 DESC;
```

```text
+--------+-----------------+-----------------+
| city   | 人均订单数      | 有单用户数      |
+--------+-----------------+-----------------+
| 广州   |           48.35 |             813 |
| 杭州   |           47.91 |             851 |
| 北京   |           47.86 |             836 |
| 上海   |           32.03 |             826 |
| 深圳   |           31.95 |             815 |
| 成都   |           31.91 |             859 |
+--------+-----------------+-----------------+
```

两个派生表拼起来：一张是「每个用户的订单数」，一张是「每个城市的平均订单数」，再让两边的 `city` 对上：

```sql
SELECT u.id, u.username, u.city, t.cnt AS 订单数, a.城市平均
FROM (SELECT user_id, COUNT(*) AS cnt FROM orders GROUP BY user_id) t
JOIN users u ON u.id = t.user_id
JOIN (SELECT city, AVG(cnt) AS 城市平均
      FROM (SELECT user_id, COUNT(*) AS cnt FROM orders GROUP BY user_id) x
      JOIN users u2 ON u2.id = x.user_id
      GROUP BY city) a ON a.city = u.city
WHERE t.cnt > a.城市平均
ORDER BY t.cnt DESC LIMIT 5;
```

```text
+------+------------+--------+-----------+--------------+
| id   | username   | city   | 订单数    | 城市平均     |
+------+------------+--------+-----------+--------------+
|    2 | user_00002 | 广州   |     13365 |      48.3481 |
|    3 | user_00003 | 北京   |     13365 |      47.8612 |
|    1 | user_00001 | 杭州   |     13364 |      47.9119 |
|  874 | user_00874 | 广州   |        54 |      48.3481 |
| 3542 | user_03542 | 深圳   |        52 |      31.9546 |
+------+------------+--------+-----------+--------------+
```

这样的用户有多少？把最后的 `LIMIT 5` 换成 `COUNT(*)`：

```sql
SELECT COUNT(*) AS 超过城市平均的用户数 FROM (
  SELECT user_id, COUNT(*) AS cnt FROM orders GROUP BY user_id) t
JOIN users u ON u.id = t.user_id
JOIN (SELECT city, AVG(cnt) AS 城市平均
      FROM (SELECT user_id, COUNT(*) AS cnt FROM orders GROUP BY user_id) x
      JOIN users u2 ON u2.id = x.user_id
      GROUP BY city) a ON a.city = u.city
WHERE t.cnt > a.城市平均;
```

```text
+--------------------------------+
| 超过城市平均的用户数           |
+--------------------------------+
|                           1245 |
+--------------------------------+
```

这道题的骨架值得记下来：**先各自算好，再按公共字段对上，最后筛**。两个派生表互不引用外表的列，各自只算一次，都属于非相关子查询，代价比让内层牵着外表走低得多。

同一套骨架换个字段就是那道经典面试题 —— 「余额不低于所在城市平均」：

```sql
SELECT u.id, u.username, u.balance, u.city
FROM users u
WHERE u.balance >= (SELECT AVG(u2.balance) FROM users u2 WHERE u2.city = u.city)
ORDER BY u.balance DESC LIMIT 5;
```

```text
+------+------------+---------+--------+
| id   | username   | balance | city   |
+------+------------+---------+--------+
| 4222 | user_04222 | 9999.92 | 上海   |
| 3796 | user_03796 | 9995.44 | 上海   |
| 4916 | user_04916 | 9994.27 | 北京   |
| 3729 | user_03729 | 9992.02 | 上海   |
| 2584 | user_02584 | 9988.14 | 深圳   |
+------+------------+---------+--------+
```

**「和自己所属分组的平均值比」** —— 子查询里带了外表的列（`u2.city = u.city`），它就变成了**相关子查询**（correlated subquery）：外表每换一行，内层就要重算一次。表越大代价越大，所以能像上面那样**提前算好**（派生表）的，就别让它相关。

## 三个必须记住的结论

1. **子查询就是「先算一块，再拿来用」**：放 `WHERE` 括号里是一个值（标量），配 `IN`/`EXISTS` 是一列，放 `FROM` 后面是一张表（派生表）
2. **`IN` 看值，`EXISTS` 看有没有行**；MySQL 8 常把两者优化成同一个计划，别迷信「EXISTS 更快」，但**排除数据请用 `NOT EXISTS`**——`NOT IN` 会被一个 NULL 干掉
3. **`UNION` 去重、`UNION ALL` 不去重**：明知不重复就用 `ALL`，省掉一次排序/哈希，也省掉「结果莫名少几行」的困惑

## 常见错误

### ❌ 直接在 `IN` 的子查询里写 `LIMIT`

```sql
-- ERROR 1235 (42000): This version of MySQL doesn't yet support 'LIMIT & IN/ALL/ANY/SOME subquery'
SELECT id, username FROM users WHERE id IN (SELECT user_id FROM orders LIMIT 5);
```

真实报错原文：

```text
ERROR 1235 (42000) at line 1: This version of MySQL doesn't yet support 'LIMIT & IN/ALL/ANY/SOME subquery'
```

**为什么错**：MySQL 不允许在 `IN`/`ALL`/`ANY` 这类子查询里直接带 `LIMIT`，8.0 到现在也没放开。而且这里你八成本来就不需要它 —— `IN` 只关心「在不在」，你把子查询截成 5 行，反而可能漏掉人。

**正确做法**：去掉 `LIMIT`。

```sql
SELECT id, username FROM users WHERE id IN (SELECT user_id FROM orders) LIMIT 5;
```

```text
+----+------------+
| id | username   |
+----+------------+
|  1 | user_00001 |
|  2 | user_00002 |
|  3 | user_00003 |
|  4 | user_00004 |
|  5 | user_00005 |
+----+------------+
```

（外层的 `LIMIT 5` 是对最终结果截断，随便用；不能用的只是写在 `IN` 括号里的那个。）

## 动手练

- [ ] 找出「有订单、但最近 90 天没有下单」的用户
- [ ] 用两种写法（JOIN 版 / 子查询版）实现「有订单的用户」，对比可读性
- [ ] 想一想：第 6 节把 `WHERE t.cnt > a.城市平均` 改成 `HAVING` 会怎样？先说结论，再跑一遍验证

<details>
<summary>第 1 题的答案</summary>

以数据里最后一单（`2024-12-30`）当「今天」，`EXISTS` 要有单、`NOT EXISTS` 排除最近 90 天的单：

```sql
SELECT COUNT(*) AS 老用户数 FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id)
  AND NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id
                  AND o.created_at >= (SELECT MAX(created_at) - INTERVAL 90 DAY FROM orders));
```

```text
+--------------+
| 老用户数     |
+--------------+
|            3 |
+--------------+
```

只有 3 个 —— 本库订单全都压在 2024 一年里，最后 90 天基本人人都有单。**先看数据分布，再下结论。**
</details>

<details>
<summary>第 2 题的答案</summary>

```sql
-- IN 版
SELECT id, username FROM users
WHERE id IN (SELECT user_id FROM (SELECT DISTINCT user_id FROM orders) t) LIMIT 5;

-- JOIN 版
SELECT u.id, u.username FROM users u
JOIN (SELECT DISTINCT user_id FROM orders) t ON t.user_id = u.id LIMIT 5;
```

两种写法输出完全一样（都是 `user_00001` 到 `user_00005`）。本机实测都是 0.02~0.05 秒。**IN 把需求翻译成「值在不在」，JOIN 翻译成「两行配不配」——你跟需求哪个更像就用哪个。**
</details>

<details>
<summary>第 3 题的答案</summary>

不会报错，实测返回**一模一样的 5 行**：

```sql
SELECT u.id, u.username, u.city, t.cnt AS 订单数, a.城市平均
FROM (SELECT user_id, COUNT(*) AS cnt FROM orders GROUP BY user_id) t
JOIN users u ON u.id = t.user_id
JOIN (SELECT city, AVG(cnt) AS 城市平均
      FROM (SELECT user_id, COUNT(*) AS cnt FROM orders GROUP BY user_id) x
      JOIN users u2 ON u2.id = x.user_id
      GROUP BY city) a ON a.city = u.city
HAVING t.cnt > a.城市平均
ORDER BY t.cnt DESC LIMIT 5;
```

```text
+------+------------+--------+-----------+--------------+
| id   | username   | city   | 订单数    | 城市平均     |
+------+------------+--------+-----------+--------------+
|    2 | user_00002 | 广州   |     13365 |      48.3481 |
|    3 | user_00003 | 北京   |     13365 |      47.8612 |
|    1 | user_00001 | 杭州   |     13364 |      47.9119 |
|  874 | user_00874 | 广州   |        54 |      48.3481 |
| 3542 | user_03542 | 深圳   |        52 |      31.9546 |
+------+------------+--------+-----------+--------------+
```

但这属于 MySQL 对「没有 `GROUP BY` 却写了 `HAVING`」的宽松处理：`HAVING` 的本义是**筛分组**，这个查询外层根本没分组。**规则就一条：对聚合完的派生表再筛一层，用 `WHERE`。**
</details>

## 配套实验

```powershell
docker cp lab/queries/08-demo-subquery.sql easy-mysql:/tmp/
docker exec easy-mysql mysql -uroot -peasy123 -t -e "source /tmp/08-demo-subquery.sql"
```

> 全程只读，不改任何数据。

## 下一篇

[09 · 函数速查：日期、字符串与 NULL 的处理](09-functions.md)
