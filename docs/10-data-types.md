# 10 · 数据类型怎么选：看完一张丑表，你就不会选错

> **一句话价值**：拿 `bad_design_demo` 这张反面教材逐字段拆一遍，每个字段该用什么类型，你都能说出实测证据。

**难度**：⭐⭐　|　**时长**：约 30 分钟　|　**涉及表**：`bad_design_demo`

## 什么时候你会遇到它

同学把 Excel 名单导进数据库，生日那一列是字符串：按生日排序，1 月 1 日的李四排到了 9 月 18 日后面；按 `birthday > '2005-06-30'` 查下半年出生的人，7 月 15 日的刘六又漏了。财务问你订单总额，你盯着 `229.80000000000004` 不知道该不该信。

这些都不是 bug，是**建表那一刻类型就选错了** —— `bad_design_demo` 就是这么一张：9 个字段，7 个标了 ✗。

## 本篇你会学到

- [ ] 数值类型：`TINYINT` ~ `BIGINT`、`DECIMAL` 为什么不能用 `FLOAT` 存钱
- [ ] 字符串：`VARCHAR(N)` 的 N 限制什么、`TEXT` 什么时候用
- [ ] 日期时间：`DATE` / `DATETIME` / `TIMESTAMP` 三者区别
- [ ] `ENUM`/`SET` 的取舍，`NULL` 和「空字符串」的区别
- [ ] **选型速查表**

---

## 1. 先看这张丑表

**问题**：一张表摆在你面前，怎么快速看出它哪里错了？

**答案**：`DESC` 看类型，`SELECT` 看真实数据，两件事一起做。

```sql
DESC bad_design_demo;
SELECT * FROM bad_design_demo LIMIT 5;
-- VARCHAR(200) 里的 200 数的是「字符」不是「字节」：utf8mb4 下一个汉字吃 4 个字节
SELECT CHAR_LENGTH('张三吃饱了') AS 字符数, LENGTH('张三吃饱了') AS 字节数;
```

```text
+-------------+-----------------+------+-----+---------+----------------+
| Field       | Type            | Null | Key | Default | Extra          |
+-------------+-----------------+------+-----+---------+----------------+
| id          | bigint unsigned | NO   | PRI | NULL    | auto_increment |
| user_name   | varchar(200)    | NO   |     | NULL    |                |
| birthday    | varchar(50)     | NO   |     | NULL    |                |
| phone       | double          | NO   |     | NULL    |                |
| price       | varchar(50)     | NO   |     | NULL    |                |
| is_man      | varchar(10)     | NO   |     | NULL    |                |
| create_time | varchar(50)     | NO   |     | NULL    |                |
| extra       | json            | YES  |     | NULL    |                |
| remark      | text            | YES  |     | NULL    |                |
+-------------+-----------------+------+-----+---------+----------------+
+----+-----------+------------+-------------+---------+--------+---------------------+------------------------------+-----------------------+
| id | user_name | birthday   | phone       | price   | is_man | create_time         | extra                        | remark                |
+----+-----------+------------+-------------+---------+--------+---------------------+------------------------------+-----------------------+
|  1 | 钱小1     | 2005-02-11 | 13800001000 | 1.99元  | 否     | 2024-01-02 10:00:00 | {"vip": 0, "source": "web"}  | 教学用反面教材        |
|  2 | 孙小2     | 2005-03-12 | 13800002000 | 2.99元  | 是     | 2024-01-03 10:00:00 | {"vip": 0, "source": "mini"} | 教学用反面教材        |
|  3 | 李小3     | 2005-04-13 | 13800003000 | 3.99元  | 否     | 2024-01-04 10:00:00 | {"vip": 1, "source": "pc"}   | 教学用反面教材        |
|  4 | 周小4     | 2005-05-14 | 13800004000 | 4.99元  | 是     | 2024-01-05 10:00:00 | {"vip": 0, "source": "app"}  | 教学用反面教材        |
|  5 | 吴小5     | 2005-06-15 | 13800005000 | 5.99元  | 否     | 2024-01-06 10:00:00 | {"vip": 0, "source": "web"}  | 教学用反面教材        |
+----+-----------+------------+-------------+---------+--------+---------------------+------------------------------+-----------------------+
+-----------+-----------+
| 字符数    | 字节数    |
+-----------+-----------+
|         5 |        15 |
+-----------+-----------+
```

逐字段过一遍，除了 `id` 和 `remark`，没一个能及格：

| 字段 | 现在的类型 | 毛病 |
|---|---|---|
| `user_name` | `VARCHAR(200)` | 名字最长 30 字符，200 是白留的空位；utf8mb4 下一列最坏要 800 字节 |
| `birthday` | `VARCHAR(50)` | 存日期，比较走字典序，第 5 节实测翻车 |
| `phone` | `DOUBLE` | 手机号不是数：前导 0 会被吃掉，11 位以上会丢精度 |
| `price` | `VARCHAR(50)` | 金额是字符串：求和靠猜，单位一混直接算错 |
| `is_man` | `VARCHAR(10)` | 布尔存字符串，`'false'` 在数值上下文里等于 0 |
| `create_time` | `VARCHAR(50)` | 时间是字符串，`LIKE '2024%'` 换个格式就漏数据 |
| `extra` | `JSON` | 把该拆列的东西全塞进 JSON，查询和约束都做不了 |

