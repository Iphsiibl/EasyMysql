-- 16-demo-optimize.sql · 第 16 篇配套实验：慢查询优化实战
-- 结构 = 文章的四步流程：抓 → 分析 → 开方 → 验证
-- 自清理：临时索引全部 DROP、汇总表 DROP、存储过程 DROP、插入的行全部 DELETE、
--         会话变量 long_query_time 恢复原值，末尾跑基线校验
-- 计时用 NOW(6)（和 14 号实验一致），每条先暖一遍缓存再计时

SET NAMES utf8mb4;

USE easy_mysql;

-- ============================================================
-- 第 1 步：抓 —— 慢查询日志实况
-- ============================================================
SHOW VARIABLES LIKE 'slow_query_log';
SHOW VARIABLES LIKE 'slow_query_log_file';
SHOW VARIABLES LIKE 'long_query_time';
SHOW VARIABLES LIKE 'log_output';

-- ★ 先记下原值（会话级改动，但照样恢复回去）
SET @old_lqt = @@SESSION.long_query_time;

-- 阈值调到 0（只对当前会话生效），把 4 条候选 SQL 放进日志
SET SESSION long_query_time = 0;
SELECT COUNT(*) FROM orders WHERE amount > 5000;
SELECT id, user_id, amount FROM orders ORDER BY id LIMIT 100000, 10;
SELECT id, amount FROM orders WHERE status = 'paid' ORDER BY amount DESC LIMIT 10;
SELECT COUNT(*) FROM orders o JOIN order_items i ON i.order_id = o.id;
SET SESSION long_query_time = @old_lqt;
SHOW VARIABLES LIKE 'long_query_time';

-- 日志是文件，得去容器里看（文件名以你上面 SHOW VARIABLES 的输出为准）：
--   docker exec easy-mysql sh -c 'tail -n 40 /var/lib/mysql/<容器ID>-slow.log'
--   docker exec easy-mysql sh -c 'grep Query_time /var/lib/mysql/<容器ID>-slow.log | sort -rn -k3 | head -5'
-- pt-query-digest 本镜像没装（连 perl 都没有），见文章第 1 节的安装指引

-- ============================================================
-- 第 2 步：分析 —— 5 条慢 SQL 的"病历"（都是优化前的计划）
-- ============================================================

-- 慢 SQL ①：amount 没索引，全表扫描
EXPLAIN SELECT COUNT(*) FROM orders WHERE amount > 5000;

-- 慢 SQL ②：深分页，先扫掉前 10 万行
EXPLAIN ANALYZE SELECT id, user_id, amount FROM orders ORDER BY id LIMIT 100000, 10\G

-- 慢 SQL ③：排序字段不在索引里 → Using filesort
EXPLAIN SELECT id, amount FROM orders WHERE status = 'paid' ORDER BY amount DESC LIMIT 10;

-- 慢 SQL ④：两个索引都能用，优化器挑了带 filesort 的那个
EXPLAIN SELECT * FROM orders WHERE status = 'paid' AND user_id BETWEEN 1 AND 100 ORDER BY user_id;

-- 慢 SQL ⑤：OR 的一边没有索引 → 整条放弃索引
EXPLAIN SELECT * FROM orders WHERE user_id = 42 OR amount > 5000;

-- ============================================================
-- 第 3 步：开方 —— 逐条优化（每条都是前后对照）
-- ============================================================

-- ---------- 慢 SQL ① 缺索引：加索引 ----------
SELECT COUNT(*) FROM orders WHERE amount > 5000;          -- 暖缓存
SET @t0 = NOW(6);
SELECT COUNT(*) FROM orders WHERE amount > 5000;
SELECT ROUND(TIMESTAMPDIFF(MICROSECOND,@t0,NOW(6))/1000,1) AS 优化前_毫秒;

ALTER TABLE orders ADD INDEX idx_amount (amount);
EXPLAIN SELECT COUNT(*) FROM orders WHERE amount > 5000;   -- type=range，rows 从 199430 掉到 83030

