-- 14-demo-when-to-index.sql · 第 14 篇配套实验

SET NAMES utf8mb4;


USE easy_mysql;

-- ============================================================
-- 1. 区分度：算出来是几，就知道该不该建索引
-- ============================================================
-- 接近 1 = 值很多 = 好索引；接近 0 = 值很少 = 坏索引
SELECT COUNT(DISTINCT user_id)  / COUNT(*) AS user_id_区分度 FROM orders;
SELECT COUNT(DISTINCT product_id)/ COUNT(*) AS product_id_区分度 FROM orders;
SELECT COUNT(DISTINCT status)   / COUNT(*) AS status_区分度    FROM orders;  -- 只有 0.0002

-- 一眼看出哪些字段值得建索引
SELECT 'user_id'    AS 字段, COUNT(DISTINCT user_id)    AS 不同值个数 FROM orders
UNION ALL SELECT 'product_id',    COUNT(DISTINCT product_id)    FROM orders
UNION ALL SELECT 'status',        COUNT(DISTINCT status)        FROM orders
UNION ALL SELECT 'created_at',    COUNT(DISTINCT created_at)    FROM orders
ORDER BY 不同值个数 DESC;

-- ============================================================
-- 2. ★ 低区分度字段建了索引，优化器会直接不用它
-- ============================================================
-- status 只有 4 个值。用它查询会命中 25% 的行，
-- 优化器认为「还不如全表扫描」，于是 key = NULL
EXPLAIN SELECT * FROM orders WHERE status = 'paid';
-- type = ALL, key = NULL, rows ≈ 50000

-- 强制让它用索引看看
EXPLAIN SELECT * FROM orders FORCE INDEX (idx_orders_status_created) WHERE status = 'paid';
-- 用上了，但扫的行数反而更多，没有意义

-- 再看一个反直觉的：user_id=42（只有 29 单）
EXPLAIN SELECT * FROM orders WHERE user_id = 42;
-- type = ref, key = idx_orders_user, rows = 29  ← 这次优化器很聪明

-- ============================================================
-- 3. 索引失效的 6 种写法（每条都跑一次 EXPLAIN 对照）
-- ============================================================

-- 失效①：在索引列上套函数
EXPLAIN SELECT * FROM orders WHERE YEAR(created_at) = 2024;
-- 正确写法：改成范围条件，走索引
EXPLAIN SELECT * FROM orders WHERE created_at >= '2024-01-01' AND created_at < '2025-01-01';

-- 失效②：隐式类型转换（user_id 是 BIGINT，用字符串比）
EXPLAIN SELECT * FROM orders WHERE user_id = '42';
-- MySQL 会把 '42' 转成 42，索引还能用
-- 但反过来在 string 列上用数字比较就会全表扫描：
-- EXPLAIN SELECT * FROM students WHERE id = '1';
--   id 是 int，'1' 会被转成 1，索引仍可用（MySQL 8 优化过）
-- 真正危险的是 CHAR 列和数字比较：
-- EXPLAIN SELECT * FROM orders WHERE status = 1;
--   status 是 ENUM，字符串 'paid' 和数字 1 比较时，索引会失效

-- 失效③：前导模糊
EXPLAIN SELECT * FROM students WHERE name LIKE '%伟';
-- 改成后缀模糊就能用（但本表按 name 没索引，先看语法）
-- EXPLAIN SELECT * FROM students WHERE name LIKE '王%';

-- 失效④：OR 连接了没有索引的列
EXPLAIN SELECT * FROM orders WHERE user_id = 42 OR amount > 5000;
-- amount 没索引 → 整条 SQL 放弃索引
-- 改写方案：UNION ALL
EXPLAIN SELECT * FROM orders WHERE user_id = 42
UNION ALL
SELECT * FROM orders WHERE amount > 5000;

-- 失效⑤：!= 和 NOT IN
EXPLAIN SELECT * FROM orders WHERE user_id != 42 LIMIT 10;
-- 命中的行太多，优化器判定不如全表扫描
EXPLAIN SELECT * FROM orders WHERE user_id NOT IN (42, 43) LIMIT 10;

-- 失效⑥：查询要取的列没被索引覆盖（触发大量回表）
EXPLAIN SELECT * FROM orders WHERE user_id = 42;
EXPLAIN SELECT id, user_id FROM orders WHERE user_id = 42;
-- 第二条的 Extra 出现 Using index = 覆盖索引，不用回表

-- ============================================================
-- 4. 索引不是越多越好：给 orders_slow 加满索引试试
-- ============================================================
SELECT COUNT(*) AS 加索引前_表体积_KB
FROM information_schema.TABLES
WHERE TABLE_SCHEMA='easy_mysql' AND TABLE_NAME='orders_slow';

ALTER TABLE orders_slow
  ADD INDEX idx_user (user_id),
  ADD INDEX idx_amount (amount),
  ADD INDEX idx_status (status);

SELECT ROUND((DATA_LENGTH+INDEX_LENGTH)/1024) AS 加索引后_表体积_KB
FROM information_schema.TABLES
WHERE TABLE_SCHEMA='easy_mysql' AND TABLE_NAME='orders_slow';
-- 对比 orders（有 2 个索引）的体积，理解「索引要花钱」

-- 清理
ALTER TABLE orders_slow
  DROP INDEX idx_user, DROP INDEX idx_amount, DROP INDEX idx_status;
