# 11 · 主键、外键与约束：让数据库替你拦住脏数据

> **一句话价值**：给表加上 `NOT NULL`、`UNIQUE`、`CHECK`、`FOREIGN KEY`，让 1500 分的成绩、不存在的学生在写入那一刻就被弹回来，而不是在报表里炸。

**难度**：⭐⭐　|　**时长**：约 30 分钟　|　**涉及表**：`students`、`scores`、`order_items`

## 什么时候你会遇到它

测试同学往 `scores` 里插了一条 `score = 1500` 的成绩，代码没报错，月底报表炸了。更隐蔽的一种是 `scores` 里出现 `student_id = 99999`——这个学生压根不存在，一 JOIN 成绩就凭空少一块。两件事的根子相同：**表自己不设防，全指望调用方手干净**。

## 本篇你会学到

- [ ] 约束（constraint，写在表结构里的数据规则）长在哪、怎么一眼看全
- [ ] 五种约束各自抛出的错误码：1048 / 1062 / 3819 / 1452 / 1451
- [ ] `ON DELETE CASCADE / SET NULL / RESTRICT` 三种删除行为的真实差别
- [ ] 物理外键（数据库强制的外键）到底要付多少钱，为什么 60 万行的 `order_items` 不建
- [ ] 主键四种写法的取舍，以及 `UNIQUE` 到底允许几条 `NULL`

## 1. 护栏写在哪：`SHOW CREATE TABLE` 一眼看全

**问题**：接手一张表，怎么知道它有哪些护栏？

**答案**：一条 `SHOW CREATE TABLE`，建表语句里所有约束都跑不掉。

**实验**：

```sql
SHOW CREATE TABLE scores\G
```

```text
*************************** 1. row ***************************
       Table: scores
Create Table: CREATE TABLE `scores` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `student_id` int unsigned NOT NULL COMMENT '学生 id',
  `course_id` int unsigned NOT NULL COMMENT '课程 id',
  `score` decimal(5,2) NOT NULL COMMENT '分数 0~100',
  `exam_date` date NOT NULL COMMENT '考试日期',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_scores_student_course` (`student_id`,`course_id`),
  KEY `idx_scores_course` (`course_id`),
  CONSTRAINT `fk_scores_course` FOREIGN KEY (`course_id`) REFERENCES `courses` (`id`),
  CONSTRAINT `fk_scores_student` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=2003 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='成绩表'
