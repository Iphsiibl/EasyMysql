# 12 · 建表军规：一份可以直接抄的模板

> **一句话价值**：拿到需求先问 7 个问题，落笔就能写出一张三个月内不用推倒重建的表。

**难度**：⭐⭐⭐　|　**时长**：约 35 分钟　|　**涉及表**：`students`、`scores`、`orders`、`order_items`（外加自建的 `products`）

## 什么时候你会遇到它

上线三个月，产品经理说「邮箱以后还能再注册」，你一查——唯一索引没带 `is_deleted`，改它等于全表重写。需求还说「订单列表要显示下单人姓名」，你顺手把 `user_name` 冗余进订单表，后来用户改名没同步，报表里同一个人出现了两个名字。**表是自己写的，返工也得自己来**。

## 本篇你会学到

- [ ] 拿到需求先问的 7 个问题，以及每个问题落到 DDL 的哪一行
- [ ] 6 条命名规矩，让同事 5 秒看懂你的表
- [ ] 三个必备字段：`created_at` / `updated_at` / `is_deleted`
- [ ] 三范式（3NF，消除冗余的三条规则）怎么落地，冗余字段的同步成本有多贵
- [ ] 逻辑删除（不删行、只打标记）为什么要求唯一索引带上 `is_deleted`
- [ ] 一份可以直接抄的模板 DDL，以及改表为什么要挑工具

## 1. 拿到需求先问这 7 个问题

**问题**：拿到一句「做一个商品表」，先动键盘还是先动嘴？

**答案**：先把 7 个问题问完。每个问题的答案，都直接决定 DDL 里的某一行：

| # | 先问这句 | 答案决定了 |
|---|---|---|
| 1 | 一行代表什么？会涨到多大？ | 表名、粒度、要不要提前想归档（`order_items` 60 万行） |
| 2 | 用什么唯一标识一行？ | 主键选自增 `id` 还是业务号（第 11 篇的四种写法） |
| 3 | 每个字段到底存什么？ | 数据类型：钱 `DECIMAL`、时间 `DATETIME`（第 10 篇） |
| 4 | 哪些列不许空、默认是多少？ | `NOT NULL DEFAULT`，NULL 要在查询里处处判 |
| 5 | 哪些组合必须唯一？ | `UNIQUE`，有逻辑删除就必须带上 `is_deleted` |
| 6 | 行与行之间有没有父子关系？ | 建物理外键，还是只建普通索引 + 应用层校验 |
| 7 | 谁改这张表、多久改一次？ | 冗余字段留不留、以后改表走不走在线工具 |

**解释**：第 7 问最容易被跳过，也最贵。问过它的人，不会在 60 万行的表上随手 `MODIFY` 一个字段类型；没问过的人，会在「加个字段」这句话后面补上一个停机窗口。7 个问题问完，表会长什么样，第 3 节的模板给了一个可以直接抄的答案。

## 2. 六条命名规矩

**问题**：命名有标准答案吗？

**答案**：没有标准答案，但全仓库必须统一。这个仓库的规矩：

| 规矩 | 对的写法 | 常见的错法 |
|---|---|---|
| 表名全小写下划线，单复数全库统一 | `orders`、`order_items` | `T_Order`、`orderItems` |
| 主键一律叫 `id` | `id BIGINT UNSIGNED AUTO_INCREMENT` | 拿 `order_no` 当主键 |
| 字段名 snake_case，不写看不懂的缩写 | `created_at`、`category_id` | `crt_tm`、`cat_id`（缩到没人懂） |
| 索引名带前缀：唯一 `uk_`、普通 `idx_`、外键 `fk_` | `uk_scores_student_course` | `uniq1`、`index_2` |
| 时间统一 `created_at` / `updated_at`，开关统一 `is_xxx` | `is_deleted`、`is_paid` | `deleted`、`flag`、`state2` |
| 别拿保留字当字段名 | `status`、`amount` | `order`、`user`（非反引号不可用） |

