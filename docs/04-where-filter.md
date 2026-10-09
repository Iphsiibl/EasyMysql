# 04 · WHERE 过滤：只留我想要的数据

> **一句话价值**：掌握 `= > < LIKE IN BETWEEN AND OR IS NULL` 这一整套筛选条件，让数据库只把你要的行找出来。

**难度**：⭐　|　**时长**：约 25 分钟　|　**涉及表**：`students`、`bad_design_demo`

## 什么时候你会遇到它

班群要收一份「北京的、2006 年以前出生的、姓名带伟的」名单。`students` 一共 200 行，你 Ctrl+F 翻了三次，每次记的条件都不一样。更尴尬的是你写了 `WHERE name LIKE '%伟%' AND gender = '男'`，跑出来 0 行 —— 你分不清是数据里真没有，还是自己写错了。

WHERE 就是那句「只要……」。**条件写错时 MySQL 不会报错，它会安静地给你一份错名单**，这比报错可怕得多。这篇把整套筛选条件过一遍，每个坑都先让你踩一次。

## 本篇你会学到

- [ ] 六种比较运算符，以及日期**为什么要加引号**
- [ ] `AND` / `OR` / `NOT` 以及**括号为什么不能省**
- [ ] `LIKE` 模糊查询，`%` 和 `_` 的区别
- [ ] `IN` 解决「或是一长串值」的写法
- [ ] `BETWEEN a AND b` 的两个坑（闭区间、写反顺序）
- [ ] `IS NULL` 和 `= NULL` 为什么不一样

---

## 正文

### 1. 最常见的三个比较：= > <

先解决最朴素的问题：只要北京的学生。`WHERE` 写在表名后面，数据库逐行看，**条件成立的行才留下**：

```sql
SELECT name, city FROM students WHERE city = '北京' ORDER BY id LIMIT 5;
```

```text
+-----------+--------+
| name      | city   |
+-----------+--------+
| 赵静      | 北京   |
| 赵军杰    | 北京   |
| 赵刚      | 北京   |
| 钱秀英    | 北京   |
| 钱艳      | 北京   |
+-----------+--------+
```

200 行进来，5 行出去。数字和日期也是同款写法：

```sql
SELECT COUNT(*) AS 等于北京 FROM students WHERE city = '北京';
SELECT COUNT(*) AS 2006之后出生 FROM students WHERE birth_date > '2006-01-01';
SELECT COUNT(*) AS 最早那天之前 FROM students WHERE birth_date < '2005-09-02';
```

```text
+--------------+
| 等于北京     |
+--------------+
|           33 |
+--------------+
+------------------+
| 2006之后出生     |
+------------------+
|               78 |
+------------------+
+--------------------+
| 最早那天之前       |
+--------------------+
|                  0 |
+--------------------+
```

- **`=` 等于 33 人**，后面所有例子都建立在这个数字上
- **`>` 等于 78 人**：200 人里 78 个出生在 2006-01-01 之后
- **`<` 查出 0 行**：这**不是 bug**。本表最早出生的是 2005-09-02，比它还早的人一个都没有。**查出 0 行时，先怀疑数据范围，再怀疑语法**

不等于用 `<>`（`!=` 也认）：

```sql
SELECT COUNT(*) AS 不是211班 FROM students WHERE class_name <> '软工211班';
```

```text
+--------------+
| 不是211班    |
+--------------+
|          150 |
+--------------+
```

**值必须加引号，日期也是。** 不加引号不会报错，MySQL 会把它当成算术题：

```sql
SELECT 2005-09-01 AS 没加引号的结果;
```

```text
+-----------------------+
| 没加引号的结果        |
+-----------------------+
|                  1995 |
+-----------------------+
```

所以 `birth_date > 2005-12-01` 实际在问「比 1995 大吗」，答案自然是全部：

```sql
SELECT COUNT(*) AS 没引号_20051201 FROM students WHERE birth_date > 2005-12-01;
SELECT COUNT(*) AS 加引号_20051201 FROM students WHERE birth_date > '2005-12-01';
```

