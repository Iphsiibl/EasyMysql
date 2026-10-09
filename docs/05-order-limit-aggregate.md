# 05 · 排序、分页与聚合：COUNT / SUM / AVG / MAX / MIN

> **一句话价值**：算出「一共多少人」「平均分多少」「最高分是谁」，并学会不会越翻越慢的分页。

**难度**：⭐⭐　|　**时长**：约 25 分钟　|　**涉及表**：`students`、`scores`、`orders`

## 什么时候你会遇到它

老师问「全班平均分多少」，你把 2000 条成绩全选出来，关掉 SQL，用计算器按。网页翻到第 5000 页时卡住不动了，你顺手把 `LIMIT 10 OFFSET 500000` 加大了点，它卡得更久。

这两个问题一个是**聚合**，一个是**分页**，都属于「SQL 自己能干的活」。这篇把五个聚合函数、COUNT 的三种写法、以及深分页那个坑一次讲清。

## 本篇你会学到

- [ ] 五个聚合函数：`COUNT` `SUM` `AVG` `MAX` `MIN`
- [ ] `COUNT(*)` 和 `COUNT(列名)`、`COUNT(DISTINCT 列名)` 的区别
- [ ] 聚合函数**为什么不能放进 WHERE**（会报什么错）
- [ ] `LIMIT offset, n` 的**大坑**：越翻越慢，以及 `EXPLAIN` 怎么暴露它
- [ ] 深分页的两个正确写法：游标分页、延迟关联
- [ ] 求「最高分是谁」的标准套路：先聚合，再回表

---

## 正文

### 1. 五个聚合函数：把 2000 行压成一行

问题很朴素：2000 条成绩，老师只要一个总分和一个平均分。**聚合函数（aggregate function）干的就是这件事：吃进去一列数字，吐出来一个数**：

```sql
SELECT COUNT(*) AS 成绩条数, SUM(score) AS 总分, ROUND(AVG(score), 2) AS 平均分, MAX(score) AS 最高分, MIN(score) AS 最低分 FROM scores;
```

```text
+--------------+-----------+-----------+-----------+-----------+
| 成绩条数     | 总分      | 平均分    | 最高分    | 最低分    |
+--------------+-----------+-----------+-----------+-----------+
|         2000 | 139936.00 |     69.97 |    100.00 |     40.00 |
+--------------+-----------+-----------+-----------+-----------+
```

五个函数五个问题：**多少条**、**加起来多少**、**平均多少**、**最高多少**、**最低多少**。2000 行进去，一行出来 —— 这就是「聚合」。

`AVG` 默认会带一堆小数，`ROUND(x, 2)` 四舍五入到两位。这五个函数以后会天天跟 `GROUP BY` 组合使用，那是下一篇的主菜。

### 2. COUNT 的三种写法，差在一个字

```sql
SELECT COUNT(*) AS count_star, COUNT(city) AS count_col, COUNT(DISTINCT city) AS 城市数 FROM students;
```

```text
+------------+-----------+-----------+
| count_star | count_col | 城市数    |
+------------+-----------+-----------+
|        200 |       200 |         6 |
+------------+-----------+-----------+
```

- **`COUNT(*)` 数的是行**：200 行就是 200
- **`COUNT(city)` 数的是「city 这一列里有值的行」**：也是 200，因为 `students.city` 是 `NOT NULL`，一行都不缺
- **`COUNT(DISTINCT city)` 先去重再数**：200 个人挤在 6 个城市里

前两个数字一样，纯属这张表设计得好。`COUNT(列)` 的真实规则是「**NULL 不算数**」，看这句就明白：

```sql
SELECT COUNT(*) AS 全部行, COUNT(NULL) AS 永远不算 FROM students;
```

```text
+-----------+--------------+
| 全部行    | 永远不算     |
+-----------+--------------+
|       200 |            0 |
+-----------+--------------+
```

`COUNT(NULL)` 永远是 0 —— 一列里要是有 NULL，`COUNT(列)` 就会比 `COUNT(*)` 少。再用 `scores` 熟悉一下 `DISTINCT`：