`CHAR_LENGTH` 那行解释了 `VARCHAR(N)` 的 N：**数的是字符数，不是字节数** —— utf8mb4 下 `VARCHAR(30)` 要留 30×4+2 字节，给多浪费、给少截断。`TEXT` 装长度不可控的内容，代价是两条硬限制：

```sql
CREATE TABLE t_txt (id INT PRIMARY KEY, body TEXT NOT NULL DEFAULT 'x');
```

```text
ERROR 1101 (42000) at line 1: BLOB, TEXT, GEOMETRY or JSON column 'body' can't have a default value
```

```sql
CREATE TABLE t_txt (id INT PRIMARY KEY, body TEXT);
CREATE INDEX idx_body ON t_txt (body);
DROP TABLE t_txt;
```

```text
ERROR 1170 (42000) at line 1: BLOB/TEXT column 'body' used in key specification without a key length
```

没有默认值、索引必须截断前缀，**能用 `VARCHAR` 就别用 `TEXT`**。

## 2. 金额：钱用 DECIMAL，浮点和字符串都不行

**问题**：金额用 `FLOAT` 或字符串存，行不行？

**答案**：字符串会算错，浮点会算歪，只有定点数（DECIMAL，exact numeric）能一分不差。

先看字符串的下场。`SUM(price)` 表面算出来了，其实每行都在被强行转数字：

```sql
SELECT SUM(price) FROM bad_design_demo;
SHOW WARNINGS;   -- 20 条 Truncated incorrect DOUBLE value
```

```text
+--------------------+
| SUM(price)         |
+--------------------+
| 229.80000000000004 |
+--------------------+
+---------+------+----------------------------------------------+
| Level   | Code | Message                                      |
+---------+------+----------------------------------------------+
| Warning | 1292 | Truncated incorrect DOUBLE value: '1.99元'   |
| Warning | 1292 | Truncated incorrect DOUBLE value: '2.99元'   |
| Warning | 1292 | Truncated incorrect DOUBLE value: '3.99元'   |
| Warning | 1292 | Truncated incorrect DOUBLE value: '4.99元'   |
| Warning | 1292 | Truncated incorrect DOUBLE value: '5.99元'   |
| Warning | 1292 | Truncated incorrect DOUBLE value: '6.99元'   |
| Warning | 1292 | Truncated incorrect DOUBLE value: '7.99元'   |
| Warning | 1292 | Truncated incorrect DOUBLE value: '8.99元'   |
| Warning | 1292 | Truncated incorrect DOUBLE value: '9.99元'   |
| Warning | 1292 | Truncated incorrect DOUBLE value: '10.99元'  |
| Warning | 1292 | Truncated incorrect DOUBLE value: '11.99元'  |
| Warning | 1292 | Truncated incorrect DOUBLE value: '12.99元'  |
| Warning | 1292 | Truncated incorrect DOUBLE value: '13.99元'  |
| Warning | 1292 | Truncated incorrect DOUBLE value: '14.99元'  |
| Warning | 1292 | Truncated incorrect DOUBLE value: '15.99元'  |
| Warning | 1292 | Truncated incorrect DOUBLE value: '16.99元'  |
| Warning | 1292 | Truncated incorrect DOUBLE value: '17.99元'  |
| Warning | 1292 | Truncated incorrect DOUBLE value: '18.99元'  |
| Warning | 1292 | Truncated incorrect DOUBLE value: '19.99元'  |
| Warning | 1292 | Truncated incorrect DOUBLE value: '20.99元'  |
+---------+------+----------------------------------------------+
```

类型不匹配在 `SELECT` 里只是**警告**，不拦你，于是 `229.80000000000004` 就端上来了。这次格式统一凑合还对，混进一个千分位或一个单位，结果直接崩：

```sql
CREATE TEMPORARY TABLE t_money (
  label VARCHAR(10) NOT NULL,
  price VARCHAR(20) NOT NULL
);
INSERT INTO t_money VALUES ('A','1,999.00元'), ('B','2.00元');
SELECT SUM(price) AS 字符串直接求和,
       SUM(CAST(REPLACE(REPLACE(price,'元',''),',','') AS DECIMAL(10,2))) AS 清洗后再求和
FROM t_money;
DROP TEMPORARY TABLE t_money;
-- 对照：DECIMAL 列求和，一次到位
SELECT ROUND(SUM(amount), 2) AS 订单总额 FROM orders;
```