```

**解释**：五行约束各管一段——`PRIMARY KEY`（主键，唯一且非空的行标识）、`UNIQUE KEY`（唯一键，值不许重复）、两个 `FOREIGN KEY`（外键，指向 `students` / `courses` 的真实行），列上的 `NOT NULL` 则逐列挡住 NULL。默认值（default，不写就用的值）在 `information_schema` 里查：

```sql
SELECT COLUMN_NAME, IS_NULLABLE, COLUMN_DEFAULT, DATA_TYPE, EXTRA
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = 'easy_mysql' AND TABLE_NAME = 'students'
ORDER BY ORDINAL_POSITION;
```

```text
+-------------+-------------+-------------------+-----------+-------------------+
| COLUMN_NAME | IS_NULLABLE | COLUMN_DEFAULT    | DATA_TYPE | EXTRA             |
+-------------+-------------+-------------------+-----------+-------------------+
| id          | NO          | NULL              | int       | auto_increment    |
| name        | NO          | NULL              | varchar   |                   |
| gender      | NO          | 男                | enum      |                   |
| class_name  | NO          | NULL              | varchar   |                   |
| birth_date  | NO          | NULL              | date      |                   |
| city        | NO          | 未知              | varchar   |                   |
| created_at  | NO          | CURRENT_TIMESTAMP | datetime  | DEFAULT_GENERATED |
+-------------+-------------+-------------------+-----------+-------------------+
```

`IS_NULLABLE = NO` 就是 `NOT NULL`；`COLUMN_DEFAULT` 是默认值，`EXTRA` 里的 `auto_increment` 说明主键自增。

## 2. 没有护栏的表能有多离谱

**问题**：不建外键，会真的有人写进不存在的 id 吗？

**答案**：会，而且没人拦。看这张对照表：

```sql
CREATE TABLE t_orphan_demo (
  id         INT NOT NULL AUTO_INCREMENT,
  student_id INT NOT NULL COMMENT '没有外键，学生不存在也进得来',
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='演示：没有外键的表';
INSERT INTO t_orphan_demo (student_id) VALUES (99999);
SELECT id, student_id, 'students 里根本没有这个学生' AS 说明 FROM t_orphan_demo;
DELETE FROM t_orphan_demo;
DROP TABLE t_orphan_demo;
```

```text
+----+------------+--------------------------------------+
| id | student_id | 说明                                 |
+----+------------+--------------------------------------+
|  1 |      99999 | students 里根本没有这个学生          |
+----+------------+--------------------------------------+
```

**解释**：一张普通表对 `99999` 来者不拒。写入路径是后台脚本、数据订正 SQL、还是别人本地直连库，你管不住——**能进来的数据，就是规则允许的数据**。

## 3. 五种约束，五个错误码

**问题**：每种约束到底拦什么？报错长什么样？

**答案**：下面五条 SQL 逐个撞一遍，报错原文一字不改。

### `NOT NULL` → ERROR 1048

```sql
INSERT INTO scores (student_id, course_id, score, exam_date) VALUES (NULL, NULL, NULL, NULL);
```

```text
ERROR 1048 (23000) at line 1: Column 'student_id' cannot be null
```

### `UNIQUE` → ERROR 1062

学生 1 已经有课程 1 的成绩，再插一条就是重复：

```sql
INSERT INTO scores (student_id, course_id, score, exam_date) VALUES (1, 1, 88, '2025-06-20');
```

```text
ERROR 1062 (23000) at line 1: Duplicate entry '1-1' for key 'scores.uk_scores_student_course'
```

注意 `'1-1'`——报错里的值是 `(student_id, course_id)` 拼起来的，这是**复合唯一键**（composite unique key，多列联合判重）的特征，一条学生只能有一条课程成绩的规则就靠它。

### `CHECK` → ERROR 3819

MySQL 8.0.16 起 `CHECK`（检查约束，限定列的取值范围）才真正生效。加进来、撞一次、再摘掉：

```sql
ALTER TABLE scores ADD CONSTRAINT chk_score_range CHECK (score BETWEEN 0 AND 100);
INSERT INTO scores (student_id, course_id, score, exam_date) VALUES (1, 15, 150, '2025-06-20');
ALTER TABLE scores DROP CHECK chk_score_range;
```

```text
ERROR 3819 (HY000) at line 1: Check constraint 'chk_score_range' is violated.
```

被拦下后，`SHOW CREATE TABLE` 能看见它（`BETWEEN 0 AND 100` 被改写成 `between 0 and 100` 存进元数据）：

```text
  CONSTRAINT `fk_scores_student` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`),
  CONSTRAINT `chk_score_range` CHECK ((`score` between 0 and 100))
) ENGINE=InnoDB AUTO_INCREMENT=2003 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='成绩表'
```

`score` 用 `150` 而不是 `1500` 是有讲究的：`DECIMAL(5,2)` 最大 `999.99`，写 `1500` 会先撞上越界（1264），根本轮不到 `CHECK` 出场。

> 报错不会打断你手上的交互式客户端，所以同块里那句 `DROP CHECK` 照样会跑。但如果你把整段 `source` 进来，MySQL 会停在报错那一句，`chk_score_range` 就会留在 `scores` 上，下一次再加同名约束会撞 `3822 Duplicate check constraint name`——配套实验把唯一的错误放在文件末尾那一句，防的就是这件事。

### `FOREIGN KEY` 写入 → ERROR 1452

```sql
INSERT INTO scores (student_id, course_id, score, exam_date) VALUES (99999, 1, 90, '2025-06-20');
```

```text
ERROR 1452 (23000) at line 1: Cannot add or update a child row: a foreign key constraint fails (`easy_mysql`.`scores`, CONSTRAINT `fk_scores_student` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`))
```

孩子行（`scores`）要挂到不存在的爹（`students`）身上，直接被拒。

### `FOREIGN KEY` 删除 → ERROR 1451

学生 1 名下有成绩，删他试试：

```sql
DELETE FROM students WHERE id = 1;
```

```text
ERROR 1451 (23000) at line 1: Cannot delete or update a parent row: a foreign key constraint fails (`easy_mysql`.`scores`, CONSTRAINT `fk_scores_student` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`))
```

五种拦截一张表记住：

| 约束 | 拦什么 | 错误码 |
|---|---|---|
| `NOT NULL` | 该有值的列写了 NULL | 1048 |
| `UNIQUE` | 值重复 | 1062 |
| `CHECK` | 超出范围 | 3819 |
| `FOREIGN KEY`（写） | 父行不存在 | 1452 |
| `FOREIGN KEY`（删/改） | 父行还被孩子引用 | 1451 |

## 4. 外键的三种删除行为

**问题**：父行被引用时，除了「不许删」，还有别的选择吗？

**答案**：有三种，关键词是 `ON DELETE`：`CASCADE`（级删，父没了孩子跟着没）、`SET NULL`（父没了孩子指向空）、`RESTRICT`（父还有孩子就不许删，不写就是它）。

**实验**：三张表各绑一种，各放一个人：

```sql
CREATE TABLE t_dept_demo (
  id    INT NOT NULL,
  dname VARCHAR(20) NOT NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='部门';
CREATE TABLE t_emp_cascade (
  id      INT NOT NULL,
  ename   VARCHAR(20) NOT NULL,
  dept_id INT NULL,
  PRIMARY KEY (id),
  KEY idx_dept (dept_id),
  CONSTRAINT fk_emp_cascade FOREIGN KEY (dept_id) REFERENCES t_dept_demo (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='删部门 → 员工连带删';
CREATE TABLE t_emp_setnull (
  id      INT NOT NULL,
  ename   VARCHAR(20) NOT NULL,
  dept_id INT NULL,
  PRIMARY KEY (id),
  KEY idx_dept (dept_id),
  CONSTRAINT fk_emp_setnull FOREIGN KEY (dept_id) REFERENCES t_dept_demo (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='删部门 → 员工部门变 NULL';
CREATE TABLE t_emp_restrict (
  id      INT NOT NULL,
  ename   VARCHAR(20) NOT NULL,
  dept_id INT NOT NULL,
  PRIMARY KEY (id),
  KEY idx_dept (dept_id),
  CONSTRAINT fk_emp_restrict FOREIGN KEY (dept_id) REFERENCES t_dept_demo (id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='部门还有人 → 不许删';
INSERT INTO t_dept_demo VALUES (1,'研发部'),(2,'测试部'),(3,'运维部');
INSERT INTO t_emp_cascade  VALUES (101,'张三',1);
INSERT INTO t_emp_setnull  VALUES (201,'王五',2);
INSERT INTO t_emp_restrict VALUES (301,'孙七',3);
SELECT '初始状态' AS 阶段, 'cascade' AS 表, id, ename, dept_id FROM t_emp_cascade
UNION ALL SELECT '初始状态', 'setnull',  id, ename, dept_id FROM t_emp_setnull
UNION ALL SELECT '初始状态', 'restrict', id, ename, dept_id FROM t_emp_restrict;
```

```text
+--------------+----------+-----+--------+---------+
| 阶段         | 表       | id  | ename  | dept_id |
+--------------+----------+-----+--------+---------+
| 初始状态     | cascade  | 101 | 张三   |       1 |
| 初始状态     | setnull  | 201 | 王五   |       2 |
| 初始状态     | restrict | 301 | 孙七   |       3 |
+--------------+----------+-----+--------+---------+
```

```sql
DELETE FROM t_dept_demo WHERE id = 1;
SELECT 'CASCADE 删完' AS 阶段, COUNT(*) AS 剩余员工 FROM t_emp_cascade;
DELETE FROM t_dept_demo WHERE id = 2;
SELECT 'SET NULL 删完' AS 阶段, id, ename, IFNULL(dept_id, 'NULL') AS dept_id FROM t_emp_setnull;
SELECT 'RESTRICT 还没删' AS 阶段, id, ename, dept_id FROM t_emp_restrict;
DROP TABLE t_emp_restrict, t_emp_cascade, t_emp_setnull, t_dept_demo;
```

```text
+----------------+--------------+
| 阶段           | 剩余员工     |
+----------------+--------------+
| CASCADE 删完   |            0 |
+----------------+--------------+
+-----------------+-----+--------+---------+
| 阶段            | id  | ename  | dept_id |
+-----------------+-----+--------+---------+
| SET NULL 删完   | 201 | 王五   | NULL    |
+-----------------+-----+--------+---------+
+--------------------+-----+--------+---------+
| 阶段               | id  | ename  | dept_id |
+--------------------+-----+--------+---------+
| RESTRICT 还没删    | 301 | 孙七   |       3 |
+--------------------+-----+--------+---------+
```

**解释**：研发部没了，张三跟着被删——用 `CASCADE` 前先想清楚这是不是你想要的；测试部没了，王五的部门空出来，得有人回头补；运维部还有孙七，`DELETE` 直接吃 `ERROR 1451`（见上一节）。**级联删除是隐式删除**，一条 `DELETE` 带走多少行你事先不知道，报表少了数据都未必查得出。

## 5. 物理外键的代价：60 万行的 `order_items` 为什么不建

**问题**：外键这么好，为什么大表常常不建？

**答案**：因为每插一行都要回父表查一次。`lab/init/01-schema.sql` 里 `order_items` 的建表语句上方写着：

```text
-- 订单明细：60 万行
-- 故意不建物理外键，真实生产中大表外键会带来写入开销和锁竞争
```

```sql
SHOW CREATE TABLE order_items\G
```

```text
*************************** 1. row ***************************
       Table: order_items
Create Table: CREATE TABLE `order_items` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `order_id` bigint unsigned NOT NULL COMMENT '所属订单',
  `product_name` varchar(60) NOT NULL COMMENT '商品名',
  `price` decimal(10,2) NOT NULL,
  `quantity` int unsigned NOT NULL DEFAULT '1',
  PRIMARY KEY (`id`),
  KEY `idx_items_order` (`order_id`)
) ENGINE=InnoDB AUTO_INCREMENT=600001 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='订单明细表'
```

确实一个 `FOREIGN KEY` 都没有，只有一个普通索引。开销有多大，同一批 4 万行插进两张结构相同的表，一张建外键一张不建：

```text
+--------------+----------+
| 插入行数     |          |
+--------------+----------+
|        40000 |          |
+--------------+----------+
+-----------------+-----------------+
| 无外键毫秒      | 有外键毫秒      |
+-----------------+-----------------+
|            2129 |            3166 |
+-----------------+-----------------+
```

**解释**：多花约五成时间，而且删改父表时会牵动子表的锁。**物理外键的取舍**：

| | 建物理外键 | 放到应用层 |
|---|---|---|
| 数据正确性 | 数据库兜底，任何入口都拦 | 全靠代码，漏一个入口就漏数据 |
| 写入性能 | 每行多一次父表检查 | 无额外开销 |
| 迁库/导数据 | 父子顺序、锁竞争都麻烦 | 随便搬 |
| 适用 | 后台管理、数据量中小、写少读多 | 大批量写入、分库分表、数据仓库 |

别一刀切：**约束能下沉到数据库就下沉**；实在要为性能让路，应用层必须把同一段校验塞进唯一入口（仓储层），否则第 2 节那条 `99999` 就是下场。

## 6. 主键四种写法

**问题**：主键（primary key，唯一标识一行的列）该用自增、UUID、雪花还是业务字段？

**答案**：

| 写法 | 长什么样 | 什么时候用 |
|---|---|---|
| `INT AUTO_INCREMENT` | 1、2、3 | 默认选择，本仓库全部表都这么干，索引最省 |
| UUID | `0205d52a-c21a-11f1-9181-9a1c88522ed8` | 要全局唯一又不想协调发号；无序写入会到处跳页 |
| 雪花 ID | 64 位整数、趋势递增 | 分库分表要自己发号时 |
| 自然主键 | 拿邮箱、身份证当主键 | 除非这字段永远不变，否则别赌 |

```sql
SELECT UUID() AS uuid例子, LENGTH(UUID()) AS 字符串形式字节数;
SELECT HEX(UUID_TO_BIN(UUID())) AS 转二进制看十六进制, LENGTH(UUID_TO_BIN(UUID())) AS 二进制字节数;
```

```text
+--------------------------------------+--------------------------+
| uuid例子                             | 字符串形式字节数         |
+--------------------------------------+--------------------------+
| 0205d52a-c21a-11f1-9181-9a1c88522ed8 |                       36 |
+--------------------------------------+--------------------------+
+----------------------------------+--------------------+
| 转二进制看十六进制               | 二进制字节数       |
+----------------------------------+--------------------+
| 0205E0E6C21A11F191819A1C88522ED8 |                 16 |
+----------------------------------+--------------------+
```

**解释**：UUID 字符串 36 字节，`UUID_TO_BIN` 后 16 字节，砍掉一半还多——要用 UUID 就存 `BINARY(16)`。自然主键的风险在「会变」：邮箱换号、政策改编号，主键一改所有外键跟着改。

## 7. `UNIQUE` 允许几条 `NULL`

**问题**：邮箱列建了 `UNIQUE`，三条都是 `NULL` 的记录进得来吗？

**答案**：进得来，三条全进：

```sql
CREATE TEMPORARY TABLE t_uk_null (
  id    INT NOT NULL PRIMARY KEY,
  email VARCHAR(60) NULL,
  UNIQUE KEY uk_email (email)
);
INSERT INTO t_uk_null VALUES (1, NULL), (2, NULL), (3, NULL);
SELECT id, IFNULL(email, 'NULL') AS email FROM t_uk_null;
DROP TEMPORARY TABLE t_uk_null;
```

```text
+----+-------+
| id | email |
+----+-------+
|  1 | NULL  |
|  2 | NULL  |
|  3 | NULL  |
+----+-------+
```

换成同一个邮箱再插就撞墙：

```sql
CREATE TEMPORARY TABLE t_uk_null2 (
  id    INT NOT NULL PRIMARY KEY,
  email VARCHAR(60) NULL,
  UNIQUE KEY uk_email (email)
);
INSERT INTO t_uk_null2 VALUES (1, 'a@x.com'), (2, 'a@x.com');
DROP TEMPORARY TABLE t_uk_null2;
```

```text
ERROR 1062 (23000) at line 1: Duplicate entry 'a@x.com' for key 't_uk_null2.uk_email'
```

**解释**：SQL 标准里 `NULL` 不等于任何值，MySQL 照做。所以「邮箱唯一」要写成 `email VARCHAR(60) NOT NULL UNIQUE`——`NOT NULL` 把三条 NULL 挡掉，`UNIQUE` 才真正等价于唯一。

## 8. `DEFAULT` 和 `ON UPDATE CURRENT_TIMESTAMP`

**问题**：`created_at` / `updated_at` 这种「创建时间 / 更新时间」每次都要代码手动写吗？

**答案**：不用，交给列默认值和自动更新：

```sql
CREATE TEMPORARY TABLE t_default_demo (
  id         INT NOT NULL AUTO_INCREMENT,
  name       VARCHAR(20) NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  is_deleted TINYINT   NOT NULL DEFAULT 0,
  PRIMARY KEY (id)
);
INSERT INTO t_default_demo (name) VALUES ('第一版');
SELECT id, name, created_at, updated_at, is_deleted FROM t_default_demo;
```

```text
+----+-----------+---------------------+---------------------+------------+
| id | name      | created_at          | updated_at          | is_deleted |
+----+-----------+---------------------+---------------------+------------+
|  1 | 第一版    | 2026-10-07 14:40:38 | 2026-10-07 14:40:38 |          0 |
+----+-----------+---------------------+---------------------+------------+
```

```sql
UPDATE t_default_demo SET name = '第二版' WHERE id = 1;
SELECT id, name, created_at, updated_at, is_deleted FROM t_default_demo;
DROP TEMPORARY TABLE t_default_demo;
```

```text
+----+-----------+---------------------+---------------------+------------+
| id | name      | created_at          | updated_at          | is_deleted |
+----+-----------+---------------------+---------------------+------------+
|  1 | 第二版    | 2026-10-07 14:40:38 | 2026-10-07 14:40:39 |          0 |
+----+-----------+---------------------+---------------------+------------+
```

**解释**：`created_at` 两行都是 `14:40:38` 没动，`updated_at` 从 `:38` 跳到 `:39`——这就是 `ON UPDATE CURRENT_TIMESTAMP` 干的活。`is_deleted` 默认 0，是软删除（逻辑删除，不真删行）的开关，第 12 篇专门讲它。

## 三个必须记住的结论

1. **五种约束对应五个错误码**：1048 `NOT NULL`、1062 重复、3819 `CHECK`、1452 父行不存在、1451 父行被引用。看到报错先认码，少绕半小时。
2. **物理外键是拿写入性能换正确性**：同一批 4 万行 `2129ms → 3166ms`。能下沉就下沉，要让路就必须把校验放进唯一入口。
3. **`UNIQUE` 允许多条 `NULL`**：「邮箱唯一」要写 `NOT NULL UNIQUE`，光 `UNIQUE` 挡不住三条 NULL。

## 常见错误

### ❌ 错误做法：信「下拉框选的 id 一定存在」

```sql
INSERT INTO scores (student_id, course_id, score, exam_date) VALUES (99999, 1, 90, '2025-06-20');
```

```text
ERROR 1452 (23000) at line 1: Cannot add or update a child row: a foreign key constraint fails (`easy_mysql`.`scores`, CONSTRAINT `fk_scores_student` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`))
```

**为什么错**：id 是前端传来的，只要接口没做存在性校验（或者有人绕过接口直接执行 SQL），`99999` 就来了。这类错误**越晚发现越贵**——写入那一刻拦住，代价是 0。

**正确做法**：表里已有外键就让它兜底（本例已经拦住了）；确实不建外键的大表，把「父行是否存在」的校验放进仓储层这一条必经之路：

```sql
INSERT INTO scores (student_id, course_id, score, exam_date)
SELECT 99999, 1, 90, '2025-06-20' FROM DUAL
WHERE EXISTS (SELECT 1 FROM students WHERE id = 99999);
SELECT COUNT(*) AS 成绩行数 FROM scores;
```

```text
+--------------+
| 成绩行数     |
+--------------+
|         2000 |
+--------------+
```

父行不存在时子查询结果为空，静默写入 0 行，成绩表仍是 2000 行。

## 动手练

- [ ] 给 `students` 加一列 `age`，再加 `CHECK (age <= 150)`，写 200 看它报什么错，然后把列和约束都清掉
- [ ] 删掉一个还有成绩的学生，看外键怎么拦你；再用事务演示「先删成绩、后删学生、然后回滚」
- [ ] 你们项目里的外键建在数据库还是应用层？说出一条具体的代价

<details>
<summary>点开看答案</summary>

```sql
-- 练习 1：加列 → 加 CHECK → 撞一次 → 清理
ALTER TABLE students ADD COLUMN age TINYINT UNSIGNED NULL COMMENT '练习用';
ALTER TABLE students ADD CONSTRAINT chk_age CHECK (age <= 150);
UPDATE students SET age = 200 WHERE id = 2;
-- ERROR 3819 (HY000) at line 1: Check constraint 'chk_age' is violated.
UPDATE students SET age = 120 WHERE id = 2;
SELECT id, name, age FROM students WHERE id = 2;
ALTER TABLE students DROP CHECK chk_age;
ALTER TABLE students DROP COLUMN age;
```

```text
+----+--------+------+
| id | name   | age  |
+----+--------+------+
|  2 | 赵芳   |  120 |
+----+--------+------+
```

```sql
-- 练习 2：RESTRICT 拦住删除；事务里按顺序删再回滚，基线一行不少
DELETE FROM students WHERE id = 1;
-- ERROR 1451 (23000) at line 1: Cannot delete or update a parent row: a foreign key constraint fails ...
START TRANSACTION;
DELETE FROM scores WHERE student_id = 1;
DELETE FROM students WHERE id = 1;
ROLLBACK;
SELECT (SELECT COUNT(*) FROM scores) AS 成绩行数, (SELECT COUNT(*) FROM students) AS 学生行数;
```

```text
+--------------+--------------+
| 成绩行数     | 学生行数     |
+--------------+--------------+
|         2000 |          200 |
+--------------+--------------+
```

> 两段答案里的清理语句都排在报错后面：交互式客户端会照常跑完，`source` 整段跑则会停在报错那句，把 `age` 列或临时表留在库里。练习做完记得 `SHOW CREATE TABLE students` 看一眼，没有 `age` 和 `chk_age` 才算干净。

</details>

## 配套实验

```powershell
docker cp lab/queries/11-demo-constraints.sql easy-mysql:/tmp/
docker exec easy-mysql mysql -uroot -peasy123 -t -e "source /tmp/11-demo-constraints.sql"
```

文件里有且只有 1 条故意写错的语句（末尾那条 `score = 1500`，ERROR 1264），跑完应看到 `ERROR 1264` 恰好一条，`SHOW TABLES` 仍是 8 张基线表。

## 下一篇

[12 · 建表军规：一份可以直接抄的模板](12-table-design-rules.md)
