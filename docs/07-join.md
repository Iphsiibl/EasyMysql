# 07 · JOIN：把学生表和成绩表拼起来

> **一句话价值**：看懂 INNER 和 LEFT 的真正差别，并一次性消灭「一对多 JOIN 把金额算翻倍」这个经典 bug。

**难度**：⭐⭐　|　**时长**：约 35 分钟　|　**涉及表**：`students`、`scores`、`courses`、`orders`、`order_items`

## 什么时候你会遇到它

老师让交一份成绩单：每个学生一行，后面跟着他考的每门课。学生表 200 行，成绩表 2000 行，你写了个 JOIN，跑出来发现**有的学生出现了 10 次，有的学生一条记录都没有**。

这不是数据库坏了，是 INNER 和 LEFT 你还没分清。报表金额莫名其妙翻倍、统计漏掉一批人，八成都是这个坑。

## 本篇你会学到

- [ ] JOIN 的本质：按一个共同字段，把两张表的行拼成一行
- [ ] `INNER JOIN`（两边都有才留）vs `LEFT JOIN`（左边全留，右边补 NULL）
- [ ] **一句话判断法**：你要「有成绩的学生」，还是「所有学生」
- [ ] ON 和 WHERE 的区别——LEFT JOIN 的头号坑
- [ ] 一对多 JOIN 让行数翻倍、金额算错的两种修法
- [ ] 三表连查，以及「驱动表」是什么

## 正文

### 1. 生活中的 JOIN：按学号把两页纸对齐

成绩单和学生名单是两张纸，纸上都有学号。把两张纸按学号对齐、贴在一起，就得到一份完整成绩单 —— **JOIN 干的就是这件事**，`ON` 后面写的就是「按什么对齐」。

```sql
SELECT s.name, sc.score FROM students s JOIN scores sc ON sc.student_id = s.id LIMIT 3;
```

```text
+--------+-------+
| name   | score |
+--------+-------+
| 冯丽   | 83.00 |
| 冯丽   | 89.00 |
| 冯丽   | 78.00 |
+--------+-------+
```

一行行拆开看：

- `students s`：给表起短名 `s`，后面全用短名，省字且不会写错
- `ON sc.student_id = s.id`：对齐条件。成绩表的 `student_id` 必须等于学生表的 `id`，配不上的行不输出
- `JOIN` 不写全称就是 `INNER JOIN`，两者一个意思

配套实验里还跑了另外三种写法（写全 `INNER JOIN`、逗号 + `WHERE` 的老式写法、`STRAIGHT_JOIN`），输出和上面这三行一模一样 —— **挑一种会写的，别在写法上纠结**。

也可以按「找东西」来理解 JOIN：左手捏着一张学生卡，右手在成绩堆里翻学号相同的卡片，翻到就叠成一张，翻不到就看你写的是哪种 JOIN。`ON` 后面能放好几个条件，用 `AND` 串起来，条件越严配上的行越少，但它管的永远只是**相邻两张表**。

还有一句常被忽略的话：**JOIN 本身不决定行数，右表的匹配数才决定**。学生和成绩是一对十，每个学生被复制成 10 行；要是一对零，那一行是消失还是留着补 NULL，就分到了 `INNER` 和 `LEFT` 两条路上。

### 2. 三表 JOIN：一个 ON 只管一对邻居

成绩要连课程名，就是三张表接龙：

```sql
SELECT s.name, c.name AS 课程, sc.score, c.teacher
FROM students s
JOIN scores  sc ON sc.student_id = s.id
JOIN courses  c ON c.id = sc.course_id
LIMIT 10;
```

```text
+--------+-----------------------+-------+---------+
| name   | 课程                  | score | teacher |
+--------+-----------------------+-------+---------+
| 冯丽   | 高等数学              | 83.00 | 张伟    |
| 冯丽   | 大学英语              | 89.00 | 李静    |
| 冯丽   | 数据结构              | 78.00 | 王强    |
| 冯丽   | 计算机网络            | 96.00 | 刘敏    |
| 冯丽   | 操作系统              | 68.00 | 陈磊    |
| 冯丽   | 数据库原理            | 89.00 | 杨洋    |
| 冯丽   | Java 程序设计         | 85.00 | 黄娟    |
| 冯丽   | Python 入门           | 81.00 | 周涛    |
| 冯丽   | 算法设计与分析        | 63.00 | 吴军    |
| 冯丽   | 软件工程              | 63.00 | 徐明    |
+--------+-----------------------+-------+---------+
```