```sql
SELECT COUNT(*) AS 行数, COUNT(DISTINCT student_id) AS 人数, COUNT(DISTINCT course_id) AS 门数 FROM scores;
```

```text
+--------+--------+--------+
| 行数   | 人数   | 门数   |
+--------+--------+--------+
|   2000 |    200 |     10 |
+--------+--------+--------+
```

2000 条成绩 = 200 个学生 × 10 门课。**`COUNT(*)` 数行，`COUNT(DISTINCT 列)` 数「有多少种」**，报表里这两个天天一起出现。

### 3. 聚合函数不能放进 WHERE

写一句「平均分大于 60 的记录」，直觉是：

```sql
SELECT AVG(score) FROM scores WHERE AVG(score) >= 60;
```

```text
ERROR 1111 (HY000) at line 1: Invalid use of group function
```

**为什么错**：`WHERE` 执行的时候，那一行一行的原始数据还没被压成「平均分」—— 都不存在的东西，怎么拿来比较？记住这句话：**WHERE 筛的是原始行，聚合是分组之后才算得出来的**。想要「筛聚合结果」，用 `HAVING`，下一篇专门讲。

但下面这句是合法的，因为它筛的是**原始行的分数**：

```sql
SELECT ROUND(AVG(score), 2) AS 及格分的平均分 FROM scores WHERE score >= 60;
```

```text
+-----------------------+
| 及格分的平均分        |
+-----------------------+
|                 80.23 |
+-----------------------+
```

和第 1 节的 69.97 对比：**69.97 是全体平均，80.23 是「及格成绩」的平均** —— 同一个 `AVG`，配不同的 `WHERE`，是两个完全不同的指标。别把后者当成「及格的人的平均分」，挂科的人被 WHERE 直接扔掉了。

### 4. 分页的坑：OFFSET 要先丢掉前 N 行

翻页就两个语法，结果一样：

```sql
SELECT id, user_id, amount FROM orders ORDER BY id LIMIT 10;
SELECT id, user_id, amount FROM orders ORDER BY id LIMIT 10 OFFSET 10;
```

```text
+----+---------+---------+
| id | user_id | amount  |
+----+---------+---------+
|  1 |    4423 | 2663.13 |
|  2 |     765 | 8614.25 |
|  3 |    1107 | 5518.36 |
|  4 |    3274 | 1621.92 |
|  5 |       3 |  220.68 |
|  6 |    3342 | 2673.36 |
|  7 |    2436 | 1285.86 |
|  8 |    4731 | 1609.91 |
|  9 |    3701 | 1767.99 |
| 10 |       2 | 4255.76 |
+----+---------+---------+
+----+---------+---------+
| id | user_id | amount  |
+----+---------+---------+
| 11 |    1186 |  197.20 |
| 12 |      12 | 5346.30 |
| 13 |    2038 | 1633.80 |
| 14 |     183 | 1982.78 |
| 15 |       1 | 3699.54 |
| 16 |    4771 | 1649.95 |
| 17 |    4181 | 1651.05 |
| 18 |     126 |  318.12 |
| 19 |    3524 |  207.50 |
| 20 |       3 |  660.13 |
+----+---------+---------+
```

第 1 页 rows 是多少？第 5000 页呢？`EXPLAIN` 直接告诉你：

```sql
EXPLAIN SELECT id, user_id, amount FROM orders ORDER BY id LIMIT 10;
EXPLAIN SELECT id, user_id, amount FROM orders ORDER BY id LIMIT 100000, 20;
```

```text
+----+-------------+--------+------------+-------+---------------+---------+---------+------+------+----------+-------+
| id | select_type | table  | partitions | type  | possible_keys | key     | key_len | ref  | rows | filtered | Extra |
+----+-------------+--------+------------+-------+---------------+---------+---------+------+------+----------+-------+
|  1 | SIMPLE      | orders | NULL       | index | NULL          | PRIMARY | 8       | NULL |   10 |   100.00 | NULL  |
+----+-------------+--------+------------+-------+---------------+---------+---------+------+------+----------+-------+
+----+-------------+--------+------------+-------+---------------+---------+---------+------+--------+----------+-------+
| id | select_type | table  | partitions | type  | possible_keys | key     | key_len | ref  | rows   | filtered | Extra |
+----+-------------+--------+------------+-------+---------------+---------+---------+------+--------+----------+-------+
|  1 | SIMPLE      | orders | NULL       | index | NULL          | PRIMARY | 8       | NULL | 100020 |   100.00 | NULL  |
+----+-------------+--------+------------+-------+---------------+---------+---------+------+--------+----------+-------+
```

