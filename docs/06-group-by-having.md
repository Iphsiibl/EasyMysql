# 06 · GROUP BY 与 HAVING：按班级统计平均分

> **一句话价值**：学会「分组统计」，并彻底搞清 `WHERE` 和 `HAVING` 到底差在哪。

**难度**：⭐⭐　|　**时长**：约 30 分钟　|　**涉及表**：`students`、`scores`、`courses`

## 什么时候你会遇到它

作业要求「统计每个班的平均分、及格人数、挂科率」。你试着写 `SELECT class_name, AVG(score) FROM students, scores ...`，要么直接报错，要么算出来 4 行变 2000 行，要么数字看起来对但和别人的对不上。

问题出在你还没搞清一件事：**数据库凭什么把 2000 行折成 4 行，折完之后还能算什么、不能算什么。** 这篇把 `GROUP BY`、`HAVING` 和那张执行顺序图一次讲透。

## 本篇你会学到

- [ ] `GROUP BY` 的含义：把行「折叠」成组
- [ ] `SELECT` 里的非聚合列必须出现在 `GROUP BY` 中（`ONLY_FULL_GROUP_BY`）
- [ ] `HAVING` 过滤的是**组**，`WHERE` 过滤的是**行**
- [ ] 执行顺序：`FROM → WHERE → GROUP BY → HAVING → SELECT → ORDER BY → LIMIT`
- [ ] 多字段分组，以及 `ROLLUP` 怎么顺手加一行总计

---

## 正文

### 1. 从一列数字到一张报表

问题：全班 200 人，我想知道每个班各有多少人。`GROUP BY` 做的事很简单 —— **按某一列的值把行折叠起来，相同的值归成一组**，然后每组只交一行答案：

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

200 行进去，4 行出来。**`COUNT(*)` 数的是每个组里有多少行**，`ORDER BY class_name` 保证输出顺序稳定。把 `COUNT` 换成 `AVG`、`SUM` 就是各种报表，套路一模一样。

### 2. ONLY_FULL_GROUP_BY：你只能问「每组一个」的问题

现在写一句注定出事的 SQL —— 我既想看 `name`（每个学生一行），又按 `class_name` 分组：

```sql
SELECT s.name, COUNT(*) FROM students s JOIN scores sc ON sc.student_id=s.id GROUP BY s.class_name;
```

```text
ERROR 1055 (42000) at line 1: Expression #1 of SELECT list is not in GROUP BY clause and contains nonaggregated column 'easy_mysql.s.name' which is not functionally dependent on columns in GROUP BY clause; this is incompatible with sql_mode=only_full_group_by
```

**为什么错**：软工210班被折成 1 行，可这个班有 50 个学生 —— `name` 该显示谁的？MySQL 不猜，直接拒绝。这就是 `ONLY_FULL_GROUP_BY`（MySQL 8 默认开启）在管的事，规则一句话：

> **分组之后，`SELECT` 里每一列要么在 `GROUP BY` 里，要么被聚合函数包着。**

两种解法，看你要什么：

```sql
-- 解法 1：我只要班级层面的数字，把 name 删掉
SELECT s.class_name, COUNT(*) AS 成绩条数 FROM students s JOIN scores sc ON sc.student_id = s.id GROUP BY s.class_name ORDER BY s.class_name;
```

```text
+--------------+--------------+
| class_name   | 成绩条数     |
+--------------+--------------+
| 软工210班    |          500 |
| 软工211班    |          500 |
| 软工212班    |          500 |
| 软工213班    |          500 |
+--------------+--------------+
```

```sql
-- 解法 2：我就是要看到人名，那把 name 也加进分组（每组变成一个学生）
SELECT s.class_name, s.name, COUNT(*) AS 科目数 FROM students s JOIN scores sc ON sc.student_id = s.id GROUP BY s.class_name, s.name ORDER BY s.class_name, s.name LIMIT 10;
```

```text
+--------------+-----------+-----------+
| class_name   | name      | 科目数    |
+--------------+-----------+-----------+
| 软工210班    | 孙丽      |        10 |
| 软工210班    | 孙伟      |        10 |
| 软工210班    | 孙娜      |        10 |
| 软工210班    | 孙强磊    |        10 |
| 软工210班    | 孙敏      |        10 |
| 软工210班    | 孙洋      |        10 |
| 软工210班    | 孙秀英    |        10 |
| 软工210班    | 孙艳      |        10 |
| 软工210班    | 孙芳      |        10 |
| 软工210班    | 孙静      |        10 |
+--------------+-----------+-----------+
```

**分组键变了，报表的粒度就变了**：按班级分是 4 行，按班级+姓名分就是 200 行。报错不是在刁难你，是在逼你想清楚「我这张报表一行代表什么」。

### 3. 本篇主菜：JOIN 之后再分组，算每班平均分

