# 附录 A2 · 练习题与答案

> **一句话价值**：30 道由浅入深的题，做完能确认自己真的会了。

**建议**：先自己写，写不出来再看答案。答案用 `<details>` 折叠。

## 基础（01~08）

1. 查出所有姓「王」的学生，显示姓名和城市
2. 查出每个城市的女生数量，按数量倒序
3. 查出成绩在 90 分以上的记录，显示学生名、课程名、分数
4. 统计每个城市的男生人数
5. 找出平均分最高的班级
6. 查出每门课的及格率，只看及格率低于 65% 的课
7. 找出选课数超过 10 人的课程
8. 列出所有学生和他们的平均分（没考的显示 0）

## 进阶（09~16）

9. 列出所有学生（包括没参加考试的）及其考试科目数
10. 找出有 5 门及以上课程不及格的学生
11. 统计每个城市的用户数，只保留用户数 > 100 的城市
12. 找出下单次数最多的前 5 个用户
13. 找出金额最大的 3 笔订单及其明细行数
14. 用一个子查询改写第 4 题
15. 列出每个月的订单量和销售额
16. 把 `orders` 按状态分组，统计每组金额均值和最大值

## 性能（17~22）

17. `EXPLAIN` 分析 `SELECT * FROM orders_slow WHERE user_id = 42`，指出问题
18. 在 `orders_slow` 上建索引，让第 17 题的 `type` 变成 `ref`
19. 找出 `orders` 表中区分度最低的两个字段，说明为什么不该单独建索引
20. 写一条必然产生 `Using filesort` 的 SQL
21. 设计一个联合索引，支持「按状态查某时间段订单」
22. 一条 SQL 查询 2024 年 7 月和 8 月的订单数（提示：条件 OR 或 `IN`）

## 事务（23~26）

23. 完成一次转账，测试 `ROLLBACK`
24. 说出「转账 SQL 写在事务里，但第二条 UPDATE 失败」时会发生什么
25. 说出 RR 和 RC 在「重复执行同一条查询」上的区别
26. 解释为什么「先查库存再更新」需要加锁

## 综合（27~30）

27. 找出「下单金额排第 3 的用户」和「下单次数排第 5 的用户」，用一次查询输出
28. 用 `JOIN` 查出每个城市的「学生数、用户数」，并算出比值
29. 找出有订单、但 2024 年 12 月没下过单的用户
30. 设计一张「商品库存变动流水表」，写出 DDL

---

<details>
<summary>参考答案 1~8</summary>

```sql
-- 1
SELECT name, city FROM students WHERE name LIKE '王%';
-- 2
SELECT city, COUNT(*) FROM students WHERE gender='女' GROUP BY city ORDER BY 2 DESC;
-- 3
SELECT s.name, c.name, sc.score
FROM scores sc JOIN students s ON s.id=sc.student_id JOIN courses c ON c.id=sc.course_id
WHERE sc.score >= 90;
-- 4
SELECT city, COUNT(*) FROM students WHERE gender='男' GROUP BY city;
-- 5
SELECT s.class_name, AVG(sc.score) a FROM students s JOIN scores sc ON sc.student_id=s.id
GROUP BY s.class_name ORDER BY a DESC LIMIT 1;
-- 6
SELECT c.name, ROUND(100*SUM(sc.score>=60)/COUNT(*),1) pass_rate FROM scores sc JOIN courses c ON c.id=sc.course_id
GROUP BY c.id HAVING pass_rate < 65;   -- 及格率最高的一门才 70.5%，低于 65% 的有 4 门
-- 7
SELECT c.name, COUNT(*) n FROM scores sc JOIN courses c ON c.id=sc.course_id
GROUP BY c.id HAVING n > 10;
-- 8
SELECT s.name, IFNULL(AVG(sc.score),0) FROM students s LEFT JOIN scores sc ON sc.student_id=s.id
GROUP BY s.id, s.name;
```

</details>

<details>
<summary>参考答案 9~16</summary>

```sql
-- 9
SELECT s.name, COUNT(sc.id) FROM students s LEFT JOIN scores sc ON sc.student_id=s.id GROUP BY s.id;
-- 10
SELECT s.name FROM students s JOIN scores sc ON sc.student_id=s.id
GROUP BY s.id HAVING SUM(sc.score<60) >= 5;   -- 返回 46 人，没有人 10 门全挂，最多挂 8 门
-- 11
SELECT city, COUNT(*) n FROM users GROUP BY city HAVING n>100;
-- 12
SELECT user_id, COUNT(*) n FROM orders GROUP BY user_id ORDER BY n DESC LIMIT 5;
-- 13
SELECT o.id, o.amount, COUNT(i.id) c FROM orders o JOIN order_items i ON i.order_id=o.id
GROUP BY o.id ORDER BY o.amount DESC LIMIT 3;
-- 14
SELECT city, COUNT(*) FROM (SELECT city FROM students WHERE gender='男') t GROUP BY city;
-- 15
SELECT DATE_FORMAT(created_at,'%Y-%m') ym, COUNT(*) orders, ROUND(SUM(amount),2) amt
FROM orders GROUP BY ym ORDER BY ym;
-- 16
SELECT status, AVG(amount), MAX(amount) FROM orders GROUP BY status;
```