每加一张表就多一个 `ON`，**一条 `ON` 只负责相邻两张表的对齐**，少一个就报错或出脏数据。三表接龙其实就是「先拼两张，再拿结果去拼第三张」，先拼哪两张由优化器决定，你只管把每对邻居的条件写对。另一个小细节：`LIMIT` 必须写在整条语句最后，管的是**最终结果**，不是中间某一步 —— 上面那 10 行是三表全拼完才截断的。冯丽一个人占了 10 行，这是「一对多」的典型长相 —— 200 个学生每人恰好 10 门成绩：

```sql
SELECT COUNT(*) AS 学生数, MIN(c) AS 最少, MAX(c) AS 最多
FROM (SELECT student_id, COUNT(*) c FROM scores GROUP BY student_id) t;
```

```text
+-----------+--------+--------+
| 学生数    | 最少   | 最多   |
+-----------+--------+--------+
|       200 |     10 |     10 |
+-----------+--------+--------+
```

### 3. LEFT JOIN：本篇的主菜

先问需求：**「找出没参加任何考试的学生」**。这类问题的写法是固定的 —— 左表全留，右表配不上的地方用 `IS NULL` 当探针：

```sql
SELECT s.id, s.name
FROM students s
LEFT JOIN scores sc ON sc.student_id = s.id
WHERE sc.id IS NULL;
```

这条在本数据集里**一行都不返回**，屏幕上连表格都不会打。用 `COUNT` 把「0 行」变成看得见的数字：

```sql
SELECT COUNT(*) AS 没考试的学生数
FROM students s LEFT JOIN scores sc ON sc.student_id = s.id
WHERE sc.id IS NULL;
```

```text
+-----------------------+
| 没考试的学生数        |
+-----------------------+
|                     0 |
+-----------------------+
```

**0 行不代表 SQL 写错了**：上一节实测每人恰好 10 门成绩，这 200 人全都考过试。写 LEFT JOIN 之前先摸清数据，比死磕语法有用。

换个等价的问题，同一条 SQL 立刻有结果 —— 20 门课里有 10 门一个学生都没选：

```sql
SELECT c.id, c.name, c.teacher
FROM courses c LEFT JOIN scores sc ON sc.course_id = c.id
WHERE sc.id IS NULL;
```

```text
+----+--------------------------+---------+
| id | name                     | teacher |
+----+--------------------------+---------+
| 11 | 计算机组成原理           | 胡超    |
| 12 | 数字逻辑                 | 朱琳    |
| 13 | 概率论与数理统计         | 高翔    |
| 14 | 线性代数                 | 林峰    |
| 15 | 大学物理                 | 何洁    |
| 16 | 马克思主义原理           | 罗宇    |
| 17 | 中国近现代史纲要         | 梁爽    |
| 18 | 体育                     | 宋丹    |
| 19 | 音乐鉴赏                 | 谢婷    |
| 20 | 机器学习导论             | 韩雪    |
+----+--------------------------+---------+
```

换成 `INNER JOIN` 再数一遍：

```sql
SELECT COUNT(DISTINCT c.id) AS INNER版只剩这么多门课
FROM courses c JOIN scores sc ON sc.course_id = c.id;
```

```text
+-------------------------------+
| INNER版只剩这么多门课         |
+-------------------------------+
|                            10 |
+-------------------------------+
```

那 10 门没人选的课**无声无息地消失了**。这就是两个关键字的全部差别：

| | 右表配上了 | 右表没配上 |
|---|---|---|
| `INNER JOIN` | 输出拼好的行 | 这行直接丢掉 |
| `LEFT JOIN` | 输出拼好的行 | 左表照样输出，右表整行填 NULL |

**判断法只有一句：你要「有成绩的人」（INNER），还是「所有人」（LEFT）。**

