# 02 · 数据库、表、行、列：先搞懂这四个词

> **一句话价值**：能向别人解释清楚「我的数据存在哪」，并自己创建第一张表。

**难度**：⭐　|　**时长**：约 15 分钟　|　**涉及表**：`students`

## 什么时候你会遇到它

别人问你「你的用户表现在多少条数据」，你支支吾吾。或者你照着某篇教程敲 `USE school`，得到一句 `Unknown database 'school'`，却不知道 `school` 该从哪来。这两个窘境是同一个病根：你不知道数据被放在哪一层。

## 本篇你会学到

- [ ] 数据库 / 表 / 行 / 列 的层级关系
- [ ] 什么是**主键**，为什么每张表都必须有
- [ ] `CREATE DATABASE` / `USE` / `SHOW TABLES` / `DESC` 四个命令
- [ ] 亲眼看看 `students` 表长什么样

---

## 正文

### 1. 四层关系，一张图说完

```text
MySQL 服务器 mysqld（第 1 篇里那个一直醒着的进程）
│
├── 库 database：easy_mysql        ← 一间屋子，本教程 8 张表全放在里面
│   │
│   ├── 表 table：students         ← 屋里的一张表格，200 行
│   │   ├── 列 column：id、name、gender、class_name、birth_date、city、created_at
│   │   └── 行 row：│ 1 │ 赵伟 │ 女 │ 软工210班 │ 2005-09-02 │ 上海 │
│   │
│   └── 表 table：scores           ← 同一间屋子里的另一张表格，2000 行
│       ├── 列 column：id、student_id、course_id、score、exam_date
│       └── 行 row：│ 1 │ 1 │ 1 │ 55.00 │ 2025-06-18 │
│
└── 库 database：mysql             ← 另一间屋子，系统自带（账号密码就存在这）
```

**库（database）是表的容器，表（table）是行和列的容器。** 一个服务器上可以挂很多个库，库与库之间互不干扰 —— 你把 `my_school` 删了，`easy_mysql` 一根毫毛都不会少，第 5 节你就亲手干这事。

**列（column）是竖着的一栏**，代表一种属性：姓名、城市、出生日期。**行（row）是横着的一条**，代表一条记录：一个学生、一笔订单、一条成绩。你在 Excel 里管的那张 sheet，在这里就叫一张表。

图里那两行不是我随手画的。假设你人已经在 `easy_mysql` 里（第 1 篇那条 `docker exec` 命令把库名写在了末尾，等于是帮你 `USE` 过了），把 `students` 的第 1 行拎出来看看：

```sql
SELECT * FROM students WHERE id = 1;
```

```text
+----+--------+--------+--------------+------------+--------+---------------------+
| id | name   | gender | class_name   | birth_date | city   | created_at          |
+----+--------+--------+--------------+------------+--------+---------------------+
|  1 | 赵伟   | 女     | 软工210班    | 2005-09-02 | 上海   | 2026-10-07 09:29:59 |
+----+--------+--------+--------------+------------+--------+---------------------+
```

> 📌 `created_at` 这一列是 **我初始化这份数据的时刻**（2026-10-07）。你要是重置过环境，
> 这里会显示你自己那次的时间 —— **只有这列对不上是正常的**，其余 6 列应该和我一字不差。

这就是**一条记录**：7 个列各领到一个值，拼起来是「赵伟这个人」。`WHERE id = 1` 的意思是「只要 id 等于 1 的那行」，它是第 4 篇的主角，这里先借用一下 —— 你只要看懂：**结果有几行，就是命中了几条记录。**

### 2. 第一次动手：先栽两个跟头

教程里那句 `USE school` 到底在干嘛？先看它报错的样子（我在真服务器上跑的）：

```sql
USE school;
```

```text
ERROR 1049 (42000) at line 1: Unknown database 'school'
```

**`USE` 是「选定当前库」**，后面不写库名的操作全在这个库里进行。`school` 是那篇教程随手编的名字，这台服务器上没这间屋子，自然选不中。我们这台服务器上现成的库叫 `easy_mysql`。

还有一个更隐蔽的跟头 —— 一个库都不选就问它有什么表：

```sql
SHOW TABLES;
```

```text
ERROR 1046 (3D000) at line 1: No database selected
```

**这就是 `SHOW TABLES` 必须先 `USE` 的原因**：它要回答「哪些表」，你却没说「哪个库里的表」。服务器不会替你猜，猜错了才是灾难。把库选上，它立刻有答案。

现在从零建一个自己的库，全程照抄即可：