**实验**：前缀规矩在库里是看得见的：

```sql
SHOW INDEX FROM scores;
```

```text
+--------+------------+--------------------------+--------------+-------------+-----------+-------------+----------+--------+------+------------+---------+---------------+---------+------------+
| Table  | Non_unique | Key_name                 | Seq_in_index | Column_name | Collation | Cardinality | Sub_part | Packed | Null | Index_type | Comment | Index_comment | Visible | Expression |
+--------+------------+--------------------------+--------------+-------------+-----------+-------------+----------+--------+------+------------+---------+---------------+---------+------------+
| scores |          0 | PRIMARY                  |            1 | id          | A         |        2000 |     NULL |   NULL |      | BTREE      |         |               | YES     | NULL       |
| scores |          0 | uk_scores_student_course |            1 | student_id  | A         |         200 |     NULL |   NULL |      | BTREE      |         |               | YES     | NULL       |
| scores |          0 | uk_scores_student_course |            2 | course_id   | A         |        2000 |     NULL |   NULL |      | BTREE      |         |               | YES     | NULL       |
| scores |          1 | idx_scores_course        |            1 | course_id   | A         |          10 |     NULL |   NULL |      | BTREE      |         |               | YES     | NULL       |
+--------+------------+--------------------------+--------------+-------------+-----------+-------------+----------+--------+------+------------+---------+---------------+---------+------------+
```

**解释**：`Non_unique = 0` 是唯一索引，名字都以 `uk_` 开头；`= 1` 是普通索引，以 `idx_` 开头；`Seq_in_index` 有两行的那条就是复合唯一键（第 11 篇）。看到名字就知道性质，不用再查。

## 3. 三个必备字段

**问题**：每张业务表都该有的三列是什么？

**答案**：`created_at`、`updated_at`、`is_deleted`。前两个不用代码手填，第三个是逻辑删除的开关：

```sql
CREATE TABLE products (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT                COMMENT '主键',
  sku         VARCHAR(32)     NOT NULL                               COMMENT '商品编码，全局唯一',
  name        VARCHAR(64)     NOT NULL                               COMMENT '商品名',
  category_id INT UNSIGNED    NOT NULL                               COMMENT '分类 id（逻辑外键，不建物理外键）',
  price       DECIMAL(10,2)   NOT NULL DEFAULT 0.00                  COMMENT '单价，金额一律 DECIMAL',
  stock       INT UNSIGNED    NOT NULL DEFAULT 0                     COMMENT '库存',
  status      TINYINT         NOT NULL DEFAULT 1                     COMMENT '1 上架 0 下架',
  created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP     COMMENT '创建时间，不用手填',
  updated_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP
                                ON UPDATE CURRENT_TIMESTAMP          COMMENT '更新时间，改行自动跳',
  is_deleted  TINYINT         NOT NULL DEFAULT 0                     COMMENT '0 正常 1 逻辑删除',
  PRIMARY KEY (id),
  UNIQUE KEY uk_sku (sku),
  UNIQUE KEY uk_name_is_deleted (name, is_deleted),
  KEY idx_status_created (status, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='商品表（建表模板）';
INSERT INTO products (sku, name, category_id, price, stock)
VALUES ('KB-001', '机械键盘', 3, 299.00, 50);
SELECT id, sku, name, price, stock, created_at, updated_at, is_deleted FROM products;
```

```text
+----+--------+--------------+--------+-------+---------------------+---------------------+------------+
| id | sku    | name         | price  | stock | created_at          | updated_at          | is_deleted |
+----+--------+--------------+--------+-------+---------------------+---------------------+------------+
|  1 | KB-001 | 机械键盘     | 299.00 |    50 | 2026-10-07 14:21:51 | 2026-10-07 14:21:51 |          0 |
+----+--------+--------------+--------+-------+---------------------+---------------------+------------+
```

`price`、`stock`、`status`、三个时间/开关字段一个都没填，全部走默认值。改一行看看 `updated_at`：