```text
+-----------------------+--------------------+
| 字符串直接求和        | 清洗后再求和       |
+-----------------------+--------------------+
|                     3 |            2001.00 |
+-----------------------+--------------------+
+--------------+
| 订单总额     |
+--------------+
| 605490225.57 |
+--------------+
```

**`1,999.00元` 被读成了 `1`**，2001 的总额算成 3，还不报错。金额列必须 `DECIMAL(10,2)`：`10` 是总位数、`2` 是小数位，全由十进制精确运算，不碰二进制。

再看浮点数（FLOAT/DOUBLE，approximate numeric）。有个反直觉的地方必须实测：

```sql
SELECT 0.1 + 0.2 = 0.3 AS 字面量直接比,
       CAST(0.1 AS DOUBLE) + CAST(0.2 AS DOUBLE) AS DOUBLE相加,
       CAST(0.1 AS DOUBLE) + CAST(0.2 AS DOUBLE) = 0.3 AS DOUBLE比,
       CAST(0.1 AS DECIMAL(10,2)) + CAST(0.2 AS DECIMAL(10,2)) = 0.3 AS DECIMAL比;
CREATE TEMPORARY TABLE t_float (price FLOAT NOT NULL);
INSERT INTO t_float VALUES (0.1), (0.2);
SELECT SUM(price) AS FLOAT列求和, SUM(price) = 0.3 AS `等于0.3吗` FROM t_float;
DROP TEMPORARY TABLE t_float;
```

```text
+--------------------+---------------------+-----------+------------+
| 字面量直接比       | DOUBLE相加          | DOUBLE比  | DECIMAL比  |
+--------------------+---------------------+-----------+------------+
|                  1 | 0.30000000000000004 |         0 |          1 |
+--------------------+---------------------+-----------+------------+
+---------------------+--------------+
| FLOAT列求和         | 等于0.3吗    |
+---------------------+--------------+
| 0.30000000447034836 |            0 |
+---------------------+--------------+
```

四列四种命运：MySQL 把字面量当**精确小数**处理，直接写 `0.1+0.2=0.3` 居然是 1，误差被藏住了；显式转 `DOUBLE`，`0.30000000000000004` 立刻现形；存进 `FLOAT` 列求和是 `0.30000000447034836`，比 `DOUBLE` 还歪。**别信「0.1+0.2 等于 0.3」的直觉**，那只是字面量的障眼法 —— 列是什么类型，结果就按什么类型算。

## 3. 手机号：它不是数

**问题**：手机号用 `DOUBLE` 或 `BIGINT` 不行吗？11 位而已。

**答案**：不行。它是**标识符**不是数量，前导 0、`+86`、短横线都是有意义的。

```sql
CREATE TEMPORARY TABLE t_phone (
  phone DOUBLE NOT NULL,
  note  VARCHAR(30) NOT NULL
);
INSERT INTO t_phone VALUES ('01381234567', '前导 0 写进 DOUBLE');
SELECT phone, CAST(phone AS UNSIGNED) AS 读回来的样子 FROM t_phone;
DROP TEMPORARY TABLE t_phone;
-- 19 位数字：存进去和读回来已经不是一个数
SELECT 1381234567890123456 AS 原始号码,
       CAST(1381234567890123456 AS DOUBLE) AS 存进DOUBLE,
       CAST(CAST(1381234567890123456 AS DOUBLE) AS UNSIGNED) AS 读回来,
       CAST(CAST(1381234567890123456 AS DOUBLE) AS UNSIGNED) = 1381234567890123456 AS 读回来还一样吗;
-- 换成 BIGINT 也一样：前导 0 直接没了
SELECT CAST('01381234567' AS UNSIGNED) AS BIGINT结果;
```

```text
+------------+--------------------+
| phone      | 读回来的样子       |
+------------+--------------------+
| 1381234567 |         1381234567 |
+------------+--------------------+
+---------------------+-----------------------+---------------------+-----------------------+
| 原始号码            | 存进DOUBLE            | 读回来              | 读回来还一样吗        |
+---------------------+-----------------------+---------------------+-----------------------+
| 1381234567890123456 | 1.3812345678901235e18 | 1381234567890123520 |                     0 |
+---------------------+-----------------------+---------------------+-----------------------+
+--------------+
| BIGINT结果   |
+--------------+
|   1381234567 |
+--------------+
```

三个证据：前导 0 没了；19 位号码存 `DOUBLE` 读回来变成 `...3520`，**和原值不相等**；换 `BIGINT` 照样丢 0。`DOUBLE` 只有约 15~17 位有效数字，`BIGINT UNSIGNED` 吃不下 `+86` 和分隔符 —— 手机号、身份证、学号、订单号统统 `VARCHAR(20)`。

## 4. 布尔：`'false'` 在 MySQL 里等于 0

**问题**：性别、是否会员这类真假值，存成 `'是'/'否'` 或 `'true'/'false'` 字符串行不行？