拿 NULL 当探针还有个细节：**探针要挑右表里一定有值的列**，主键最稳。这里 `sc.id` 是自增主键，永远非空，拿它当探针不会出错；换成允许 NULL 的业务列就危险了 —— 行明明配上了，可那个字段恰好是 NULL，你会误判成「没配上」。本库 `scores.score` 建表时是 `NOT NULL`，所以两个探针结果相同，但写 `sc.id` 是更保险的习惯。

### 4. ON 和 WHERE：条件放哪不是随便放的

需求：查 95 分以上的成绩，但**所有学生都要在列表里**。同一个条件，放 `ON` 和放 `WHERE` 是两个结果。

**写法 A：条件写在 `ON` 里**

```sql
SELECT COUNT(*) AS 行数, SUM(sc.id IS NULL) AS 其中NULL行
FROM students s LEFT JOIN scores sc ON sc.student_id = s.id AND sc.score >= 95;
```

```text
+--------+---------------+
| 行数   | 其中NULL行    |
+--------+---------------+
|    270 |            65 |
+--------+---------------+
```

**写法 B：条件写在 `WHERE` 里**

```sql
SELECT COUNT(*) AS 行数
FROM students s LEFT JOIN scores sc ON sc.student_id = s.id
WHERE sc.score >= 95;
```

```text
+--------+
| 行数   |
+--------+
|    205 |
+--------+
```

270 = 205 条 95 分以上的成绩 + 65 行 NULL 补位：那 65 个学生一门 95 分以上都没有，右表配不上，于是被 NULL 顶上：

```sql
SELECT s.id, s.name, sc.score
FROM students s LEFT JOIN scores sc ON sc.student_id = s.id AND sc.score >= 95
WHERE sc.id IS NULL LIMIT 3;
```

```text
+-----+-----------+-------+
| id  | name      | score |
+-----+-----------+-------+
| 178 | 冯刚      |  NULL |
| 177 | 冯平      |  NULL |
| 168 | 冯强磊    |  NULL |
+-----+-----------+-------+
```

写法 B 里这 65 个学生**整个人消失了**。原因一句话：`ON` 是**配对阶段**的条件，学生一个不少，只是这次配不上 95 分的成绩；`WHERE` 是**配对完再过滤**，NULL 行过不了 `sc.score >= 95`，被整行删掉 —— LEFT 已经悄悄退化成 INNER。

顺带提醒：把阈值换成 60 分，两种写法都返回 1332 行，一模一样。**看不出差别 ≠ 没写错**，换条数据线立刻露馅，所以别拿「结果对了」证明写法对。

### 5. 重复行：金额被算翻倍的经典 bug

一张订单有 3 条明细，JOIN 之后这张订单就出现 3 次：

```sql
SELECT o.id, o.amount, COUNT(*) AS 出现次数
FROM orders o JOIN order_items i ON i.order_id = o.id
GROUP BY o.id, o.amount
ORDER BY o.id LIMIT 3;
```

```text
+----+---------+--------------+
| id | amount  | 出现次数     |
+----+---------+--------------+
|  1 | 2663.13 |            3 |
|  2 | 8614.25 |            3 |
|  3 | 5518.36 |            3 |
+----+---------+--------------+
```

于是下面这条「前 100 单总额」就是错的：

```sql
-- 错：订单金额被明细重复了 3 遍
SELECT ROUND(SUM(o.amount), 2) AS 错误总额
FROM orders o JOIN order_items i ON i.order_id = o.id
WHERE o.id <= 100;
```

```text
+--------------+
| 错误总额     |
+--------------+
|    774822.33 |
+--------------+
```

```sql
-- 对：订单表本来就有金额，根本不用 JOIN
SELECT ROUND(SUM(amount), 2) AS 正确总额 FROM orders WHERE id <= 100;
```

```text
+--------------+
| 正确总额     |
+--------------+
|    258274.11 |
+--------------+
```

正好 3 倍（本库每单恰好 3 条明细）。**`SUM` 没变笨，是输入的行变多了** —— 它照规矩把见到的每一行都加了一遍。规律可以写成一行：**JOIN 后的行数 = 左表每行 × 它在右表配上的行数**，`o.id <= 100` 的 100 单 JOIN 明细实测就是 300 行。两种修法：

1. **不要 JOIN**：要的字段左表本来就有，就别去招惹右表
2. **必须 JOIN**：先把「多」的那侧聚合成一行，再去拼