```sql
UPDATE products SET price = 279.00 WHERE id = 1;
SELECT id, sku, name, price, stock, created_at, updated_at, is_deleted FROM products;
```

```text
+----+--------+--------------+--------+-------+---------------------+---------------------+------------+
| id | sku    | name         | price  | stock | created_at          | updated_at          | is_deleted |
+----+--------+--------------+--------+-------+---------------------+---------------------+------------+
|  1 | KB-001 | 机械键盘     | 279.00 |    50 | 2026-10-07 14:21:51 | 2026-10-07 14:21:52 |          0 |
+----+--------+--------------+--------+-------+---------------------+---------------------+------------+
```

**解释**：`created_at` 停在 `:51` 没动，`updated_at` 自己跳到 `:52`——`ON UPDATE CURRENT_TIMESTAMP` 干的活，不用写一行代码，也不存在哪个接口忘了更新它。

## 4. 三范式落地：能由主键推出来的列，别存

**问题**：三范式（third normal form）背下来了，建表时到底看什么？

**答案**：三条口诀：

| 范式 | 大白话 | 违反的样子 |
|---|---|---|
| 第一范式 | 一格只放一个值 | `tags VARCHAR(200)` 里塞 `a,b,c` 逗号分隔 |
| 第二范式 | 非主键列要依赖**整个**主键 | 选课表里存「学生姓名」——它只依赖 `student_id` |
| 第三范式 | 非主键列之间不许互相推导 | 订单表里存 `user_name`，它由 `user_id` 推出来 |

第三条最常被「优化」掉：为了少 JOIN 一次，把名字冗余进子表。代价立刻显形：

```sql
CREATE TEMPORARY TABLE t_user_demo (id INT NOT NULL PRIMARY KEY, username VARCHAR(30) NOT NULL);
CREATE TEMPORARY TABLE t_order_demo (id INT NOT NULL PRIMARY KEY, user_id INT NOT NULL, user_name VARCHAR(30) NULL, KEY idx_user (user_id));
INSERT INTO t_user_demo VALUES (1, '张三');
INSERT INTO t_order_demo VALUES (1001, 1, '张三');
UPDATE t_user_demo SET username = '张三丰' WHERE id = 1;
SELECT u.username AS 用户表里的名字, o.user_name AS 订单里冗余的名字
FROM t_user_demo u JOIN t_order_demo o ON o.user_id = u.id;
DROP TEMPORARY TABLE t_user_demo, t_order_demo;
```

```text
+-----------------------+--------------------------+
| 用户表里的名字        | 订单里冗余的名字         |
+-----------------------+--------------------------+
| 张三丰                | 张三                     |
+-----------------------+--------------------------+
```

**解释**：改了主表，子表还挂着旧值，报表里同一个人两个名字。**冗余不是不能用**，代价是每一次 UPDATE 都要多改一张表，还要保证全部入口都改到；只想省一次 JOIN 的话，先想想这个 JOIN 有没有索引（第 13 篇）。

## 5. 逻辑删除的坑：唯一索引必须带上 `is_deleted`

**问题**：`is_deleted = 1` 不就是删了吗，为什么邮箱「唯一」会拦住重新注册？

**答案**：逻辑删除（logical delete）没真删行，旧行还在表里占着唯一索引的位置。两种写法各跑一遍：

```sql
CREATE TABLE demo_member_bad (
  id         INT NOT NULL AUTO_INCREMENT,
  email      VARCHAR(60) NOT NULL,
  is_deleted TINYINT NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  UNIQUE KEY uk_email (email)                     -- ✗ 少了 is_deleted
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='反面：唯一索引没带 is_deleted';
INSERT INTO demo_member_bad (email) VALUES ('amy@example.com');
UPDATE demo_member_bad SET is_deleted = 1 WHERE email = 'amy@example.com';
INSERT INTO demo_member_bad (email) VALUES ('amy@example.com');   -- 想再注册一次
```