**10 对 100020。** `OFFSET` 的定义就是「先跳过前 N 行，再给你后面的」—— 数据库老老实实数完 10 万行、全部丢掉，才开始返回 20 行。你翻得越深，它丢得越多，**页码是免费的，OFFSET 不是**。

跑一遍实测（每条跑两遍，避开首次预热）：

```sql
SET profiling = 1;
SELECT id, user_id, amount FROM orders ORDER BY id LIMIT 100000, 20;
SELECT id, user_id, amount FROM orders ORDER BY id LIMIT 100000, 20;
SELECT o.id, o.user_id, o.amount FROM orders o JOIN (SELECT id FROM orders ORDER BY id LIMIT 100000, 20) t ON t.id = o.id ORDER BY o.id;
SELECT o.id, o.user_id, o.amount FROM orders o JOIN (SELECT id FROM orders ORDER BY id LIMIT 100000, 20) t ON t.id = o.id ORDER BY o.id;
SELECT id, user_id, amount FROM orders WHERE id > 150000 ORDER BY id LIMIT 20;
SELECT id, user_id, amount FROM orders WHERE id > 150000 ORDER BY id LIMIT 20;
SELECT id, user_id, amount FROM orders ORDER BY id LIMIT 10;
SHOW PROFILES;
```

```text
+----------+------------+-----------------------------------------------------------------------------------------------------------------------------------------+
| Query_ID | Duration   | Query                                                                                                                                   |
+----------+------------+-----------------------------------------------------------------------------------------------------------------------------------------+
|        1 | 0.02184650 | SELECT id, user_id, amount FROM orders ORDER BY id LIMIT 100000, 20                                                                     |
|        2 | 0.02156975 | SELECT id, user_id, amount FROM orders ORDER BY id LIMIT 100000, 20                                                                     |
|        3 | 0.01719800 | SELECT o.id, o.user_id, o.amount FROM orders o JOIN (SELECT id FROM orders ORDER BY id LIMIT 100000, 20) t ON t.id = o.id ORDER BY o.id |
|        4 | 0.01581350 | SELECT o.id, o.user_id, o.amount FROM orders o JOIN (SELECT id FROM orders ORDER BY id LIMIT 100000, 20) t ON t.id = o.id ORDER BY o.id |
|        5 | 0.00095125 | SELECT id, user_id, amount FROM orders WHERE id > 150000 ORDER BY id LIMIT 20                                                           |
|        6 | 0.00078525 | SELECT id, user_id, amount FROM orders WHERE id > 150000 ORDER BY id LIMIT 20                                                           |
|        7 | 0.00017525 | SELECT id, user_id, amount FROM orders ORDER BY id LIMIT 10                                                                             |
+----------+------------+-----------------------------------------------------------------------------------------------------------------------------------------+
```

> **⚠️ 关于这些数字**：`Duration` 随机器、缓存、磁盘变化，**你的数字不会和我一样**。值得记的是稳定的那部分：1 和 2 是深分页，5 和 6 是游标分页，7 是第一页 —— 三者差了一个数量级以上，而 `EXPLAIN` 的 `rows`（100020 vs 10）从头到尾不变。

### 5. 深分页的两个正确写法

**写法 A：游标分页（推荐）。** 上一页的末条是 `id = 150000`，下一页就从它后面取，别让数据库「跳过」任何东西：

```sql
SELECT id, user_id, amount FROM orders WHERE id > 150000 ORDER BY id LIMIT 20;
```