**答案**：只要查询里出现数字，字符串就会被转成数字，而**任何转不成数字的字符串都等于 0**。

```sql
SELECT 'false' + 0 AS 加法里是几,
       'false' = 0 AS 等于0吗,
       'false' = 1 AS 等于1吗;
SELECT COUNT(*) AS 用is_man等于0来找 FROM bad_design_demo WHERE is_man = 0;
SELECT COUNT(*) AS 用is_man等于否来找 FROM bad_design_demo WHERE is_man = '否';
SELECT COUNT(*) AS 用is_man等于false来找 FROM bad_design_demo WHERE is_man = 'false';
```

```text
+-----------------+------------+------------+
| 加法里是几      | 等于0吗    | 等于1吗    |
+-----------------+------------+------------+
|               0 |          1 |          0 |
+-----------------+------------+------------+
+------------------------+
| 用is_man等于0来找      |
+------------------------+
|                     20 |
+------------------------+
+--------------------------+
| 用is_man等于否来找       |
+--------------------------+
|                       10 |
+--------------------------+
+----------------------------+
| 用is_man等于false来找      |
+----------------------------+
|                          0 |
+----------------------------+
```

最狠的是第二条：`WHERE is_man = 0` **全表 20 行全中**，因为 `'是'`、`'否'` 转数字都是 0；`WHERE is_man = 'false'` 一行没有，因为表里存的是中文。这种 bug 不报错、不慢，结果悄悄错。MySQL 没有原生布尔类型，`BOOL`/`BOOLEAN` 就是 `TINYINT(1)` 的别名：存 `1`/`0`，判断写 `WHERE is_man = 1`。

## 5. 日期：字符串一比就乱

**问题**：生日、下单时间用字符串存，看着排序也对啊？

**答案**：格式统一时碰巧对，格式一乱立刻错。基线这 20 行是脚本生成的、格式规整，看不出毛病：

```sql
SELECT user_name, birthday FROM bad_design_demo ORDER BY birthday LIMIT 5;
```

```text
+-----------+------------+
| user_name | birthday   |
+-----------+------------+
| 冯小18    | 2005-01-10 |
| 陈小9     | 2005-01-10 |
| 钱小1     | 2005-02-11 |
| 陈小19    | 2005-02-11 |
| 赵小10    | 2005-02-11 |
+-----------+------------+
```

混进一条真实世界到处都有的**不补零**日期，字典序立刻露馅：

```sql
CREATE TEMPORARY TABLE t_date_sort (
  user_name VARCHAR(20) NOT NULL,
  birthday  VARCHAR(20) NOT NULL
);
INSERT INTO t_date_sort VALUES
  ('张三','2005-09-18'), ('李四','2005-1-1'),
  ('王五','2005-02-11'), ('刘六','2005-7-15');
SELECT user_name, birthday FROM t_date_sort ORDER BY birthday;
DROP TEMPORARY TABLE t_date_sort;
```

```text
+-----------+------------+
| user_name | birthday   |
+-----------+------------+
| 王五      | 2005-02-11 |
| 张三      | 2005-09-18 |
| 李四      | 2005-1-1   |
| 刘六      | 2005-7-15  |
+-----------+------------+
```

逐字符比：`'2005-1-1'` 第 5 位是 `1`，比所有 `'2005-0X'` 都大，于是**李四掉到了队尾**，刘六排在 9 月之后。换成 `DATE` 列：

```sql
CREATE TEMPORARY TABLE t_date_sort_ok (
  user_name VARCHAR(20) NOT NULL,
  birthday  DATE        NOT NULL
);
INSERT INTO t_date_sort_ok VALUES
  ('张三','2005-09-18'), ('李四','2005-1-1'),
  ('王五','2005-02-11'), ('刘六','2005-7-15');
SELECT user_name, birthday FROM t_date_sort_ok ORDER BY birthday;
DROP TEMPORARY TABLE t_date_sort_ok;
```

```text
+-----------+------------+
| user_name | birthday   |
+-----------+------------+
| 李四      | 2005-01-01 |
| 王五      | 2005-02-11 |
| 刘六      | 2005-07-15 |
| 张三      | 2005-09-18 |
+-----------+------------+
```

顺序对了，`2005-1-1` 还被自动规整成 `2005-01-01`。字符串时间连范围查询也靠不住：

```sql
SELECT COUNT(*) AS 字符串表LIKE出的2024年 FROM bad_design_demo WHERE create_time LIKE '2024%';
SELECT COUNT(*) AS 日期列范围查出的 FROM orders
WHERE created_at >= '2024-01-01' AND created_at < '2025-01-01';
```

```text
+-------------------------------+
| 字符串表LIKE出的2024年        |
+-------------------------------+
|                            20 |
+-------------------------------+
+--------------------------+
| 日期列范围查出的         |
+--------------------------+
|                   200000 |
+--------------------------+
```