```sql
CREATE DATABASE IF NOT EXISTS my_school DEFAULT CHARSET utf8mb4;
USE my_school;
CREATE TABLE t_student (
  id   INT UNSIGNED NOT NULL AUTO_INCREMENT,
  name VARCHAR(30)  NOT NULL,
  PRIMARY KEY (id)
);
INSERT INTO t_student (name) VALUES ('张三'), ('李四'), ('王五');
SHOW TABLES;
SELECT * FROM t_student ORDER BY id;
```

```text
+---------------------+
| Tables_in_my_school |
+---------------------+
| t_student           |
+---------------------+
+----+--------+
| id | name   |
+----+--------+
|  1 | 张三   |
|  2 | 李四   |
|  3 | 王五   |
+----+--------+
```

逐段拆开：

- `DEFAULT CHARSET utf8mb4`：这个库用什么字符集存字。**为什么不是 `utf8`，第 5 节给你看报错**
- `INT UNSIGNED NOT NULL AUTO_INCREMENT`：无符号整数、不许为空、自动编号。插数据时我不写 `id`，它自己排 1、2、3
- `PRIMARY KEY (id)`：**主键（primary key）**，这一列的值必须唯一、必须非空。它就是这一行的身份证号 —— 没有它，两行一模一样的数据你分不清谁是谁，后面第 11 篇的约束、第 13 篇的索引全踩在它上面
- `INSERT` 插进去三行，`SHOW TABLES` 证明表建成了，`SELECT *` 把三行取出来。**到这儿，库 → 表 → 行你都亲手摸过了**

### 3. 看懂表结构：`DESC` 和 `SHOW CREATE TABLE`

你面前摆着现成的 `students`，想知道它长什么样。先切回正库 —— 上一节末尾你人在 `my_school`，不切回去 `students` 就不在当前库里，照样报 `ERROR 1146`：

```sql
USE easy_mysql;
DESC students;
```

```text
+------------+-------------------+------+-----+-------------------+-------------------+
| Field      | Type              | Null | Key | Default           | Extra             |
+------------+-------------------+------+-----+-------------------+-------------------+
| id         | int unsigned      | NO   | PRI | NULL              | auto_increment    |
| name       | varchar(30)       | NO   | UNI | NULL              |                   |
| gender     | enum('男','女')   | NO   |     | 男                |                   |
| class_name | varchar(30)       | NO   |     | NULL              |                   |
| birth_date | date              | NO   |     | NULL              |                   |
| city       | varchar(30)       | NO   |     | 未知              |                   |
| created_at | datetime          | NO   |     | CURRENT_TIMESTAMP | DEFAULT_GENERATED |
+------------+-------------------+------+-----+-------------------+-------------------+
```

这张结果有六列，各有各的职责：`Field` 字段名，`Type` 类型，`Null` 允不允许空，**`Key` 是这列上有什么键**（`PRI` = 主键，`UNI` = 唯一），`Default` 是不写值时用什么兜底，`Extra` 是额外说明（`auto_increment` = 自动编号）。`gender` 那行的 `Type` 是 `enum('男','女')`，意思是这一列**只认**这两个值，第三个值它不收。

想要更完整的版本：

```sql
SHOW CREATE TABLE students\G
```