判断要不要 JOIN 还有条最省事的防线：看看 `SELECT` 后面到底有没有右表的列，一个都没有，那这个 `JOIN` 就是在给自己埋雷。真按修法 2 动手时，先聚合再拼出来是这样：

```sql
SELECT o.id, o.amount, t.明细数, t.明细金额
FROM orders o
JOIN (SELECT order_id, COUNT(*) AS 明细数, ROUND(SUM(price*quantity),2) AS 明细金额
      FROM order_items GROUP BY order_id) t ON t.order_id = o.id
WHERE o.id <= 3;
```

```text
+----+---------+-----------+--------------+
| id | amount  | 明细数    | 明细金额     |
+----+---------+-----------+--------------+
|  1 | 2663.13 |         3 |      6525.19 |
|  2 | 8614.25 |         3 |      1601.66 |
|  3 | 5518.36 |         3 |      4176.34 |
+----+---------+-----------+--------------+
```

（`amount` 和 `明细金额` 对不上是造数据时随机生成的，本库 20 万单全都对不上 —— 这里比的是「同一份 SQL 有没有多算」，别被这列带偏。）

### 6. 三表连查与驱动表

把订单、用户、明细串起来，查 1 号订单都买了什么：

```sql
SELECT u.username, o.id AS 订单号, i.product_name, i.quantity
FROM orders o
JOIN users u        ON u.id = o.user_id
JOIN order_items i  ON i.order_id = o.id
WHERE o.id = 1;
```

```text
+------------+-----------+-----------------+----------+
| username   | 订单号    | product_name    | quantity |
+------------+-----------+-----------------+----------+
| user_04423 |         1 | 人体工学椅      |        3 |
| user_04423 |         1 | 人体工学椅      |        1 |
| user_04423 |         1 | 人体工学椅      |        5 |
+------------+-----------+-----------------+----------+
```

你按 `FROM o → u → i` 写的 SQL，数据库不一定按这个顺序执行。`EXPLAIN` 的每一行是「拿这张表去配下一张表」，**排第一行的就是驱动表**：

```sql
EXPLAIN SELECT u.username, o.id AS 订单号, i.product_name, i.quantity
FROM orders o
JOIN users u        ON u.id = o.user_id
JOIN order_items i  ON i.order_id = o.id
WHERE o.id = 1;
```

```text
+----+-------------+-------+------------+-------+-------------------------+-----------------+---------+-------+------+----------+-------+
| id | select_type | table | partitions | type  | possible_keys           | key             | key_len | ref   | rows | filtered | Extra |
+----+-------------+-------+------------+-------+-------------------------+-----------------+---------+-------+------+----------+-------+
|  1 | SIMPLE      | o     | NULL       | const | PRIMARY,idx_orders_user | PRIMARY         | 8       | const |    1 |   100.00 | NULL  |
|  1 | SIMPLE      | u     | NULL       | const | PRIMARY                 | PRIMARY         | 8       | const |    1 |   100.00 | NULL  |
|  1 | SIMPLE      | i     | NULL       | ref   | idx_items_order         | idx_items_order | 8       | const |    3 |   100.00 | NULL  |
+----+-------------+-------+------------+-------+-------------------------+-----------------+---------+-------+------+----------+-------+
```

先用 `o.id = 1` 锁死 1 行，再用主键找到那个用户 1 行，最后顺着索引拿到 3 条明细。**驱动表是优化器挑的，不看你 FROM 的顺序** —— 它怎么挑、怎么影响快慢，第 15 篇专门讲，你现在只要记住这个概念就行。

读 `EXPLAIN` 还有个笨办法：把三行连成一句人话 ——「先拿 `o.id = 1` 这个常量取到 1 行订单，再到 `u` 里取 1 行用户，最后顺着索引到 `i` 里取 3 行明细」。每行的 `ref` 列写着「拿上一行的什么值来配我」，`const` 表示常量，`easy_mysql.users.id` 表示具体某一列；谁排在第一行，谁就是驱动表。

## 三个必须记住的结论

1. **INNER 只留两边都配上的行，LEFT 把左表全留下、右表补 NULL**。先问自己「我要全部左表，还是只要配上的」，答案就出来了
2. **右表的过滤条件写在 `ON` 里**；写进 `WHERE` 就是在给左表动刀，LEFT 会瞬间退化成 INNER
3. **一对多 JOIN 会让行数翻倍**：金额、次数这类聚合，要么别 JOIN，要么先把「多」的一侧聚合成一行再拼