`LIKE '2024%'` 这次对了是格式凑巧 —— 它只匹配前缀，日期写成 `2024/1/5` 或 `20240105` 就被静默漏掉，也没法表达「整一年」。正解是日期列的 `>= ... AND < ...`；前缀匹配该不该走索引，是第 13、14 篇的话题。

**日期三兄弟对照表**（术语：日期时间类型，date/time types）：

| 类型 | 存什么 | 时区 | 范围 |
|---|---|---|---|
| `DATE` | `2005-09-01` | 无 | 1000-01-01 ~ 9999-12-31 |
| `DATETIME` | `2005-09-01 13:00:00` | 无，存什么读什么 | 1000-01-01 ~ 9999-12-31 23:59:59 |
| `TIMESTAMP` | 同 `DATETIME` | **存 UTC，读时按会话时区换算** | 1970-01-01 00:00:01 UTC ~ **2038-01-19 03:14:07** UTC |

时区那一条是跑出来的（`ts` 是 `TIMESTAMP`，`dt` 是 `DATETIME`）：

```sql
CREATE TEMPORARY TABLE t_dates (
  id INT NOT NULL,
  d  DATE NULL,
  dt DATETIME NULL,
  ts TIMESTAMP NULL,
  PRIMARY KEY (id)
);
SET time_zone = '+00:00';
INSERT INTO t_dates (id, d, dt, ts) VALUES (1, '2025-06-01', '2025-06-01 13:00:00', '2025-06-01 13:00:00');
SELECT '+00:00 会话里读' AS 会话时区, d, dt, ts FROM t_dates;
SET time_zone = '+08:00';
SELECT '+08:00 会话里读' AS 会话时区, d, dt, ts FROM t_dates;
```

```text
+---------------------+------------+---------------------+---------------------+
| 会话时区            | d          | dt                  | ts                  |
+---------------------+------------+---------------------+---------------------+
| +00:00 会话里读     | 2025-06-01 | 2025-06-01 13:00:00 | 2025-06-01 13:00:00 |
+---------------------+------------+---------------------+---------------------+
+---------------------+------------+---------------------+---------------------+
| 会话时区            | d          | dt                  | ts                  |
+---------------------+------------+---------------------+---------------------+
| +08:00 会话里读     | 2025-06-01 | 2025-06-01 13:00:00 | 2025-06-01 21:00:00 |
+---------------------+------------+---------------------+---------------------+
```

同样的数据，会话时区从 `+00:00` 切到 `+08:00`，`TIMESTAMP` 的 `13:00:00` 变成了 `21:00:00`，`DATETIME` 纹丝不动。**`TIMESTAMP` 会跟着时区跑，`DATETIME` 不会** —— 服务器搬家、用户跨国访问时，这个差别就是线上事故的来源。范围上：

```sql
INSERT INTO t_dates (id, d, dt, ts) VALUES (2, '9999-12-31', '9999-12-31 23:59:59', NULL);
SELECT 'DATETIME 撑到 9999' AS 提示, id, d, dt, ts FROM t_dates WHERE id = 2;
SET time_zone = SYSTEM;
DROP TEMPORARY TABLE t_dates;
```

```text
+----------------------+----+------------+---------------------+------+
| 提示                 | id | d          | dt                  | ts   |
+----------------------+----+------------+---------------------+------+
| DATETIME 撑到 9999   |  2 | 9999-12-31 | 9999-12-31 23:59:59 | NULL |
+----------------------+----+------------+---------------------+------+
```

`DATETIME` 轻松写到 9999 年，而 `TIMESTAMP` 一过 2038 年就翻脸：

```sql
SET time_zone = '+00:00';
CREATE TEMPORARY TABLE t2038 (ts TIMESTAMP NULL);
INSERT INTO t2038 VALUES ('2038-01-20 00:00:00');
```

```text
ERROR 1292 (22007) at line 1: Incorrect datetime value: '2038-01-20 00:00:00' for column 'ts' at row 1
```

**默认选 `DATETIME`**：不折腾时区、范围到 9999、读写直观；只有跨时区统一时刻是刚需、且你清楚 UTC 存储策略时才用 `TIMESTAMP`。

## 6. ENUM 和 SET：能用，但别上瘾

**问题**：状态、性别这种固定取值，用枚举（ENUM，一组命名常量）还是 `VARCHAR`？

**答案**：取值**真的固定、几乎不变**时用 `ENUM`，随时会加就用 `TINYINT` + 注释。基线里就有现成例子：

```sql
SELECT status, COUNT(*) AS 单数 FROM orders GROUP BY status;
```

```text
+-----------+--------+
| status    | 单数   |
+-----------+--------+
| created   |  50000 |
| paid      |  50000 |
| shipped   |  50000 |
| cancelled |  50000 |
+-----------+--------+
```

`orders.status` 是 `ENUM('created','paid','shipped','cancelled')`：插错值直接被拦，存的还是序号：