```text
*************************** 1. row ***************************
       Table: students
Create Table: CREATE TABLE `students` (
  `id` int unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `name` varchar(30) NOT NULL COMMENT '姓名',
  `gender` enum('男','女') NOT NULL DEFAULT '男' COMMENT '性别',
  `class_name` varchar(30) NOT NULL COMMENT '班级',
  `birth_date` date NOT NULL COMMENT '出生日期',
  `city` varchar(30) NOT NULL DEFAULT '未知' COMMENT '城市',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_students_name` (`name`)
) ENGINE=InnoDB AUTO_INCREMENT=1002 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='学生表'
```

`\G` 是让结果竖过来显示，行太宽时比表格好读。注意这段就是**MySQL 自己记账用的建表原文**，一字不差地贴到任何一台新机器上，都能建出一模一样的表 —— 第 21 篇的备份恢复靠的就是它。里面的 `UNIQUE KEY uk_students_name (name)` 说的是「姓名不许重复」，`PRIMARY KEY (id)` 说的是「id 不许重复且不许为空」，两者区别第 11 篇细讲。

> 📌 只有结尾那行的 `AUTO_INCREMENT=1002` 是「历史」：它记的是这张表的自增计数器到哪了，全新初始化的机器上是 `201`（种子数据的 id 是 1 ~ 200），谁往里插过行它就往上走。数字对不上不用慌，看结构别看它。

### 4. 动手改：加一列、改列名、删掉重来

表不是刻死的，`ALTER TABLE` 负责改。给 `t_student` 加一列班级：

```sql
ALTER TABLE t_student ADD COLUMN class_name VARCHAR(30) NOT NULL DEFAULT '未分班';
DESC t_student;
```

```text
+------------+--------------+------+-----+-----------+----------------+
| Field      | Type         | Null | Key | Default   | Extra          |
+------------+--------------+------+-----+-----------+----------------+
| id         | int unsigned | NO   | PRI | NULL      | auto_increment |
| name       | varchar(30)  | NO   |     | NULL      |                |
| class_name | varchar(30)  | NO   |     | 未分班    |                |
+------------+--------------+------+-----+-----------+----------------+
```

已有的三行没报错，老行会自动填上默认值 —— 本节末尾 `SELECT` 里三行的 `class_name` 全是 `'未分班'`，就是这么来的。

那要是**不给** `DEFAULT` 呢？造张表当场实测（末尾那句 `DROP` 把它清理掉）：

```sql
CREATE TABLE probe_addcol (id INT PRIMARY KEY, a INT NOT NULL);
INSERT INTO probe_addcol VALUES (1,1);
ALTER TABLE probe_addcol ADD COLUMN b INT NOT NULL;
SELECT * FROM probe_addcol;
DROP TABLE probe_addcol;
```

```text
+----+---+---+
| id | a | b |
+----+---+---+
|  1 | 1 | 0 |
+----+---+---+
```

MySQL 一声不吭，直接给老行填了个 `0` —— 那是它眼里的「整数零值」，可你要的多半是 `'未分班'` 这种有意义的东西。**加列时把 `DEFAULT` 顺手写上**，别把填什么的决定权交给服务器。

改列名用 `CHANGE`，注意它后面要跟**完整的新定义**：

```sql
ALTER TABLE t_student CHANGE name student_name VARCHAR(30) NOT NULL;
SELECT id, student_name, class_name FROM t_student ORDER BY id;
```

```text
+----+--------------+------------+
| id | student_name | class_name |
+----+--------------+------------+
|  1 | 张三         | 未分班     |
|  2 | 李四         | 未分班     |
|  3 | 王五         | 未分班     |
+----+--------------+------------+
```

你写 `NOT NULL`，它就照办；你忘了写，它就顺手把约束也删了 —— `CHANGE` 是「整段覆盖」，不是「只改名字」。

「删掉重来」一步到位：

```sql
DROP TABLE t_student;
CREATE TABLE t_student (
  id           INT UNSIGNED NOT NULL AUTO_INCREMENT,
  student_name VARCHAR(30)  NOT NULL,
  class_name   VARCHAR(30)  NOT NULL DEFAULT '未分班',
  PRIMARY KEY (id)
) DEFAULT CHARSET = utf8mb4;
DESC t_student;
```

```text
+--------------+--------------+------+-----+-----------+----------------+
| Field        | Type         | Null | Key | Default   | Extra          |
+--------------+--------------+------+-----+-----------+----------------+
| id           | int unsigned | NO   | PRI | NULL      | auto_increment |
| student_name | varchar(30)  | NO   |     | NULL      |                |
| class_name   | varchar(30)  | NO   |     | 未分班    |                |
+--------------+--------------+------+-----+-----------+----------------+
```

`DROP TABLE` 不会问你第二次，结构和数据一起没。重建出来的表结构和原来一模一样，但里面是空的 —— 具体有多空，动手练第二题你亲手量。

### 5. 坑：你写的 `utf8`，不是你以为的那个 `utf8`

建一张字符集写 `utf8` 的表，然后问 MySQL 它到底是什么：

```sql
CREATE TABLE t_emoji (
  id   INT UNSIGNED NOT NULL AUTO_INCREMENT,
  name VARCHAR(30) NOT NULL,
  PRIMARY KEY (id)
) DEFAULT CHARSET = utf8;

SHOW CREATE TABLE t_emoji\G
```

```text
*************************** 1. row ***************************
       Table: t_emoji