## 常见错误

### ❌ 两张表都有 `id`，却不写表名前缀

```sql
-- ERROR 1052 (23000): Column 'id' in field list is ambiguous
SELECT id, name FROM students JOIN scores ON scores.student_id = students.id LIMIT 3;
```

真实报错原文：

```text
ERROR 1052 (23000) at line 1: Column 'id' in field list is ambiguous
```

**为什么错**：`students` 有 `id`，`scores` 也有 `id`，数据库不知道你要哪一个，`ambiguous` 就是「有歧义」。同理 `ORDER BY id`、`WHERE id = 1` 也会踩。

**正确做法**：给列加上表名（或别名）前缀。

```sql
SELECT s.id, s.name FROM students s JOIN scores sc ON sc.student_id = s.id LIMIT 3;
```

```text
+-----+--------+
| id  | name   |
+-----+--------+
| 167 | 冯丽   |
| 167 | 冯丽   |
| 167 | 冯丽   |
+-----+--------+
```

## 动手练

- [ ] 列出所有学生（包括没参加考试的人）及其平均分，没考的显示 NULL
- [ ] 统计每个订单的明细行数，找出明细超过 3 条的订单
- [ ] 想一想：第 5 节那个 3 倍的错，如果订单表里**没有** `amount` 这一列，你只能 JOIN 明细，怎么写才对？

<details>
<summary>第 1 题的答案</summary>

```sql
SELECT s.id, s.name, ROUND(AVG(sc.score),2) AS 平均分
FROM students s LEFT JOIN scores sc ON sc.student_id = s.id
GROUP BY s.id, s.name ORDER BY 平均分 DESC LIMIT 5;
```

```text
+-----+--------+-----------+
| id  | name   | 平均分    |
+-----+--------+-----------+
|  71 | 李勇   |     80.90 |
| 149 | 王洋   |     80.80 |
| 162 | 冯芳   |     80.40 |
|  80 | 李英   |     80.30 |
|   5 | 赵敏   |     80.10 |
+-----+--------+-----------+
```

本数据集 200 人都考过试，所以没有 NULL 行；`AVG` 会跳过 NULL，真有没考的人，他的平均分就是 NULL，正好符合题意。
</details>

<details>
<summary>第 2 题的答案</summary>

```sql
SELECT COUNT(*) AS 明细超过3条的订单数 FROM (
  SELECT order_id FROM order_items GROUP BY order_id HAVING COUNT(*) > 3) t;
```

```text
+------------------------------+
| 明细超过3条的订单数          |
+------------------------------+
|                            0 |
+------------------------------+
```

结果是 0 —— 本库 20 万单**每单恰好 3 条明细**（600000 ÷ 200000）。查出 0 行不是白跑，它反过来证明明细表没脏数据。
</details>

<details>
<summary>第 3 题的答案</summary>

先把明细聚合成「每个订单一行」，再和订单表拼，左表的行数不会被右表撑大：

```sql
SELECT o.id, o.amount, t.明细金额
FROM orders o
JOIN (SELECT order_id, ROUND(SUM(price*quantity),2) AS 明细金额
      FROM order_items GROUP BY order_id) t ON t.order_id = o.id
WHERE o.id <= 3;
```

```text
+----+---------+--------------+
| id | amount  | 明细金额     |
+----+---------+--------------+
|  1 | 2663.13 |      6525.19 |
|  2 | 8614.25 |      1601.66 |
|  3 | 5518.36 |      4176.34 |
+----+---------+--------------+
```

核心就一句：**先聚合，再 JOIN**。
</details>

## 配套实验

```powershell
docker cp lab/queries/07-demo-join.sql easy-mysql:/tmp/
docker exec easy-mysql mysql -uroot -peasy123 -t -e "source /tmp/07-demo-join.sql"
```

> 文件里有一段 `INSERT` 临时造了个「没考试的学生」，查完立刻 `DELETE` 掉，跑完不影响后面的篇目。

## 下一篇

[08 · 子查询与 UNION：让 SQL 嵌套起来](08-subquery-union.md)