```sql
CREATE TEMPORARY TABLE t_enum_set (
  gender ENUM('男','女') NOT NULL,
  hobbies SET('篮球','唱歌','游戏') NOT NULL
);
INSERT INTO t_enum_set VALUES ('女','篮球,游戏'), ('男','篮球');
SELECT gender, hobbies, gender = '女' AS 是女吗,
       FIND_IN_SET('唱歌', hobbies) > 0 AS 喜欢唱歌吗,
       gender + 0 AS 内部序号
FROM t_enum_set ORDER BY gender;
DROP TEMPORARY TABLE t_enum_set;
```

```text
+--------+---------------+-----------+-----------------+--------------+
| gender | hobbies       | 是女吗    | 喜欢唱歌吗      | 内部序号     |
+--------+---------------+-----------+-----------------+--------------+
| 男     | 篮球          |         0 |               0 |            1 |
| 女     | 篮球,游戏     |         1 |               0 |            2 |
+--------+---------------+-----------+-----------------+--------------+
```

`gender + 0` 暴露了内部序号：`男` 是 1、`女` 是 2，**排序按序号不按拼音**。集合（SET，一个字段装多个值）能用逗号存多选，判断要 `FIND_IN_SET` 或位运算。取舍：`ENUM` 加值要 `ALTER TABLE`（第 12 篇讲改表代价），`SET` 的多选在 JOIN 面前一文不值 —— **真有多对多，建关联表**。

## 7. NULL 和空字符串不是一回事

**问题**：`WHERE remark = ''` 和 `WHERE remark IS NULL` 有区别吗？

**答案**：有，而且 `NULL` 参与的比较结果是「未知」，不是真也不是假。

```sql
CREATE TEMPORARY TABLE t_null_demo (
  id     INT NOT NULL,
  remark VARCHAR(50) NULL,
  PRIMARY KEY (id)
);
INSERT INTO t_null_demo VALUES (1, ''), (2, NULL), (3, '写了内容');
SELECT id, remark, remark IS NULL AS 是NULL吗, remark = '' AS 等于空串吗 FROM t_null_demo;
SELECT COUNT(*) AS 用空串条件找到的 FROM t_null_demo WHERE remark = '';
SELECT COUNT(*) AS 用IS_NULL找到的 FROM t_null_demo WHERE remark IS NULL;
SELECT NULL = '' AS NULL等于空串吗, COALESCE(NULL,'x') AS A, COALESCE('','x') AS B;
DROP TEMPORARY TABLE t_null_demo;
```

```text
+----+--------------+------------+-----------------+
| id | remark       | 是NULL吗   | 等于空串吗      |
+----+--------------+------------+-----------------+
|  1 |              |          0 |               1 |
|  2 | NULL         |          1 |            NULL |
|  3 | 写了内容     |          0 |               0 |
+----+--------------+------------+-----------------+
+--------------------------+
| 用空串条件找到的         |
+--------------------------+
|                        1 |
+--------------------------+
+---------------------+
| 用IS_NULL找到的     |
+---------------------+
|                   1 |
+---------------------+
+---------------------+---+---+
| NULL等于空串吗      | A | B |
+---------------------+---+---+
|                NULL | x |   |
+---------------------+---+---+
```

第 2 行 `remark = ''` 的结果是 `NULL`（空白格），**既不是 1 也不是 0**，任何条件都捞不到它。规则很简单：**业务字段要么全 `NOT NULL`（配 `DEFAULT`），要么老实允许 `NULL`**，别两种「没有值」并存。还要记住 `SUM`/`AVG`/`COUNT(col)` 跳过 `NULL`，`GROUP BY` 把 `NULL` 归成一组。

## 8. JSON：能用，但不是「不想设计表」的借口

**问题**：字段老变来变去，全塞进一个 `JSON` 列行不行？

**答案**：存杂项、配置这类结构不固定的数据可以；**会参与查询、排序、唯一性校验的字段不行** —— JSON 路径建不了普通索引，也加不了约束。

```sql
SELECT user_name, extra,
       JSON_EXTRACT(extra, '$.source') AS 来源,
       JSON_UNQUOTE(JSON_EXTRACT(extra, '$.source')) AS 来源文本
FROM bad_design_demo LIMIT 3;
SELECT user_name, extra ->> '$.source' AS 箭头写法
FROM bad_design_demo WHERE JSON_EXTRACT(extra, '$.vip') = 1 LIMIT 3;
```

```text
+-----------+------------------------------+--------+--------------+
| user_name | extra                        | 来源   | 来源文本     |
+-----------+------------------------------+--------+--------------+
| 钱小1     | {"vip": 0, "source": "web"}  | "web"  | web          |
| 孙小2     | {"vip": 0, "source": "mini"} | "mini" | mini         |
| 李小3     | {"vip": 1, "source": "pc"}   | "pc"   | pc           |
+-----------+------------------------------+--------+--------------+
+-----------+--------------+
| user_name | 箭头写法     |
+-----------+--------------+
| 李小3     | pc           |
| 郑小6     | mini         |
| 陈小9     | web          |
+-----------+--------------+
```

