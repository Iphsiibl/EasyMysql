-- 16-demo-optimize.sql · 第 16 篇配套实验：5 条慢 SQL 优化实战

SET NAMES utf8mb4;

-- 用法：先跑一遍 EXPLAIN 和 SHOW PROFILES 看现状，再按注释里的方案改写，对比前后

USE easy_mysql;

-- ============================================================
-- 慢 SQL ① 缺索引：type = ALL
-- ============================================================
EXPLAIN SELECT COUNT(*) FROM orders WHERE amount > 5000;   -- type=ALL, rows≈100000

-- 优化：加索引
ALTER TABLE orders ADD INDEX idx_amount (amount);
EXPLAIN SELECT COUNT(*) FROM orders WHERE amount > 5000;   -- type=range, rows 骤降

SET profiling = 1;
SELECT COUNT(*) FROM orders WHERE amount > 5000;
SHOW PROFILES;
-- 本机约 0.031s → 0.011s。绝对值因机器而异，
-- 但 EXPLAIN 的 rows 从 ~10 万降到 1 万上下，这个是稳定的。

ALTER TABLE orders DROP INDEX idx_amount;   -- 清理（留着会影响第 17 篇的实验）

-- ============================================================
-- 慢 SQL ② 深分页：LIMIT 100000, 10
-- ============================================================
SET profiling = 1;
SELECT id, user_id, amount FROM orders ORDER BY id LIMIT 100000, 10;
SHOW PROFILES;
-- 数据库必须先读出并丢弃前 10 万行

-- 优化 A：延迟关联（覆盖索引先取 id，再回表取整行）
SET profiling = 1;
SELECT o.* FROM orders o
JOIN (SELECT id FROM orders ORDER BY id LIMIT 100000, 10) t ON t.id = o.id;
SHOW PROFILES;

-- 优化 B：书签式分页（记住上次看到的位置，无 LIMIT OFFSET）
SET profiling = 1;
SELECT id, user_id, amount FROM orders WHERE id > 199990 ORDER BY id LIMIT 10;
SHOW PROFILES;
-- 这是最快的一种分页，第 17 篇展开讲原理

-- ============================================================
-- 慢 SQL ③ 排序字段没索引：Using filesort
-- ============================================================
EXPLAIN SELECT id, amount FROM orders WHERE status = 'paid' ORDER BY amount DESC LIMIT 10;
-- Extra: Using filesort

-- 优化：建 (status, amount) 联合索引，让排序走索引
ALTER TABLE orders ADD INDEX idx_status_amount (status, amount);
EXPLAIN SELECT id, amount FROM orders WHERE status = 'paid' ORDER BY amount DESC LIMIT 10;
-- Extra 里的 Using filesort 消失，type 变成 range
SET profiling = 1;
SELECT id, amount FROM orders WHERE status = 'paid' ORDER BY amount DESC LIMIT 10;
SHOW PROFILES;
ALTER TABLE orders DROP INDEX idx_status_amount;   -- 清理

-- ============================================================
-- 慢 SQL ④ 索引下推没利用：复合条件
-- ============================================================
-- 优化器选了 idx_orders_status_created（status 只有 4 个值，要扫 5 万行）
SET profiling = 1;
SELECT COUNT(*) FROM orders WHERE status = 'paid' AND user_id = 42;
SHOW PROFILES;
-- 先看清优化器到底选了哪个索引：
EXPLAIN SELECT COUNT(*) FROM orders WHERE status = 'paid' AND user_id = 42;
-- 如果 key = idx_orders_status_created，rows 会是 4 万上下（等于扫描量）

-- 但 user_id=42 只有 29 单，用 idx_orders_user 明显更合适
SET profiling = 1;
SELECT COUNT(*) FROM orders FORCE INDEX (idx_orders_user) WHERE status = 'paid' AND user_id = 42;
SHOW PROFILES;
EXPLAIN SELECT COUNT(*) FROM orders FORCE INDEX (idx_orders_user) WHERE status='paid' AND user_id=42;
-- 这时 key = idx_orders_user，rows 只有 29
-- ★ 用 rows 判断，别用耗时判断（耗时会被缓存和机器性能干扰）

-- 更好的办法不是 FORCE INDEX，而是换个联合索引顺序
-- 详见第 17 篇

-- ============================================================
-- 慢 SQL ⑤ COUNT(*) 太慢 / OR 拖后腿
-- ============================================================
-- OR 的问题：amount 没索引，整个查询放弃索引
EXPLAIN SELECT * FROM orders WHERE user_id = 42 OR amount > 5000;

-- 改写 1：UNION ALL（两个分支各走各的索引）
EXPLAIN SELECT * FROM orders WHERE user_id = 42
UNION ALL
SELECT * FROM orders WHERE amount > 5000;

-- 改写 2：给 amount 也建索引，让优化器自己选
-- （本数据集 20 万行，UNION ALL 反而可能更慢，因为返回行数多。
--   这也是一个重要结论：优化要看真实数据量，不能想当然）

-- COUNT(*) 的优化思路
SET profiling = 1;
SELECT COUNT(*) FROM orders;          -- InnoDB 会扫一遍
SHOW PROFILES;
-- 生产上的做法：
--   1. 估算值：EXPLAIN SELECT * FROM orders;  看 rows
--   2. 汇总表：单独维护一张 cnt 表，插入订单时 +1
--   3. 缓存：数据不动就不查

-- ============================================================
-- ★ 别过度优化：本仓库大部分查询都在 20 毫秒以内
-- ============================================================
SET profiling = 1;
SELECT COUNT(*) FROM users;
SELECT COUNT(*) FROM scores;
SELECT name, city FROM students WHERE city = '北京';
SHOW PROFILES;
-- 结论：80% 的「慢」是网络和客户端的问题，不是数据库的问题