```text
+--------------------+
| 没引号_20051201    |
+--------------------+
|                200 |
+--------------------+
+--------------------+
| 加引号_20051201    |
+--------------------+
|                109 |
+--------------------+
```

同一个条件，200 和 109，**不报错的那种错最难受**。

### 2. AND 和 OR：先算错一次

需求：「软工211班的男生，或者北京的学生」。先看看三个基础数字：

```sql
SELECT
  (SELECT COUNT(*) FROM students WHERE gender='男' AND class_name='软工211班') AS 男生且211班,
  (SELECT COUNT(*) FROM students WHERE city='北京')                             AS 北京,
  (SELECT COUNT(*) FROM students WHERE gender='男' AND class_name='软工211班' AND city='北京') AS 三个都要;
```

```text
+-----------------+--------+--------------+
| 男生且211班     | 北京   | 三个都要     |
+-----------------+--------+--------------+
|              25 |     33 |            8 |
+-----------------+--------+--------------+
```

你的第一反应八成是 8：三个条件都得满足。现在实跑不带括号的版本：

```sql
SELECT COUNT(*) AS 无括号 FROM students
WHERE gender='男' AND class_name='软工211班' OR city='北京';
```

```text
+-----------+
| 无括号    |
+-----------+
|        50 |
+-----------+
```

50，不是 8。**`AND` 的优先级比 `OR` 高**，数据库把它读成 `(男 且 211班) 或 北京`：25 个 211 班男生，**并上** 33 个北京人，交集 8 人只算一次 —— 25 + 33 − 8 = 50。

那我加括号总行了吧：

```sql
SELECT COUNT(*) AS 加括号 FROM students
WHERE gender='男' AND (class_name='软工211班' OR city='北京');
```

```text
+-----------+
| 加括号    |
+-----------+
|        50 |
+-----------+
```

**也是 50，纯属巧合**，别误以为括号没用。看一眼就明白：

```sql
SELECT gender, COUNT(*) AS n FROM students WHERE city='北京' GROUP BY gender;
```

```text
+--------+----+
| gender | n  |
+--------+----+
| 男     | 33 |
+--------+----+
```

北京的 33 人**全是男生**，所以「北京人」和「北京男生」是同一批人，两种括号写法自然撞出同一个数字。把条件里的北京换成上海，立刻打脸：

```sql
SELECT COUNT(*) AS 无括号_上海 FROM students
WHERE gender='男' AND class_name='软工211班' OR city='上海';
SELECT COUNT(*) AS 加括号_上海 FROM students
WHERE gender='男' AND (class_name='软工211班' OR city='上海');
```

```text
+------------------+
| 无括号_上海      |
+------------------+
|               59 |
+------------------+
+------------------+
| 加括号_上海      |
+------------------+
|               25 |
+------------------+
```

59 和 25，差的全是「上海女生」。**有 AND 又有 OR，就把你的意图用括号写明白**，别让数据库替你猜 —— 它猜的永远是标准优先级，不是你脑子里那个。

### 3. LIKE：% 是「任意多个字符」，_ 是「正好一个字符」

```sql
SELECT name FROM students WHERE name LIKE '王%' ORDER BY name;
```

```text
+-----------+
| name      |
+-----------+
| 王丽      |
| 王伟      |
| 王军杰    |
| 王刚      |
| 王勇      |
| 王娜      |
| 王娟      |
| 王平      |
| 王强磊    |
| 王敏      |
| 王明超    |
| 王桂      |
| 王洋      |
| 王涛      |
| 王秀英    |
| 王艳      |
| 王芳      |
| 王英      |
| 王霞      |
| 王静      |
+-----------+
```

`%` 放在后面 = 「姓王，后面爱几个字几个字」，20 个全在。`%` 放前面是「以它结尾」：

```sql
SELECT name FROM students WHERE name LIKE '%伟' ORDER BY name;
```

```text
+--------+
| name   |
+--------+
| 冯伟   |
| 吴伟   |
| 周伟   |
| 孙伟   |
| 李伟   |
| 王伟   |
| 赵伟   |
| 郑伟   |
| 钱伟   |
| 陈伟   |
+--------+
```