```text
ERROR 1062 (23000) at line 1: Duplicate entry 'amy@example.com' for key 'demo_member_bad.uk_email'
```

**解释**：用户注销后用同一个邮箱注册，被「已经删掉的自己」挡在门外，而且回给前端的是一句看不懂的 1062。把唯一索引改成 `(email, is_deleted)`：

```sql
DROP TABLE demo_member_bad;
CREATE TABLE demo_member_good (
  id         INT NOT NULL AUTO_INCREMENT,
  email      VARCHAR(60) NOT NULL,
  is_deleted TINYINT NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  UNIQUE KEY uk_email_is_deleted (email, is_deleted)   -- ✓ 带上 is_deleted
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='正面：唯一索引带 is_deleted';
INSERT INTO demo_member_good (email) VALUES ('amy@example.com');
UPDATE demo_member_good SET is_deleted = 1 WHERE email = 'amy@example.com';
INSERT INTO demo_member_good (email) VALUES ('amy@example.com');
SELECT id, email, is_deleted FROM demo_member_good;
DROP TABLE demo_member_good;
```

```text
+----+-----------------+------------+
| id | email           | is_deleted |
+----+-----------------+------------+
|  2 | amy@example.com |          0 |
|  1 | amy@example.com |          1 |
+----+-----------------+------------+
```

**解释**：`(amy, 0)` 和 `(amy, 1)` 是两个不同的组合，唯一索引放行；要查「未删除的 amy」还得自己加 `WHERE is_deleted = 0`——**逻辑删除的查询成本转嫁给了每一条 SELECT**，这是它换来的代价。

## 6. 改表不是免费的

**问题**：需求加一列，20 万行的表要锁多久？

**答案**：加列和改类型根本不是一回事，同一批 20 万行实测：

```text
+--------------+-----------------+
| 加列毫秒     | 改类型毫秒      |
+--------------+-----------------+
|           43 |            6241 |
+--------------+-----------------+
```

**解释**：MySQL 8.0 的 `ADD COLUMN` 只改元数据（43ms）；`MODIFY` 换类型要整表重建、逐行转换（6241ms，两个数量级）。`UPDATE` 全程持锁，这张表上的读写都得排队。大表改类型别直接上 `ALTER`，挑一个在线改表工具——**`pt-online-schema-change`** 和 **`gh-ost`** 都是建一张影子表、搬数据、再原子换名的思路，锁的时间从「整个窗口」变成「切表那一瞬」。第 7 问「谁改这张表、多久改一次」问的就是这个：写少读多的表可以忍，天天写的核心表必须提前想好退路。

## 7. 完整模板

把第 3 节的 DDL 存成自己的起点：类型选对（第 10 篇）、约束到位（第 11 篇）、命名统一、三个必备字段齐全、唯一索引带 `is_deleted`。它就是配套文件 `lab/queries/12-demo-design.sql` 里那张 `products`，演示完就删干净，库里一张临时表都不留：