</details>

<details>
<summary>参考答案 17~22</summary>

```sql
-- 17
EXPLAIN SELECT * FROM orders_slow WHERE user_id = 42;
-- type=ALL、possible_keys=NULL：没有可用索引，全表扫约 20 万行
-- 18
ALTER TABLE orders_slow ADD INDEX idx_user (user_id);
EXPLAIN SELECT * FROM orders_slow WHERE user_id = 42;   -- type=ref、key=idx_user、rows≈29
ALTER TABLE orders_slow DROP INDEX idx_user;            -- 演示完必须删掉，orders_slow 是无索引对照组
-- 19
SELECT 'status' AS col, COUNT(DISTINCT status) AS distinct_n FROM orders
UNION ALL SELECT 'quantity', COUNT(DISTINCT quantity) FROM orders
UNION ALL SELECT 'product_id', COUNT(DISTINCT product_id) FROM orders
UNION ALL SELECT 'user_id', COUNT(DISTINCT user_id) FROM orders
UNION ALL SELECT 'amount', COUNT(DISTINCT amount) FROM orders
UNION ALL SELECT 'created_at', COUNT(DISTINCT created_at) FROM orders
ORDER BY distinct_n;
-- 排在最前的 status=4、quantity=5：一个取值平均对 5 万行，建了索引也筛不掉多少行
-- 20
SELECT * FROM orders ORDER BY amount DESC;   -- amount 无索引 → Using filesort
-- 21
SHOW INDEX FROM orders;   -- idx_orders_status_created (status, created_at) 就是这个设计，本库已有
EXPLAIN SELECT * FROM orders WHERE status='paid' AND created_at >= '2024-07-01' AND created_at < '2024-08-01';
-- 等值列在前、范围列在后 → type=range；新库先建索引：
-- ALTER TABLE orders ADD INDEX idx_orders_status_created (status, created_at);
-- 22
SELECT COUNT(*) FROM orders
WHERE (created_at >= '2024-07-01' AND created_at < '2024-08-01')
   OR (created_at >= '2024-08-01' AND created_at < '2024-09-01');
-- 返回 33976；等价的范围写法 WHERE created_at >= '2024-07-01' AND created_at < '2024-09-01'
```

</details>

<details>
<summary>参考答案 23~26</summary>

**23 · 转账 + ROLLBACK**

```sql
SELECT id, balance FROM users WHERE id IN (1, 2);   -- 转账前：6201.78 / 5086.48
START TRANSACTION;
UPDATE users SET balance = balance - 100 WHERE id = 1;
UPDATE users SET balance = balance + 100 WHERE id = 2;
SELECT id, balance FROM users WHERE id IN (1, 2);   -- 事务里已变：6101.78 / 5186.48
ROLLBACK;
SELECT id, balance FROM users WHERE id IN (1, 2);   -- 回滚后：回到转账前
```

要点：`START TRANSACTION` 开启事务，`COMMIT` 才真正落盘，`ROLLBACK` 把整个事务撤销；两条 UPDATE 要么一起生效，要么一起作废。既不 COMMIT 也不 ROLLBACK 就断开连接，MySQL 同样会替你回滚。

**24 · 第二条 UPDATE 失败会怎样**

```sql
START TRANSACTION;
UPDATE users SET balance = balance - 100 WHERE id = 1;   -- 第一条成功
UPDATE users SET age = -1 WHERE id = 2;                  -- 第二条报错 1264：age 无符号，-1 超范围
SELECT balance FROM users WHERE id = 1;                  -- 6101.78：第一条还留在事务里，没被带走
ROLLBACK;                                                -- 显式回滚，第一条也一起撤销
SELECT balance FROM users WHERE id = 1;                  -- 6201.78，回到转账前
```

要点：MySQL 只回滚出错的那一条语句，事务仍然开着——要么 `ROLLBACK` 把第一条也撤销，要么 `COMMIT` 让第一条单独生效；什么都不做，连接断开时会隐式回滚。如果压根没开事务（autocommit=1），第一条早已提交，撤不回来。

**25 · RR 和 RC 的区别（开两个连接演示）**

```sql
-- 先准备演示表
CREATE TABLE t_iso_demo (id INT NOT NULL PRIMARY KEY, v INT NOT NULL);
INSERT INTO t_iso_demo VALUES (1, 1);

-- 连接 A（把 SET TRANSACTION 那行换成 READ COMMITTED 再跑一遍）：
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
START TRANSACTION;
SELECT v FROM t_iso_demo;   -- 第一次读：v=1，RR 从这次读起建立事务快照
-- （这里切到连接 B 执行：UPDATE t_iso_demo SET v = 2; COMMIT;）
SELECT v FROM t_iso_demo;   -- 第二次读：RR 还是 v=1；RC 变成 v=2
COMMIT;

-- 演示完删表
DROP TABLE t_iso_demo;
```