`_` 完全不同，它**只占一个字**。这两句的差别就是重点：

```sql
SELECT name FROM students WHERE name LIKE '赵%伟' ORDER BY name;
SELECT COUNT(*) AS 赵_伟 FROM students WHERE name LIKE '赵_伟';
```

```text
+--------+
| name   |
+--------+
| 赵伟   |
+--------+
+---------+
| 赵_伟   |
+---------+
|       0 |
+---------+
```

`赵%伟` 能查到赵伟 —— `%` 允许是 0 个字符；`赵_伟` 要求「赵 + 恰好 1 个字 + 伟」，表里没有这种名字，所以 0 行。把下划线补够就通了：

```sql
SELECT name FROM students WHERE name LIKE '赵__' ORDER BY name;
```

```text
+-----------+
| name      |
+-----------+
| 赵军杰    |
| 赵强磊    |
| 赵明超    |
| 赵秀英    |
+-----------+
```

记法很土但好用：**`%` 是懒人（几个字都行），`_` 是一个萝卜一个坑**。

### 4. IN 与 BETWEEN：闭区间，顺序别反

「城市是北京、上海、深圳之一」写成三个 `OR` 太啰嗦，用 `IN`：

```sql
SELECT name, city FROM students WHERE city IN ('北京', '上海') ORDER BY city, name LIMIT 6;
SELECT COUNT(*) AS 三城 FROM students WHERE city IN ('北京', '上海', '深圳');
```

```text
+-----------+--------+
| name      | city   |
+-----------+--------+
| 冯娜      | 上海   |
| 冯明超    | 上海   |
| 冯洋      | 上海   |
| 吴娜      | 上海   |
| 吴明超    | 上海   |
| 吴洋      | 上海   |
+-----------+--------+
+--------+
| 三城   |
+--------+
|    100 |
+--------+
```

`BETWEEN` 管一段范围，**两端都算**（这叫闭区间）。先看一条反面教材：

```sql
SELECT COUNT(*) AS 大纲区间 FROM students WHERE birth_date BETWEEN '2005-09-01' AND '2006-09-01';
```

```text
+--------------+
| 大纲区间     |
+--------------+
|          200 |
+--------------+
```

200 = 全班。本表出生日期从 2005-09-02 到 2006-03-20，**整个落在这个区间里** —— 条件没写错，是区间选得太宽。写 `BETWEEN` 之前先看一眼数据范围。换成十月验证闭区间：

```sql
SELECT COUNT(*) AS 十月 FROM students WHERE birth_date BETWEEN '2005-10-01' AND '2005-10-31';
SELECT COUNT(*) AS 单日 FROM students WHERE birth_date BETWEEN '2005-10-01' AND '2005-10-01';
SELECT COUNT(*) AS 写反 FROM students WHERE birth_date BETWEEN '2006-09-01' AND '2005-09-01';
```

```text
+--------+
| 十月   |
+--------+
|     31 |
+--------+
+--------+
| 单日   |
+--------+
|      1 |
+--------+
+--------+
| 写反   |
+--------+
|      0 |
+--------+
```

- **31**：10 月 1 日到 10 月 31 日，两个端点都在里面，31 天一个不少
- **1**：起点和终点是同一天也成立 —— 这就是「闭」的意思
- **0**：顺序写反了**不报错**，MySQL 认为这个区间里没有数据，安静地给你 0 行

### 5. NULL：为什么 `= NULL` 永远查不到

先跑一句大纲里的原话 —— 这表压根没有 `remark` 列：

```sql
SELECT * FROM order_items WHERE remark IS NULL;
```

```text
ERROR 1054 (42S22) at line 1: Unknown column 'remark' in 'where clause'
```

列名错了它会告诉你。那换成真的可空列，先看看全库哪些列允许 NULL：

```sql
SELECT TABLE_NAME, COLUMN_NAME FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = 'easy_mysql' AND IS_NULLABLE = 'YES'
ORDER BY TABLE_NAME, ORDINAL_POSITION;
```