Create Table: CREATE TABLE `t_emoji` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(30) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3
```

输出最底下那行写着 `DEFAULT CHARSET=utf8mb3`：**MySQL 里没有真正的 `utf8`，那个名字是历史遗留，它的真实身份是 `utf8mb3`** —— 一个字符最多 3 个字节。存汉字够了（汉字 UTF-8 编码就是 3 字节），所以你中文一直没出事。emoji 是 4 个字节：

```sql
INSERT INTO t_emoji (name) VALUES ('😀');
```

```text
ERROR 1366 (HY000) at line 1: Incorrect string value: '\xF0\x9F\x98\x80' for column 'name' at row 1
```

`\xF0\x9F\x98\x80` 就是 😀 的四个字节，第 4 个字节无处安放，服务器直接拒收。这种错最阴险的地方在于：**测试阶段全是汉字，一切正常；上线后用户填了个 emoji，接口 500。**

改成 `utf8mb4`（UTF-8，一个字符最多 4 字节）再插：

```sql
ALTER TABLE t_emoji MODIFY name VARCHAR(30) CHARACTER SET utf8mb4 NOT NULL;
INSERT INTO t_emoji (name) VALUES ('😀');
SELECT id, name, LENGTH(name) AS bytes, CHAR_LENGTH(name) AS chars FROM t_emoji;
```

```text
+----+------+-------+-------+
| id | name | bytes | chars |
+----+------+-------+-------+
|  1 | 😀     |     4 |     1 |
+----+------+-------+-------+
```

`LENGTH` 数的是**字节**（4），`CHAR_LENGTH` 数的是**字符**（1）—— 同一个 emoji 的两种量法，第 9 篇会再用到。记住一句话：**建库建表，字符集一律 `utf8mb4`**，本仓库 8 张表全是它，emoji、生僻字、英文都装得下。

顺手把演示库收干净，这是每个实验该有的样子：

```sql
DROP DATABASE IF EXISTS my_school;
SELECT COUNT(*) AS my_school_left FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = 'my_school';
```

```text
+----------------+
| my_school_left |
+----------------+
|              0 |
+----------------+
```

## 三个必须记住的结论

1. **库 → 表 → 行 → 列**：库装表，表装行和列；列是属性，行是一条记录。回答「存在哪」要说清**哪个库的哪张表**
2. **主键是行的身份证号**：唯一、非空，`DESC` 里显示 `PRI`，后面所有约束和索引都建立在它上面
3. **字符集只写 `utf8mb4`**：`utf8` 在 MySQL 里是 `utf8mb3`，存不下 emoji，报 `ERROR 1366`

## 常见错误

### ❌ 表名打错了

```sql
USE easy_mysql;
SELECT * FROM student;      -- 表其实叫 students
```

```text
ERROR 1146 (42S02) at line 1: Table 'easy_mysql.student' doesn't exist
```

**为什么错**：表必须住在某个库里，MySQL 找表时看的是「**当前库**.表名」。报错里那句 `easy_mysql.student` 把它的搜索过程全交代了：当前库是 `easy_mysql`，它按这个名字去找，没找到。**顺带一提，这行报错还能反过来告诉你「我现在到底在哪个库」** —— 比 `Unknown table` 这种没头没尾的提示好用多了。

**正确做法**：表名是 `students`（第 1 节那张图里就有）。拿不准就先问一句：

```sql
SHOW TABLES;
```

```text
+----------------------+
| Tables_in_easy_mysql |
+----------------------+
| bad_design_demo      |
| courses              |
| order_items          |
| orders               |
| orders_slow          |
| scores               |
| students             |
| users                |
+----------------------+
```

> 📌 看表头：`Tables_in_easy_mysql` 直接把你当前所在的库写在了脸上。「我现在在哪个库」这个问题，`SHOW TABLES` 顺手就答了。

## 动手练

- [ ] 说出为什么 `SHOW TABLES;` 要先 `USE` 某个库
- [ ] 把 `t_student` 删掉重建，这期间你会发现什么？

<details>
<summary>两题的答案</summary>

**第一题**：`SHOW TABLES` 只知道「列出表」，不知道「列哪个库的表」，而服务器允许同时存在很多库。不 `USE` 就问，它只能回你 `ERROR 1046 (3D000) at line 1: No database selected`（第 2 节原文）。`USE` 就是在给后面的语句指定办事的房间。

**第二题**：结构回来了，数据没回来。删完重建后量一下：

```sql
SELECT COUNT(*) AS rows_left FROM t_student;
```

```text
+-----------+
| rows_left |
+-----------+
|         0 |
+-----------+
```

`DESC` 看起来和原来分毫不差，但那三行跟着 `DROP TABLE` 一起蒸发了。**表结构和表数据是两样东西**，改结构的语句（`ALTER`）留数据，删表的语句（`DROP`）一样都不留。真要重建带数据的表，得先 `mysqldump` 备份 —— 第 21 篇讲。
</details>

## 配套实验

```powershell
docker cp lab/queries/02-demo-db-table.sql easy-mysql:/tmp/
docker exec easy-mysql mysql -uroot -peasy123 -t --default-character-set=utf8mb4 easy_mysql -e "source /tmp/02-demo-db-table.sql"
```

> 实验自建 `my_school` 库，把加列、改名、删表、字符集的坑全走一遍，末尾用一句 `DROP DATABASE` 收尾，跑完不留任何痕迹。

## 下一篇

[03 · SELECT 入门：查出你想要的那几行](03-select-basics.md)