`JSON_EXTRACT(extra, '$.source')` 取出来的值**带引号**（`"web"`），所以常配 `JSON_UNQUOTE`；`->>` 是快捷写法，自动去引号。`WHERE JSON_EXTRACT(extra, '$.vip') = 1` 能查，但只能逐行解析 JSON，数据一多就是灾难。判断标准就一条：**这个字段会被 WHERE / ORDER BY / 唯一约束用到吗？会，就拆成正经的列。**

## 9. 动手改造：把 8 个字段全改对

**问题**：知道了每个坑，这张表的正确版本长什么样？

**答案**：照下面建，用一条 `INSERT ... SELECT` 把脏数据洗进新表：

```sql
CREATE TABLE good_design_demo (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_name   VARCHAR(30)   NOT NULL COMMENT '名字不需要 200 字符',
  birthday    DATE          NOT NULL COMMENT '日期用 DATE',
  phone       VARCHAR(20)   NOT NULL COMMENT '手机号是字符串：有前导 0、有 +86',
  price       DECIMAL(10,2) NOT NULL COMMENT '金额用 DECIMAL',
  is_man      TINYINT(1)    NOT NULL COMMENT '布尔用 TINYINT：1 是 0 否',
  create_time DATETIME      NOT NULL COMMENT '时间用 DATETIME',
  extra       JSON          NULL     COMMENT 'JSON 可以用，但别当万能口袋',
  remark      TEXT          NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_phone (phone)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='正面教材';
INSERT INTO good_design_demo (user_name, birthday, phone, price, is_man, create_time)
SELECT LEFT(user_name, 10),
       STR_TO_DATE(birthday, '%Y-%m-%d'),
       CAST(phone AS CHAR),
       CAST(REPLACE(price, '元', '') AS DECIMAL(10,2)),
       is_man = '是',
       STR_TO_DATE(create_time, '%Y-%m-%d %H:%i:%s')
FROM bad_design_demo;
SELECT user_name, birthday FROM good_design_demo ORDER BY birthday LIMIT 5;
DROP TABLE good_design_demo;
```

```text
+-----------+------------+
| user_name | birthday   |
+-----------+------------+
| 冯小18    | 2005-01-10 |
| 陈小9     | 2005-01-10 |
| 钱小1     | 2005-02-11 |
| 陈小19    | 2005-02-11 |
| 赵小10    | 2005-02-11 |
+-----------+------------+
```

洗数据的四个动作你已经见过了：`STR_TO_DATE` 转日期、`REPLACE` 摘「元」、`is_man = '是'` 中文布尔变 1/0、`CAST(phone AS CHAR)` 保前导 0。原表 `birthday` 实际全是 `2005-0M-1D`，`ORDER BY` 结果碰巧和 `DATE` 版一样 —— **这是运气，不是正确**。

## 10. 选型速查表

| 你要存的东西 | 用这个 | 别用这个 | 一句话理由 |
|---|---|---|---|
| 金额、余额、单价 | `DECIMAL(10,2)`（大额 `DECIMAL(12,2)`） | `FLOAT`/`DOUBLE`/字符串 | 二进制浮点存不了 0.1 |
| 手机号、身份证、学号、订单号 | `VARCHAR(20)` | `BIGINT`/`DOUBLE` | 标识符不是数，前导 0 有意义 |
| 年龄、状态、布尔 | `TINYINT`（`TINYINT(1)` 当布尔） | `VARCHAR` | 数值上下文里字符串会变 0 |
| 大整数（自增主键、外键） | `BIGINT` / `INT UNSIGNED` | `DECIMAL` | 省 4~8 字节，索引更快 |
| 名字、标题、地址 | `VARCHAR(30~128)` | `TEXT`（能定长时） | `VARCHAR` 能建索引、有默认值 |
| 文章正文、日志 | `TEXT`（更长用 `MEDIUMTEXT`） | 无限制 `VARCHAR` | 长度不可控就别占行内空间 |
| 只有日期（生日） | `DATE` | `DATETIME`/字符串 | 省 3 字节，语义也更准 |
| 时间戳（下单时间） | `DATETIME` | `TIMESTAMP`（除非有跨时区刚需） | 不怕 2038，不怕时区搬家 |
| 固定几个取值 | `ENUM` 或 `TINYINT` + 注释 | 随手 `VARCHAR` | 拦截非法值、排序按序号 |
| 多选标签 | 关联表 | `SET` | 关联表能加索引、能统计 |
| 真假值 | `TINYINT(1)` + `DEFAULT 0` | `'true'`/`'false'` 字符串 | `'false'` 等于 0 |
| 可有可无的杂项配置 | `JSON` | 拿 JSON 当主表 | 会查询的字段必须是列 |

## 三个必须记住的结论