```text
+--------+---------+---------+
| id     | user_id | amount  |
+--------+---------+---------+
| 150001 |     413 | 1530.30 |
| 150002 |    2919 | 5711.28 |
| 150003 |     841 | 1298.90 |
| 150004 |    1372 | 9374.25 |
| 150005 |       3 | 1677.15 |
| 150006 |    1336 | 2521.00 |
| 150007 |    1026 |  215.74 |
| 150008 |    2945 |  543.30 |
| 150009 |    3695 | 9889.60 |
| 150010 |       2 | 1058.07 |
| 150011 |    2366 | 1569.58 |
| 150012 |    4464 | 1183.13 |
| 150013 |    2690 | 4431.16 |
| 150014 |    4019 |  510.12 |
| 150015 |       2 |  316.70 |
| 150016 |    2743 | 3532.80 |
| 150017 |    2425 | 2506.96 |
| 150018 |    4026 | 6876.95 |
| 150019 |     840 |  599.21 |
| 150020 |       1 | 2160.36 |
+--------+---------+---------+
```

```sql
EXPLAIN SELECT id, user_id, amount FROM orders WHERE id > 150000 ORDER BY id LIMIT 20;
```

```text
+----+-------------+--------+------------+-------+---------------+---------+---------+------+-------+----------+-------------+
| id | select_type | table  | partitions | type  | possible_keys | key     | key_len | ref  | rows  | filtered | Extra       |
+----+-------------+--------+------------+-------+---------------+---------+---------+------+-------+----------+-------------+
|  1 | SIMPLE      | orders | NULL       | range | PRIMARY       | PRIMARY | 8       | NULL | 99715 |   100.00 | Using where |
+----+-------------+--------+------------+-------+---------------+---------+---------+------+-------+----------+-------------+
```

`type = range`：**直接定位到 `id > 150000` 的位置开始读，读够 20 行就停**。`rows` 显示 99715 是「这个范围里一共有多少行」的估算上限，不是「它真读了这么多」—— 读多少由 `LIMIT` 说了算。深分页那种「先数完 10 万行再说」的流程，这里一步都没发生。代价是你的页面不能随便输页码，得记住上一页的末条 id（所以叫**游标 / keyset 分页**），也没法直接跳到末页 —— 换来的是**从第 1 页到第 5000 页，耗时一个样**。

**写法 B：延迟关联。** 产品非要「跳到第 5000 页」的按钮怎么办？把 OFFSET 关进一个只查 `id` 的子查询里，取到 20 个 id 再回表：

```sql
SELECT o.id, o.user_id, o.amount FROM orders o JOIN (SELECT id FROM orders ORDER BY id LIMIT 100000, 20) t ON t.id = o.id ORDER BY o.id;
```

```text
+--------+---------+---------+
| id     | user_id | amount  |
+--------+---------+---------+
| 100001 |    4141 | 1598.34 |
| 100002 |    3983 | 1444.72 |
| 100003 |     521 | 1927.88 |
| 100004 |    4324 | 1596.87 |
| 100005 |       1 | 7318.68 |
| 100006 |    2944 | 2876.18 |
| 100007 |    1314 |  397.75 |
| 100008 |    4649 |  755.28 |
| 100009 |    1783 | 4474.40 |
| 100010 |       3 | 4146.87 |
| 100011 |    1166 | 1301.10 |
| 100012 |     712 | 3247.47 |
| 100013 |    2554 |  851.75 |
| 100014 |    4019 |  510.12 |
| 100015 |       2 |  316.70 |
| 100016 |    2743 | 3532.80 |
| 100017 |    2425 | 2506.96 |
| 100018 |    4026 | 6876.95 |
| 100019 |     840 |  599.21 |
| 100020 |       1 | 2160.36 |
+--------+---------+---------+
```

输出和普通深分页一模一样（都是 id 100001~100020），差别全在 `EXPLAIN` 里：