SELECT COUNT(*) FROM orders WHERE amount > 5000;          -- 暖缓存
SET @t0 = NOW(6);
SELECT COUNT(*) FROM orders WHERE amount > 5000;
SELECT ROUND(TIMESTAMPDIFF(MICROSECOND,@t0,NOW(6))/1000,1) AS 优化后_毫秒;

ALTER TABLE orders DROP INDEX idx_amount;   -- 清理（留着会干扰第 17 篇）

-- ---------- 慢 SQL ② 深分页：三种写法（按主键排序） ----------
-- (a) 原始：扫 100010 行
EXPLAIN ANALYZE SELECT id, user_id, amount FROM orders ORDER BY id LIMIT 100000, 10\G
-- (b) 延迟关联：内层只取主键、外层回表 10 次，但本例的列都在主键索引里 → 还是扫 100010 行
EXPLAIN ANALYZE SELECT o.* FROM orders o
JOIN (SELECT id FROM orders ORDER BY id LIMIT 100000, 10) t ON t.id = o.id\G
-- (c) 书签式（keyset）：从 id 直接定位，只碰 10 行
EXPLAIN ANALYZE SELECT id, user_id, amount FROM orders WHERE id > 199990 ORDER BY id LIMIT 10\G

SELECT id, user_id, amount FROM orders ORDER BY id LIMIT 100000, 10;
SET @t0 = NOW(6);
SELECT id, user_id, amount FROM orders ORDER BY id LIMIT 100000, 10;
SELECT ROUND(TIMESTAMPDIFF(MICROSECOND,@t0,NOW(6))/1000,1) AS 原始分页_毫秒;

SELECT id, user_id, amount FROM orders WHERE id > 199990 ORDER BY id LIMIT 10;
SET @t0 = NOW(6);
SELECT id, user_id, amount FROM orders WHERE id > 199990 ORDER BY id LIMIT 10;
SELECT ROUND(TIMESTAMPDIFF(MICROSECOND,@t0,NOW(6))/1000,1) AS 书签式分页_毫秒;

-- 换个排序列（按 user_id 排），延迟关联才开始发力：
-- (a) 原始：全表扫 200000 行 + filesort
EXPLAIN ANALYZE SELECT * FROM orders ORDER BY user_id LIMIT 100000, 10\G
-- (b) 延迟关联：走覆盖索引扫 100010 行，外层只回表 10 次
EXPLAIN ANALYZE SELECT o.* FROM orders o
JOIN (SELECT id FROM orders ORDER BY user_id LIMIT 100000, 10) t ON t.id = o.id\G

SELECT * FROM orders ORDER BY user_id LIMIT 100000, 10;
SET @t0 = NOW(6);
SELECT * FROM orders ORDER BY user_id LIMIT 100000, 10;
SELECT ROUND(TIMESTAMPDIFF(MICROSECOND,@t0,NOW(6))/1000,1) AS 原始分页_user排序_毫秒;

SELECT o.* FROM orders o JOIN (SELECT id FROM orders ORDER BY user_id LIMIT 100000, 10) t ON t.id = o.id;
SET @t0 = NOW(6);
SELECT o.* FROM orders o JOIN (SELECT id FROM orders ORDER BY user_id LIMIT 100000, 10) t ON t.id = o.id;
SELECT ROUND(TIMESTAMPDIFF(MICROSECOND,@t0,NOW(6))/1000,1) AS 延迟关联_user排序_毫秒;

-- ---------- 慢 SQL ③ Using filesort：建联合索引让排序走索引 ----------
EXPLAIN SELECT id, amount FROM orders WHERE status = 'paid' ORDER BY amount DESC LIMIT 10;

SELECT id, amount FROM orders WHERE status = 'paid' ORDER BY amount DESC LIMIT 10;   -- 暖缓存
SET @t0 = NOW(6);
SELECT id, amount FROM orders WHERE status = 'paid' ORDER BY amount DESC LIMIT 10;
SELECT ROUND(TIMESTAMPDIFF(MICROSECOND,@t0,NOW(6))/1000,1) AS 建索引前_毫秒;

ALTER TABLE orders ADD INDEX idx_status_amount (status, amount);
EXPLAIN SELECT id, amount FROM orders WHERE status = 'paid' ORDER BY amount DESC LIMIT 10;
-- Extra 里的 Using filesort 消失了，Backward index scan = 反向扫索引就够