```sql
DROP TABLE products;
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

## 三个必须记住的结论

1. **先问 7 个问题再写 DDL**：一行代表什么、主键是什么、类型、NULL 与默认、唯一组合、父子关系、谁改多大——漏问哪一个，返工时都要补。
2. **冗余换来的每一次省 JOIN，都要用同步成本还**：改名只改了主表，子表立刻出现两个名字。
3. **逻辑删除必须把 `is_deleted` 写进唯一索引**，否则用户注销后连自己的邮箱都注册不回来。

## 常见错误

### ❌ 错误做法：唯一索引不带 `is_deleted`

```sql
CREATE TABLE demo_member_bad (
  id         INT NOT NULL AUTO_INCREMENT,
  email      VARCHAR(60) NOT NULL,
  is_deleted TINYINT NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  UNIQUE KEY uk_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
INSERT INTO demo_member_bad (email) VALUES ('amy@example.com');
UPDATE demo_member_bad SET is_deleted = 1 WHERE email = 'amy@example.com';
INSERT INTO demo_member_bad (email) VALUES ('amy@example.com');
```

```text
ERROR 1062 (23000) at line 1: Duplicate entry 'amy@example.com' for key 'demo_member_bad.uk_email'
```

**为什么错**：`is_deleted = 1` 的旧行仍占着 `uk_email` 的位置，重复邮箱永远插不进去。

**正确做法**：唯一索引带上标记列（第 5 节的 `demo_member_good`），并在所有查询里补 `WHERE is_deleted = 0`：

```sql
DROP TABLE demo_member_bad;
CREATE TABLE demo_member_good (
  id         INT NOT NULL AUTO_INCREMENT,
  email      VARCHAR(60) NOT NULL,
  is_deleted TINYINT NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  UNIQUE KEY uk_email_is_deleted (email, is_deleted)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
INSERT INTO demo_member_good (email) VALUES ('amy@example.com');
UPDATE demo_member_good SET is_deleted = 1 WHERE email = 'amy@example.com';
INSERT INTO demo_member_good (email) VALUES ('amy@example.com');
SELECT id, email, is_deleted FROM demo_member_good
WHERE email = 'amy@example.com' AND is_deleted = 0;
DROP TABLE demo_member_good;
```

```text
+----+-----------------+------------+
| id | email           | is_deleted |
+----+-----------------+------------+
|  2 | amy@example.com |          0 |
+----+-----------------+------------+
```

## 动手练

- [ ] 给一张表加 `content TEXT NOT NULL DEFAULT ''`，看它报什么；再给 `TEXT` 建普通索引，看第二条报错
- [ ] 用 7 个问题过一遍 `order_items`：它为什么没有物理外键？`quantity` 的默认值是多少？
- [ ] 你们线上有逻辑删除的表吗？它的唯一索引带 `is_deleted` 了吗？没带会出什么事？

<details>
<summary>点开看答案</summary>

```sql
-- 练习 1：TEXT 不能有默认值（1101），也不能裸建索引（1170）
CREATE TABLE t_text_demo (id INT NOT NULL PRIMARY KEY, content TEXT NOT NULL DEFAULT '');
```

```text
ERROR 1101 (42000) at line 1: BLOB, TEXT, GEOMETRY or JSON column 'content' can't have a default value
```

```sql
CREATE TABLE t_text_demo (id INT NOT NULL PRIMARY KEY, content TEXT NOT NULL, KEY idx_content (content));
```

```text
ERROR 1170 (42000) at line 1: BLOB/TEXT column 'content' used in key specification without a key length
```

```sql
-- 正确做法：装得下就用 VARCHAR，装不下就给索引指定前缀长度
CREATE TABLE t_text_demo (id INT NOT NULL PRIMARY KEY, content VARCHAR(500) NOT NULL, KEY idx_content (content));
SHOW CREATE TABLE t_text_demo\G
DROP TABLE t_text_demo;
```

```text
*************************** 1. row ***************************
       Table: t_text_demo
Create Table: CREATE TABLE `t_text_demo` (
  `id` int NOT NULL,
  `content` varchar(500) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_content` (`content`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
```

```sql
-- 练习 2：答案对照（在库上跑一下就知道）
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

没有 `FOREIGN KEY`，只有普通索引 `idx_items_order`——第 11 篇量过：60 万行的明细表每插一行都要回父表查一次，不划算；`quantity` 默认 `1`。

</details>

## 配套实验

```powershell
docker cp lab/queries/12-demo-design.sql easy-mysql:/tmp/
docker exec easy-mysql mysql -uroot -peasy123 -t -e "source /tmp/12-demo-design.sql"
```

文件 0 条错误：建 `products` → 验证三个必备字段 → 演示逻辑删除的唯一索引坑 → 三张自建表全部 `DROP`，跑完 `SHOW TABLES` 仍是 8 张基线表。

## 下一篇

[13 · 索引是什么：扫 19 万行变成扫 29 行](13-index-what.md)