```text
+----+-------------+------------+------------+--------+---------------+---------+---------+------+--------+----------+---------------------------------+
| id | select_type | table      | partitions | type   | possible_keys | key     | key_len | ref  | rows   | filtered | Extra                           |
+----+-------------+------------+------------+--------+---------------+---------+---------+------+--------+----------+---------------------------------+
|  1 | PRIMARY     | <derived2> | NULL       | ALL    | NULL          | NULL    | NULL    | NULL | 100020 |   100.00 | Using temporary; Using filesort |
|  1 | PRIMARY     | o          | NULL       | eq_ref | PRIMARY       | PRIMARY | 8       | t.id |      1 |   100.00 | NULL                            |
|  2 | DERIVED     | orders     | NULL       | index  | NULL          | PRIMARY | 8       | NULL | 100020 |   100.00 | Using index                     |
+----+-------------+------------+------------+--------+---------------+---------+---------+------+--------+----------+---------------------------------+
```

三行各干各的：`DERIVED` 那行是内层子查询，`Using index` 说明它**只在主键索引上数 id，不碰别的列**；`o` 那行 `type = eq_ref, rows = 1`，拿到 20 个 id 后每次只查一行，**外层一共只处理 20 行**。

老实说：在 20 万行的 `orders` 上，它的耗时和普通深分页**同一个数量级**（看上面第 3、4 行）—— `OFFSET` 要扫的 10 万行躲不掉，能省的只是每行的开销。**深分页的解药是写法 A，写法 B 是不得不用 OFFSET 时的止损。**

顺带说一句「排序走不走索引」：按 `id` 排时 `Extra` 是空的，索引本身就是按 id 排好的；换成按 `amount` 排：

```sql
EXPLAIN SELECT id, user_id, amount FROM orders ORDER BY amount DESC LIMIT 10;
```

```text
+----+-------------+--------+------------+------+---------------+------+---------+------+--------+----------+----------------+
| id | select_type | table  | partitions | type | possible_keys | key  | key_len | ref  | rows   | filtered | Extra          |
+----+-------------+--------+------------+------+---------------+------+---------+------+--------+----------+----------------+
|  1 | SIMPLE      | orders | NULL       | ALL  | NULL          | NULL | NULL    | NULL | 199430 |   100.00 | Using filesort |
+----+-------------+--------+------------+------+---------------+------+---------+------+--------+----------+----------------+
```

`Using filesort` = 20 万行全读出来，在内存里现排序。**「让排序尽量走索引」指的就是消掉这个 `Using filesort`**，第 16 篇会拿它开刀。

### 6. 最高分是谁：先聚合，再回表

`MAX` 只会给你一个数字，不带任何人名：

```sql
SELECT COUNT(*) AS 满分条数 FROM scores WHERE score = (SELECT MAX(score) FROM scores);
```

```text
+--------------+
| 满分条数     |
+--------------+
|           27 |
+--------------+
```

满分 27 条。套路是**把聚合结果当条件，再回表去拿人名**（子查询写在 `WHERE` 后面，第 08 篇细讲）：

```sql
SELECT s.name, c.name AS 课程, sc.score FROM scores sc JOIN students s ON s.id = sc.student_id JOIN courses c ON c.id = sc.course_id WHERE sc.score = (SELECT MAX(score) FROM scores) ORDER BY sc.id LIMIT 8;
```

```text
+-----------+-----------------------+--------+
| name      | 课程                  | score  |
+-----------+-----------------------+--------+
| 赵秀英    | 软件工程              | 100.00 |
| 赵强磊    | 数据库原理            | 100.00 |
| 赵军杰    | Python 入门           | 100.00 |
| 赵明超    | Java 程序设计         | 100.00 |
| 赵刚      | Java 程序设计         | 100.00 |
| 赵桂      | 算法设计与分析        | 100.00 |
| 赵英      | 高等数学              | 100.00 |
| 钱伟      | 计算机网络            | 100.00 |
+-----------+-----------------------+--------+
```

先用子查询拿到 100.00 这个数，再拿它去 `scores` 里筛行，接着 JOIN 出名字和课程。`ORDER BY sc.id LIMIT 8` 是为了输出稳定（27 行太多，只看前 8 条）。

## 三个必须记住的结论