要点：RR 下事务的第一次读建立快照，之后重复执行同一条查询读的都是这份快照，结果永远一致；RC 下每条语句都取最新已提交的数据，重复读会看到别人提交的新值。

**26 · 先查库存再更新为什么要加锁（开两个连接演示）**

```sql
-- 先准备演示表
CREATE TABLE t_stock_demo (id INT NOT NULL PRIMARY KEY, stock INT NOT NULL);
INSERT INTO t_stock_demo VALUES (1, 10);

-- 连接 A：
START TRANSACTION;
SELECT stock FROM t_stock_demo WHERE id = 1 FOR UPDATE;   -- 读到 10，并把这行锁住
-- （切到连接 B，在 A 提交前执行，等 1 秒后报错）：
-- SET innodb_lock_wait_timeout = 1;
-- START TRANSACTION;
-- SELECT stock FROM t_stock_demo WHERE id = 1 FOR UPDATE;   → ERROR 1205 Lock wait timeout
-- 回到连接 A 收尾：
UPDATE t_stock_demo SET stock = stock - 1 WHERE id = 1;
COMMIT;
DROP TABLE t_stock_demo;
```

要点：先 SELECT 再 UPDATE 中间有窗口，两个事务读到同一个旧值、各自写回就丢一次更新（库存少扣一次，甚至超卖）；`SELECT ... FOR UPDATE` 给行加排他锁，后到的事务只能等前一个提交后重读。等锁太贵的场景改用版本号，在 UPDATE 时校验（乐观锁）。

</details>

<details>
<summary>参考答案 27~30</summary>

**27 · 一次查询输出两个名次**

```sql
SELECT
  (SELECT user_id FROM orders GROUP BY user_id ORDER BY SUM(amount) DESC, user_id LIMIT 1 OFFSET 2) AS amt_rank3,
  (SELECT user_id FROM orders GROUP BY user_id ORDER BY COUNT(*) DESC, user_id LIMIT 1 OFFSET 4) AS cnt_rank5;
-- amt_rank3=1、cnt_rank5=3542；OFFSET 从 0 数起，ORDER BY 补 user_id 让并列时结果固定
```

**28 · 每个城市的学生数 / 用户数**

```sql
SELECT s.city, s.n AS students, u.n AS users, ROUND(s.n/u.n, 4) AS ratio
FROM (SELECT city, COUNT(*) n FROM students GROUP BY city) s
JOIN (SELECT city, COUNT(*) n FROM users GROUP BY city) u ON u.city = s.city;
-- 两表城市一致，配对出 6 行，如上海 34 / 826 = 0.0412
```

**29 · 有订单、但 12 月没下过单的用户**

```sql
SELECT user_id FROM orders GROUP BY user_id HAVING SUM(created_at >= '2024-12-01') = 0;
-- SUM(条件) 数的就是 12 月的单数，=0 即 12 月一单没下；返回 368 个用户
```

**30 · 商品库存变动流水表 DDL**

```sql
CREATE TABLE stock_flows (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT            COMMENT '主键',
  product_id  INT UNSIGNED    NOT NULL                           COMMENT '商品 id（逻辑外键，只建索引，不建物理外键）',
  change_type TINYINT         NOT NULL                           COMMENT '1 入库 2 出库 3 盘盈 4 盘亏',
  change_qty  INT             NOT NULL                           COMMENT '变动数量：正数入库、负数出库',
  stock_after INT UNSIGNED    NOT NULL                           COMMENT '变动后的库存，用来对账',
  order_id    BIGINT UNSIGNED          DEFAULT NULL              COMMENT '关联订单 id，盘点没有订单就填 NULL',
  reason      VARCHAR(100)    NOT NULL DEFAULT ''                COMMENT '变动原因备注',
  created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，不用手填',
  updated_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP
              ON UPDATE CURRENT_TIMESTAMP                        COMMENT '更新时间，改行自动跳',
  PRIMARY KEY (id),
  CONSTRAINT chk_qty CHECK (change_qty <> 0),    -- 没有变动量的流水没有意义
  CONSTRAINT chk_stock CHECK (stock_after >= 0), -- 库存不为负
  KEY idx_product_created (product_id, created_at),
  KEY idx_stock_order (order_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='商品库存变动流水表';
```

要点：每次变动记一行，`stock_after` 存变动后库存，把流水加回去能和现存量对账；流水只增不改，所以不放 `is_deleted`；`product_id`、`order_id` 是逻辑外键，只建索引不建物理外键；`CHECK` 兜底挡住「变动量为 0」「库存为负」，`(product_id, created_at)` 支持按商品查出入库历史。

</details>

---

## 返回

[附录 A3 · 术语中英对照表](A3-glossary.md)