```text
+-----------------+-------------+
| TABLE_NAME      | COLUMN_NAME |
+-----------------+-------------+
| bad_design_demo | extra       |
| bad_design_demo | remark      |
+-----------------+-------------+
```

全库就这两列。注意「**允许 NULL**」和「**现在有 NULL**」是两码事 —— 这 20 行的 `remark` 全填了值：

```sql
SELECT COUNT(*) AS remark为空的 FROM bad_design_demo WHERE remark IS NULL;
```

```text
+-----------------+
| remark为空的    |
+-----------------+
|               0 |
+-----------------+
```

库里现在没有 NULL 行，那就让查询自己吐一个 NULL 出来，看两种写法的差别（不碰任何表）：

```sql
SELECT COUNT(*) AS 用IS_NULL FROM (SELECT NULL AS n) t WHERE t.n IS NULL;
SELECT COUNT(*) AS 用等号    FROM (SELECT NULL AS n) t WHERE t.n = NULL;
SELECT NULL = NULL AS 等号结果, NULL IS NULL AS IS结果;
```

```text
+------------+
| 用IS_NULL  |
+------------+
|          1 |
+------------+
+-----------+
| 用等号    |
+-----------+
|         0 |
+-----------+
+--------------+----------+
| 等号结果     | IS结果   |
+--------------+----------+
|         NULL |        1 |
+--------------+----------+
```

**1 对 0，全部秘密在上面那张表里**：`NULL = NULL` 的结果是 `NULL`，不是 `1`。NULL 的意思是「不知道」，「不知道等于不知道吗」—— 数据库老实回答：不知道。而 WHERE 只保留结果为**真**的行，「不知道」不等于真，所以一行都进不来：

```sql
SELECT COUNT(*) AS students用等号 FROM students WHERE city = NULL;
```

```text
+-------------------+
| students用等号    |
+-------------------+
|                 0 |
+-------------------+
```

`city` 明明 200 行都有值，`city = NULL` 照样 0 行 —— 写法本身就错了。**判断 NULL 只能用 `IS NULL` / `IS NOT NULL`。** 自己插一行 NULL 看效果，配套实验的第 5 节有现成的（插完会删掉，不会留垃圾）。

### 6. 实战：四个条件一层层剥

需求：「北京或上海、2006 年之前出生、名字里带伟」的男生。别一口气写完，**分四步，每步看还剩多少人**：

```sql
SELECT COUNT(*) AS 1京沪     FROM students WHERE city IN ('北京', '上海');
SELECT COUNT(*) AS 2再减2006 FROM students WHERE city IN ('北京', '上海') AND birth_date < '2006-01-01';
SELECT COUNT(*) AS 3再减带伟 FROM students WHERE city IN ('北京', '上海') AND birth_date < '2006-01-01'
                                                                AND name LIKE '%伟%';
SELECT COUNT(*) AS 4再减男生 FROM students WHERE city IN ('北京', '上海') AND birth_date < '2006-01-01'
                                                                AND name LIKE '%伟%' AND gender = '男';
```

```text
+---------+
| 1京沪   |
+---------+
|      67 |
+---------+
+-------------+
| 2再减2006   |
+-------------+
|          41 |
+-------------+
+---------------+
| 3再减带伟     |
+---------------+
|             3 |
+---------------+
+---------------+
| 4再减男生     |
+---------------+
|             0 |
+---------------+
```

67 → 41 → 3 → 0。第三步还剩 3 个人，看看他们是谁：

```sql
SELECT name, city, birth_date, gender FROM students
WHERE city IN ('北京', '上海') AND birth_date < '2006-01-01' AND name LIKE '%伟%'
ORDER BY name;
```

```text
+--------+--------+------------+--------+
| name   | city   | birth_date | gender |
+--------+--------+------------+--------+
| 李伟   | 上海   | 2005-11-01 | 女     |
| 赵伟   | 上海   | 2005-09-02 | 女     |
| 郑伟   | 上海   | 2005-12-31 | 女     |
+--------+--------+------------+--------+
```

三个全是女生，所以第四步的 `gender='男'` 把人全筛没了：