SELECT id, amount FROM orders WHERE status = 'paid' ORDER BY amount DESC LIMIT 10;
SET @t0 = NOW(6);
SELECT id, amount FROM orders WHERE status = 'paid' ORDER BY amount DESC LIMIT 10;
SELECT ROUND(TIMESTAMPDIFF(MICROSECOND,@t0,NOW(6))/1000,1) AS 建索引后_毫秒;

ALTER TABLE orders DROP INDEX idx_status_amount;   -- 清理

-- ---------- 慢 SQL ④ 优化器选错索引：FORCE INDEX 只是止痛 ----------
EXPLAIN SELECT * FROM orders WHERE status = 'paid' AND user_id BETWEEN 1 AND 100 ORDER BY user_id;
EXPLAIN SELECT * FROM orders FORCE INDEX (idx_orders_user)
WHERE status = 'paid' AND user_id BETWEEN 1 AND 100 ORDER BY user_id;

-- 看实际扫描量和真实耗时（EXPLAIN ANALYZE 会真跑一遍）
EXPLAIN ANALYZE SELECT * FROM orders WHERE status = 'paid' AND user_id BETWEEN 1 AND 100 ORDER BY user_id\G
EXPLAIN ANALYZE SELECT * FROM orders FORCE INDEX (idx_orders_user)
WHERE status = 'paid' AND user_id BETWEEN 1 AND 100 ORDER BY user_id\G
-- 为什么选错、比 FORCE INDEX 更好的办法：第 17 篇

-- ---------- 慢 SQL ⑤ OR 拖后腿：改写 UNION ALL ----------
EXPLAIN SELECT * FROM orders WHERE user_id = 42 OR amount > 5000;
EXPLAIN SELECT id, user_id, amount FROM orders WHERE user_id = 42
UNION ALL
SELECT id, user_id, amount FROM orders WHERE amount > 5000;
-- 注意：UNION ALL 第二个分支还是全表扫，省掉的只是"整条查询被 OR 拖死"这件事

-- ============================================================
-- 实战二：批量写入 —— 攒批 + 事务（插完就删干净）
-- ============================================================
DELIMITER $$
CREATE PROCEDURE ins_one_by_one(IN n INT)
BEGIN
  DECLARE i INT DEFAULT 0;
  WHILE i < n DO
    INSERT INTO orders_slow (user_id, product_id, quantity, amount, status, created_at, updated_at)
    VALUES (1, 1, 1, 10.00, 'created', '2024-06-01 12:00:00', '2024-06-01 13:00:00');
    SET i = i + 1;
  END WHILE;
END$$
CREATE PROCEDURE ins_batch_tx(IN n INT)
BEGIN
  DECLARE i INT DEFAULT 0;
  START TRANSACTION;
  WHILE i < n DO
    INSERT INTO orders_slow (user_id, product_id, quantity, amount, status, created_at, updated_at)
    VALUES (1, 1, 1, 10.00, 'created', '2024-06-01 12:00:00', '2024-06-01 13:00:00');
    SET i = i + 1;
  END WHILE;
  COMMIT;
END$$
DELIMITER ;

-- A：每条 INSERT 各自提交一次（默认 autocommit=1）→ 2000 次提交
SET @t0 = NOW(6);
CALL ins_one_by_one(2000);
SELECT ROUND(TIMESTAMPDIFF(MICROSECOND,@t0,NOW(6))/1000,1) AS 逐条插入2000行_毫秒;

-- B：同样 2000 条，攒在一个事务里 → 1 次提交
SET @t0 = NOW(6);
CALL ins_batch_tx(2000);
SELECT ROUND(TIMESTAMPDIFF(MICROSECOND,@t0,NOW(6))/1000,1) AS 攒批事务2000行_毫秒;

-- ★ 现场恢复：删掉这 4000 行
SELECT COUNT(*) AS 插入后行数 FROM orders_slow;
DELETE FROM orders_slow WHERE id > 200000;
SELECT COUNT(*) AS 删除后行数 FROM orders_slow;
ANALYZE TABLE orders_slow;