1. **聚合函数吃一列、吐一个数**，`COUNT(*)` 数行、`COUNT(DISTINCT 列)` 数种类，`COUNT(列)` 跳过 NULL
2. **聚合函数不能出现在 WHERE 里**（`ERROR 1111`）：WHERE 筛原始行，筛聚合结果要用 HAVING
3. **`OFFSET` 是先跳过再返回**，`EXPLAIN` 的 `rows` 会从 10 涨到 100020；翻深页用游标（`id > 上次最大值`），非用 OFFSET 不可就延迟关联

## 常见错误

### ❌ 想要「班级 + 人数」，却忘了 GROUP BY

```sql
SELECT class_name, COUNT(*) FROM students;
```

```text
ERROR 1140 (42000) at line 1: In aggregated query without GROUP BY, expression #1 of SELECT list contains nonaggregated column 'easy_mysql.students.class_name'; this is incompatible with sql_mode=only_full_group_by
```

**为什么错**：`COUNT(*)` 要把 200 行压成 1 个数，可你同时还要 `class_name` —— 压成 1 行之后，该显示哪个班的名字？MySQL 拒绝替你猜。**聚合列和普通列不能出现在同一个没有 GROUP BY 的查询里。**

**正确做法**：告诉它按什么分组（下一篇的主角）：

```sql
SELECT class_name, COUNT(*) AS 人数 FROM students GROUP BY class_name ORDER BY class_name;
```

```text
+--------------+--------+
| class_name   | 人数   |
+--------------+--------+
| 软工210班    |     50 |
| 软工211班    |     50 |
| 软工212班    |     50 |
| 软工213班    |     50 |
+--------------+--------+
```

## 动手练

- [ ] 查询订单金额最高的 10 笔订单
- [ ] 查询前 1000 笔订单里每个用户的订单数，取前 10 名（这题要用 `GROUP BY`，没学过就照着答案跑，下一篇讲）

<details>
<summary>点开看答案</summary>

```sql
-- 第 1 题：ORDER BY 金额倒序 + LIMIT 10
SELECT id, user_id, amount FROM orders ORDER BY amount DESC LIMIT 10;
```

```text
+--------+---------+----------+
| id     | user_id | amount   |
+--------+---------+----------+
|   3235 |       2 | 10049.30 |
|  27306 |    1565 | 10048.60 |
|  23387 |    4278 | 10048.25 |
| 180371 |     468 | 10047.85 |
|  96144 |    1247 | 10047.70 |
|  36451 |    2035 | 10047.50 |
| 141386 |    2324 | 10047.45 |
|  75907 |    1320 | 10047.35 |
| 112449 |    3494 | 10047.15 |
|  67133 |    3031 | 10046.90 |
+--------+---------+----------+
```

```sql
-- 第 2 题：先 WHERE 圈定前 1000 笔，再按用户分组，按订单数倒序
SELECT user_id, COUNT(*) AS 订单数 FROM orders WHERE id <= 1000 GROUP BY user_id ORDER BY 订单数 DESC, user_id LIMIT 10;
```

```text
+---------+-----------+
| user_id | 订单数    |
+---------+-----------+
|       2 |        67 |
|       3 |        67 |
|       1 |        66 |
|    1268 |         3 |
|    2205 |         3 |
|    2895 |         3 |
|      40 |         2 |
|      84 |         2 |
|     307 |         2 |
|     357 |         2 |
+---------+-----------+
```

第 1、2、3 名是老熟人：第 13 篇的实验文件里提过，本数据集 20% 的订单就压在这三个用户身上 —— 前 1000 笔里他们占了 200 笔，换个口径照样霸榜。

</details>

## 配套实验

```powershell
docker cp lab/queries/05-demo-aggregate.sql easy-mysql:/tmp/
docker exec easy-mysql mysql -uroot -peasy123 -t -e "source /tmp/05-demo-aggregate.sql"
```

> 只读实验，不改任何数据；报错的两句在文件里注释掉了，解开可以亲眼看 `ERROR 1111` 和 `ERROR 1140`。

## 下一篇

[06 · GROUP BY 与 HAVING：按班级统计平均分](06-group-by-having.md)