成绩在 `scores`，班级在 `students`，先 JOIN 成一张宽表，再按班折叠：

```sql
SELECT s.class_name, COUNT(*) AS 成绩条数, ROUND(AVG(sc.score), 2) AS 平均分, MAX(sc.score) AS 最高分
FROM students s JOIN scores sc ON sc.student_id = s.id
GROUP BY s.class_name ORDER BY 平均分 DESC;
```

```text
+--------------+--------------+-----------+-----------+
| class_name   | 成绩条数     | 平均分    | 最高分    |
+--------------+--------------+-----------+-----------+
| 软工212班    |          500 |     70.47 |    100.00 |
| 软工210班    |          500 |     70.05 |    100.00 |
| 软工211班    |          500 |     69.78 |    100.00 |
| 软工213班    |          500 |     69.57 |    100.00 |
+--------------+--------------+-----------+-----------+
```

读法很具体：**2000 条成绩 JOIN 成 2000 行宽表，按 `class_name` 折成 4 组，每组 500 条成绩算一个平均分**。`ORDER BY 平均分 DESC` 用的是 `SELECT` 里的别名 —— 排序阶段在 SELECT 之后，所以别名排得上用场（下面那张图会再提一次）。

四个班的平均分挤在 69.57~70.47 之间，`MAX` 全是 100 —— 这份数据的分布很平，**报表的意义在结构不在数字**：换份真数据，这张 SQL 一行都不用改。

### 4. 执行顺序：这张图才是本篇的重点

SQL 不是你写什么顺序就执行什么顺序。照着下面的流程画一遍，`WHERE` 和 `HAVING` 的区别会自己浮出来：

```
   ① FROM       students JOIN scores        ← 先把 2000 行宽表取出来
       ↓
   ② WHERE      sc.score >= 60              ← 筛【行】：此时还没分组，
       ↓                                     所以这里不能写 AVG() / COUNT()
   ③ GROUP BY   s.class_name                ← 按班折叠：2000 行 → 4 组
       ↓
   ④ HAVING     AVG(sc.score) >= 70         ← 筛【组】：分组已完成，
       ↓                                     聚合函数在这里合法
   ⑤ SELECT     s.class_name, AVG(sc.score) ← 这时才算得出平均分；
       ↓                                     别名也是这里才诞生
   ⑥ ORDER BY   平均分 DESC                 ← 排序（能用第 ⑤ 步的别名）
       ↓
   ⑦ LIMIT      10                          ← 截断，只要前 N 行
```

三个推论直接背下来：

1. **`WHERE` 里不能有聚合函数** —— 第 ② 步跑的时候第 ③ 步还没发生，「平均分」根本不存在（这就是第 05 篇 `ERROR 1111` 的原因）
2. **`HAVING` 里可以有聚合函数** —— 它排在分组后面；但它也可以写原始列，因为那时列还在
3. **别名在 `WHERE` 里无效、在 `HAVING` / `ORDER BY` 里有效** —— 别名第 ⑤ 步才出生，`WHERE` 第 ② 步就跑完了

### 5. WHERE vs HAVING 对比实验

同一个班，两种「筛」法，结果长得完全不一样。先看 `WHERE`：

```sql
SELECT s.class_name, ROUND(AVG(sc.score), 2) AS 及格平均分
FROM students s JOIN scores sc ON sc.student_id = s.id
WHERE sc.score >= 60 GROUP BY s.class_name ORDER BY s.class_name;
```

```text
+--------------+-----------------+
| class_name   | 及格平均分      |
+--------------+-----------------+
| 软工210班    |           79.96 |
| 软工211班    |           80.95 |
| 软工212班    |           80.51 |
| 软工213班    |           79.53 |
+--------------+-----------------+
```

再看 `HAVING`：

```sql
SELECT s.class_name, ROUND(AVG(sc.score), 2) AS 全科平均分
FROM students s JOIN scores sc ON sc.student_id = s.id
GROUP BY s.class_name HAVING AVG(sc.score) >= 70 ORDER BY s.class_name;
```

```text
+--------------+-----------------+
| class_name   | 全科平均分      |
+--------------+-----------------+
| 软工210班    |           70.05 |
| 软工212班    |           70.47 |
+--------------+-----------------+
```

并排讲差别：

| | 写法 A：`WHERE score >= 60` | 写法 B：`HAVING AVG(score) >= 70` |
|---|---|---|
| 什么时候生效 | 分组**之前** | 分组**之后** |
| 筛掉的东西 | 不及格的**成绩行** | 平均分不够 70 的**班级** |
| 还剩几组 | 4 个班全在，只是数字从 70 变到 80 | 4 个班只剩 2 个，211 和 213 整组消失 |
| 影响 | 改变**参与计算的数据** | 改变**留下哪些报表行** |