DROP PROCEDURE ins_one_by_one;
DROP PROCEDURE ins_batch_tx;
SHOW PROCEDURE STATUS WHERE Db = 'easy_mysql';   -- 期望：空

-- ============================================================
-- 实战三：COUNT(*) 太慢的三个对策（这里实测其中两个）
-- ============================================================

-- 对策 1：近似值 —— 不数了，直接看执行计划估的行数
EXPLAIN SELECT * FROM orders;
SELECT TABLE_ROWS AS 估算行数 FROM information_schema.TABLES
 WHERE TABLE_SCHEMA = 'easy_mysql' AND TABLE_NAME = 'orders';
SELECT COUNT(*) AS 精确行数 FROM orders;

-- 对策 2：汇总表 —— 每天一行，365 行代替 20 万行
CREATE TABLE orders_cnt_daily (
  day DATE NOT NULL PRIMARY KEY,
  total INT NOT NULL
) ENGINE=InnoDB;
INSERT INTO orders_cnt_daily (day, total)
SELECT DATE(created_at), COUNT(*) FROM orders GROUP BY DATE(created_at);

EXPLAIN SELECT total FROM orders_cnt_daily WHERE day = '2024-07-01';
EXPLAIN SELECT COUNT(*) FROM orders
 WHERE created_at >= '2024-07-01' AND created_at < '2024-07-02';

SELECT COUNT(*) FROM orders;                      -- 暖缓存
SET @t0 = NOW(6);
SELECT COUNT(*) FROM orders;
SELECT ROUND(TIMESTAMPDIFF(MICROSECOND,@t0,NOW(6))/1000,1) AS 全表COUNT_毫秒;

SET @t0 = NOW(6);
SELECT total FROM orders_cnt_daily WHERE day = '2024-07-01';
SELECT ROUND(TIMESTAMPDIFF(MICROSECOND,@t0,NOW(6))/1000,1) AS 查汇总表_毫秒;

DROP TABLE orders_cnt_daily;
SHOW TABLES LIKE 'orders_cnt%';   -- 期望：空

-- ============================================================
-- 别过度优化：本仓库大部分查询本来就在毫秒级以下
-- ============================================================
SELECT COUNT(*) FROM users;
SET @t0 = NOW(6);
SELECT COUNT(*) FROM users;
SELECT ROUND(TIMESTAMPDIFF(MICROSECOND,@t0,NOW(6))/1000,1) AS count_users_毫秒;

SELECT COUNT(*) FROM scores;
SET @t0 = NOW(6);
SELECT COUNT(*) FROM scores;
SELECT ROUND(TIMESTAMPDIFF(MICROSECOND,@t0,NOW(6))/1000,1) AS count_scores_毫秒;

SELECT name, city FROM students WHERE city = '北京';
SET @t0 = NOW(6);
SELECT name, city FROM students WHERE city = '北京';
SELECT ROUND(TIMESTAMPDIFF(MICROSECOND,@t0,NOW(6))/1000,1) AS students北京_毫秒;

SELECT COUNT(*) FROM students WHERE name = '王伟';
SET @t0 = NOW(6);
SELECT COUNT(*) FROM students WHERE name = '王伟';
SELECT ROUND(TIMESTAMPDIFF(MICROSECOND,@t0,NOW(6))/1000,1) AS students王伟_毫秒;

-- ============================================================
-- 收尾自检：行数、索引、变量全部回到基线
-- ============================================================
SELECT COUNT(*) AS students行数 FROM students;
SELECT COUNT(*) AS courses行数 FROM courses;
SELECT COUNT(*) AS scores行数 FROM scores;
SELECT COUNT(*) AS users行数 FROM users;
SELECT COUNT(*) AS orders行数 FROM orders;
SELECT COUNT(*) AS orders_slow行数 FROM orders_slow;
SELECT COUNT(*) AS order_items行数 FROM order_items;
SELECT COUNT(*) AS bad_design_demo行数 FROM bad_design_demo;
SHOW INDEX FROM orders;
SHOW INDEX FROM orders_slow;
SHOW TABLES LIKE 'orders_cnt%';
SHOW PROCEDURE STATUS WHERE Db = 'easy_mysql';
SHOW VARIABLES LIKE 'long_query_time';