```sql
SELECT COUNT(*) AS 结果 FROM students
WHERE city IN ('北京', '上海') AND birth_date < '2006-01-01' AND name LIKE '%伟%' AND gender = '男';
```

```text
+--------+
| 结果   |
+--------+
|      0 |
+--------+
```

**0 行也是正确答案**，前提是你知道它为什么是 0。写复杂条件时别指望一次写对：每加一个条件就 `COUNT(*)` 一次，人是怎么少掉的一目了然。这也回答了开头那个问题：`LIKE '%伟%' AND gender='男'` 查出 0 行，不是你 WHERE 写错了，是这份数据里叫「伟」的 10 个人全是女生。

## 三个必须记住的结论

1. **`AND` 先算、`OR` 后算**，优先级搞错不报错、只给错结果；有 AND 又有 OR，就把括号写上
2. **`%` 匹配任意多个字符，`_` 只匹配一个字符**；`BETWEEN` 两端都包含，顺序写反不报错、只给 0 行
3. **NULL 只能用 `IS NULL` 判断**：`= NULL` 的答案永远是「不知道」，任何一行都查不出来

## 常见错误

### ❌ 字符串值忘了加引号

```sql
SELECT name FROM students WHERE city = 北京;
```

```text
ERROR 1054 (42S22) at line 1: Unknown column '北京' in 'where clause'
```

**为什么错**：不加引号时 MySQL 把 `北京` 当成列名去找，表里没有叫这个名字的列。它以为你在引用一列，其实你想给一个值。

**正确做法**：

```sql
SELECT name, city FROM students WHERE city = '北京' ORDER BY id LIMIT 5;
```

值（字符串、日期）一律加单引号；只有列名不加。数字可以不加，但日期必须加 —— 不加就成了算术题（第 1 节实测过）。

## 动手练

- [ ] 软工210班有多少女生？（两个条件，用 `AND` 连）
- [ ] 查出生日在 2005-12-25 到 2006-01-05 之间（含两端）的学生，一共几人？
- [ ] 想要「姓王、名字至少两个字」的学生，`LIKE` 该怎么写？查出来几人？
- [ ] 想一想：`SELECT * FROM students WHERE city IN (NULL);` 会查到什么？为什么？

<details>
<summary>点开看答案</summary>

```sql
-- 第 1 题：25 人
SELECT COUNT(*) AS 软工210班女生 FROM students WHERE class_name = '软工210班' AND gender = '女';
```

```text
+--------------------+
| 软工210班女生      |
+--------------------+
|                 25 |
+--------------------+
```

```sql
-- 第 2 题：12 人（注意 BETWEEN 两端都算）
SELECT COUNT(*) AS 圣诞到元旦 FROM students WHERE birth_date BETWEEN '2005-12-25' AND '2006-01-05';
```

```text
+-----------------+
| 圣诞到元旦      |
+-----------------+
|              12 |
+-----------------+
```

```sql
-- 第 3 题：王 + 两个下划线 + 任意长度，4 人
SELECT name FROM students WHERE name LIKE '王__%' ORDER BY name;
```

```text
+-----------+
| name      |
+-----------+
| 王军杰    |
| 王强磊    |
| 王明超    |
| 王秀英    |
+-----------+
```

```sql
-- 第 4 题：0 行。IN (NULL) 里的比较结果是「不知道」，不是真，
-- 所以和 = NULL 一样，一行都进不来。要找 NULL 得写 IS NULL：
SELECT COUNT(*) AS 用IN_NULL FROM students WHERE city IN (NULL);
```

```text
+------------+
| 用IN_NULL  |
+------------+
|          0 |
+------------+
```

</details>

## 配套实验

```powershell
docker cp lab/queries/04-demo-where.sql easy-mysql:/tmp/
docker exec easy-mysql mysql -uroot -peasy123 -t -e "source /tmp/04-demo-where.sql"
```

> 实验第 5 节会临时插一行 NULL 再删掉，结尾的自检会确认 `bad_design_demo` 还是 20 行。

## 下一篇

[05 · 排序、分页与聚合：COUNT / SUM / AVG / MAX / MIN](05-order-limit-aggregate.md)