**`WHERE` 改的是原料，`HAVING` 改的是成品。** 记住这个对应关系，比背语法管用：想「先去掉脏数据再统计」用 `WHERE`，想「统计完再挑几组」用 `HAVING`。两者都能用的时候，优先用 `WHERE` —— 先筛行能让分组少干很多活（能不能提速，第 15 篇用 `EXPLAIN` 验证）。

### 6. 多字段分组

`GROUP BY` 后面可以跟多列：**列的组合相同才归一组**。城市 × 性别：

```sql
SELECT city, gender, COUNT(*) AS 人数 FROM students GROUP BY city, gender ORDER BY city, gender;
```

```text
+--------+--------+--------+
| city   | gender | 人数   |
+--------+--------+--------+
| 上海   | 女     |     34 |
| 北京   | 男     |     33 |
| 广州   | 男     |     34 |
| 成都   | 女     |     33 |
| 杭州   | 男     |     33 |
| 深圳   | 女     |     33 |
+--------+--------+--------+
```

6 组，200 人一个不少。这份数据里每城只有一种性别（造数据时故意的），所以看不出交叉；换成真数据，`GROUP BY city, gender` 就是一张「城市 × 性别」的交叉表 —— 顺带说，第 2 节的规则在这里同样成立：你写了两列分组，`SELECT` 里就能放这两列。

### 7. ROLLUP：顺手给报表加一行总计

报表最后一行常常是「合计」。`WITH ROLLUP` 白送：

```sql
SELECT s.class_name, ROUND(AVG(sc.score), 2) AS 平均分, COUNT(*) AS 成绩条数
FROM students s JOIN scores sc ON sc.student_id = s.id
GROUP BY s.class_name WITH ROLLUP ORDER BY s.class_name;
```

```text
+--------------+-----------+--------------+
| class_name   | 平均分    | 成绩条数     |
+--------------+-----------+--------------+
| NULL         |     69.97 |         2000 |
| 软工210班    |     70.05 |          500 |
| 软工211班    |     69.78 |          500 |
| 软工212班    |     70.47 |          500 |
| 软工213班    |     69.57 |          500 |
+--------------+-----------+--------------+
```

第一行的 `class_name` 是 `NULL`，它就是汇总行：**所有班合起来的平均分 69.97、成绩 2000 条**（和第 05 篇的全局数字对上了）。因为 `NULL` 默认排在最前，总计行跑到顶上去了 —— 想让它垫底得自己处理排序，MySQL 不支持 `NULLS LAST`。

网上有说法称「`WITH ROLLUP` 时不能按聚合列 `ORDER BY`」。**本机 MySQL 8.0.46 实测，能跑**：

```sql
SELECT s.class_name, ROUND(AVG(sc.score), 2) AS 平均分
FROM students s JOIN scores sc ON sc.student_id = s.id
GROUP BY s.class_name WITH ROLLUP ORDER BY 平均分 DESC;
```

```text
+--------------+-----------+
| class_name   | 平均分    |
+--------------+-----------+
| 软工212班    |     70.47 |
| 软工210班    |     70.05 |
| NULL         |     69.97 |
| 软工211班    |     69.78 |
| 软工213班    |     69.57 |
+--------------+-----------+
```

能跑是能跑，但汇总行按自己的 69.97 **插进了队伍中间**，第 3 行那个 NULL 很容易被当成一个叫「NULL」的班。**汇总行的排序问题，实测为准，别背结论**；要保险就按分组列排，让汇总行位置固定。

## 三个必须记住的结论

1. **`GROUP BY` 把行折叠成组，一行报表 = 一个组**；`SELECT` 里非聚合列必须进 `GROUP BY`，否则吃 `ERROR 1055`
2. **执行顺序是 `FROM → WHERE → GROUP BY → HAVING → SELECT → ORDER BY → LIMIT`**：`WHERE` 筛行（不能用聚合），`HAVING` 筛组（可以），别名只在 `HAVING` / `ORDER BY` 里有效
3. **`WHERE` 改原料，`HAVING` 改成品**；能用 `WHERE` 先筛行就先筛，`ROLLUP` 可以白送一行汇总

## 常见错误

### ❌ 把 `SELECT` 起的别名写进 `WHERE`

```sql
SELECT class_name, COUNT(*) AS n FROM students WHERE n > 40 GROUP BY class_name;
```

```text
ERROR 1054 (42S22) at line 1: Unknown column 'n' in 'where clause'
```

**为什么错**：`WHERE` 是第 ② 步，`SELECT` 里的别名 `n` 到第 ⑤ 步才诞生 —— `WHERE` 执行时 `n` 这个名字根本不存在，MySQL 只好当成一个不存在的列名报错。**在 WHERE 里引用别名 = 让你在出生前见到自己。**