1. **字符串比较是字典序**。日期、金额、布尔用字符串存，排序、范围、求和都会给你「看起来对」的错结果
2. **钱用 `DECIMAL`，真假用 `TINYINT(1)`，号码用 `VARCHAR`**。`DOUBLE` 的 15~17 位有效数字和 `BIGINT` 的前导 0 都会背叛你
3. **日期默认 `DATETIME`**：`TIMESTAMP` 存 UTC、读时跟着会话时区变，还卡在 2038；需要跨时区统一时刻时才选它

## 常见错误

### ❌ 上线半年才想起「金额列改成 DECIMAL 吧」

```sql
-- ERROR 1292 (22007): Truncated incorrect DECIMAL value: '1.99元'
ALTER TABLE bad_design_demo MODIFY price DECIMAL(10,2) NOT NULL;
```

```text
ERROR 1292 (22007) at line 1: Truncated incorrect DECIMAL value: '1.99元'
```

**为什么错**：严格模式下 `'1.99元'` 转不成 `DECIMAL`，MySQL 直接拒绝；`ALTER TABLE` 是**原子的**，报错即整体回滚，表结构原封不动。这不是刁难你，是它救你：真转成功了，20 行脏值就变成 20 个错值。

**正确做法**：新建列 → 洗数据 → 删旧列 → 改名，顺序不能反。真表别急着动，先在复制品上跑熟：

```sql
CREATE TABLE t_price_fix LIKE bad_design_demo;
INSERT INTO t_price_fix SELECT * FROM bad_design_demo;
ALTER TABLE t_price_fix ADD COLUMN price_new DECIMAL(10,2) NULL COMMENT '洗过的金额';
UPDATE t_price_fix SET price_new = CAST(REPLACE(price, '元', '') AS DECIMAL(10,2));
ALTER TABLE t_price_fix DROP COLUMN price, RENAME COLUMN price_new TO price;
SELECT user_name, price FROM t_price_fix ORDER BY id LIMIT 3;
DROP TABLE t_price_fix;
```

```text
+-----------+-------+
| user_name | price |
+-----------+-------+
| 钱小1     |  1.99 |
| 孙小2     |  2.99 |
| 李小3     |  3.99 |
+-----------+-------+
```

**解释**：`REPLACE` 摘掉「元」，剩下的字符串转成 `DECIMAL(10,2)` 干净落位；反面教材 `bad_design_demo` 原封没动 —— `price` 仍是 `varchar`。

类型选对永远最便宜——**建表时花 10 分钟，上线后少熬三个通宵**。

## 动手练

- [ ] 照第 9 节的思路，把 `create_time` 和 `extra` 也想清楚：哪些该拆成列？写出你的 `CREATE TABLE`
- [ ] 在原表跑 `SELECT user_name, birthday FROM bad_design_demo ORDER BY birthday;` —— 看着很正常对吧？插一条 `birthday = '2005-1-1'` 再排一次，看它跑到哪（**跑完记得删**）
- [ ] 想一想：为什么 `WHERE is_man = 0` 能命中全部 20 行，而 `WHERE is_man = 'false'` 一行都没有？

<details>
<summary>第二题的答案</summary>

```sql
INSERT INTO bad_design_demo (user_name, birthday, phone, price, is_man, create_time, extra, remark)
VALUES ('测试不补零', '2005-1-1', 13800009999, '9.99元', '否', '2024-01-01 10:00:00', NULL, '排序坑');
SELECT user_name, birthday FROM bad_design_demo ORDER BY birthday;
-- '2005-1-1' 第 5 位是 '1'，比所有 '2005-0X' 都大，掉到了队尾
DELETE FROM bad_design_demo WHERE user_name = '测试不补零';   -- 跑完必须删，行数要回到 20
SELECT COUNT(*) FROM bad_design_demo;
```

</details>

<details>
<summary>第三题的答案</summary>

`is_man` 是 `VARCHAR`，`WHERE is_man = 0` 触发「字符串 ↔ 数字」比较，`'是'`、`'否'` 都转不成数字，按规则一律当 0，所以 20 行全命中。
`WHERE is_man = 'false'` 是字符串比字符串，表里存的是 `'是'`/`'否'`，一个都对不上，返回 0 行。
**真假值就用 `TINYINT(1)` 存 1/0**，判断写 `= 1` / `= 0`。
</details>

## 配套实验

```powershell
docker cp lab/queries/10-demo-types.sql easy-mysql:/tmp/
docker exec easy-mysql mysql -uroot -peasy123 -t -e "source /tmp/10-demo-types.sql"
```

> 文件里所有临时表用完即删，`good_design_demo` 收尾时也会 `DROP`。
> 末尾那一句是故意写错的（把 `price` 改成 `DECIMAL` 被拒），所以 `source` 会停在那一句 —— 前面的实验和清理已经全部执行完。

## 下一篇

[11 · 主键、外键与约束：让数据库替你拦住脏数据](11-keys-constraints.md)