**正确做法**：筛聚合结果用 `HAVING`（它在第 ④ 步，那时 `n` 还没出生也没关系，直接重写条件）：

```sql
SELECT class_name, COUNT(*) AS n FROM students GROUP BY class_name HAVING n > 40 ORDER BY class_name;
```

```text
+--------------+----+
| class_name   | n  |
+--------------+----+
| 软工210班    | 50 |
| 软工211班    | 50 |
| 软工212班    | 50 |
| 软工213班    | 50 |
+--------------+----+
```

（`GROUP BY` 之后 `HAVING` 能直接用别名 `n`，也能写 `HAVING COUNT(*) > 40`，效果一样。）

## 动手练

- [ ] 统计每门课的报名人数、平均分、最高分，并只留平均分 ≥ 60 的课
- [ ] 统计每个学生的不及格科目数，只看有不及格的

<details>
<summary>点开看答案</summary>

```sql
-- 第 1 题：分组算三个指标，再用 HAVING 筛组
SELECT c.name AS 课程, COUNT(*) AS 报名人数, ROUND(AVG(sc.score), 2) AS 平均分, MAX(sc.score) AS 最高分
FROM scores sc JOIN courses c ON c.id = sc.course_id
GROUP BY c.id, c.name HAVING AVG(sc.score) >= 60 ORDER BY 平均分 DESC;
```

```text
+-----------------------+--------------+-----------+-----------+
| 课程                  | 报名人数     | 平均分    | 最高分    |
+-----------------------+--------------+-----------+-----------+
| 软件工程              |          200 |     71.67 |    100.00 |
| 大学英语              |          200 |     71.23 |    100.00 |
| 操作系统              |          200 |     71.05 |    100.00 |
| 数据库原理            |          200 |     70.95 |    100.00 |
| 数据结构              |          200 |     70.22 |    100.00 |
| Java 程序设计         |          200 |     69.80 |    100.00 |
| 算法设计与分析        |          200 |     69.55 |    100.00 |
| 计算机网络            |          200 |     69.01 |    100.00 |
| 高等数学              |          200 |     68.49 |    100.00 |
| Python 入门           |          200 |     67.74 |    100.00 |
+-----------------------+--------------+-----------+-----------+
```

10 门全过了 —— `HAVING` 没删掉任何一行，这题的门槛设低了。把 60 改成 70 再跑，就是另一回事：

```sql
SELECT c.name AS 课程, ROUND(AVG(sc.score), 2) AS 平均分
FROM scores sc JOIN courses c ON c.id = sc.course_id
GROUP BY c.id, c.name HAVING AVG(sc.score) >= 70 ORDER BY 平均分 DESC;
```

```text
+-----------------+-----------+
| 课程            | 平均分    |
+-----------------+-----------+
| 软件工程        |     71.67 |
| 大学英语        |     71.23 |
| 操作系统        |     71.05 |
| 数据库原理      |     70.95 |
| 数据结构        |     70.22 |
+-----------------+-----------+
```

只剩 5 门，这才是 `HAVING` 在干活的样子。

```sql
-- 第 2 题：先 WHERE 只留不及格的成绩，再按学生分组，HAVING 筛掉 0 分组的
SELECT s.name, COUNT(*) AS 不及格门数 FROM students s JOIN scores sc ON sc.student_id = s.id
WHERE sc.score < 60 GROUP BY s.id, s.name ORDER BY 不及格门数 DESC, s.name LIMIT 10;
```

```text
+--------+-----------------+
| name   | 不及格门数      |
+--------+-----------------+
| 吴静   |               8 |
| 周平   |               7 |
| 赵霞   |               7 |
| 郑英   |               7 |
| 冯敏   |               6 |
| 冯艳   |               6 |
| 吴涛   |               6 |
| 周勇   |               6 |
| 孙丽   |               6 |
| 孙平   |               6 |
+--------+-----------------+
```

全班 200 人里 **197 人至少挂一科**，最多的挂了 8 科：

```sql
SELECT COUNT(*) AS 至少挂一科的人数 FROM (SELECT student_id FROM scores WHERE score < 60 GROUP BY student_id) x;
```

```text
+--------------------------+
| 至少挂一科的人数         |
+--------------------------+
|                      197 |
+--------------------------+
```

</details>

## 配套实验

```powershell
docker cp lab/queries/06-demo-group-by.sql easy-mysql:/tmp/
docker exec easy-mysql mysql -uroot -peasy123 -t -e "source /tmp/06-demo-group-by.sql"
```

> 只读实验；会报错的那句 `ONLY_FULL_GROUP_BY` 在文件里注释掉了，解开能亲眼看 `ERROR 1055`。

## 下一篇

[07 · JOIN：把学生表和成绩表拼起来](07-join.md)
