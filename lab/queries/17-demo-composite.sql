-- 17-demo-composite.sql · 第 17 篇配套实验：最左前缀一张表看懂

SET NAMES utf8mb4;


USE easy_mysql;

-- 本表已有索引：idx_orders_status_created (status, created_at)
SHOW INDEX FROM orders;

-- ============================================================
-- 联合索引的本质：按 (status, created_at) 组合排序
-- 先按 status 排；status 相同时，再按 created_at 排
-- ============================================================

-- 【能用到索引的第一个列】type=ref, key=idx_orders_status_created
EXPLAIN SELECT * FROM orders WHERE status = 'paid' LIMIT 10;
-- key_len = 42（status ENUM 占的字节数）

-- 【两个都能用】key_len 会变长
EXPLAIN SELECT * FROM orders WHERE status = 'paid' AND created_at >= '2024-07-01' LIMIT 10;
-- key_len ≈ 61

-- 【★ 用不上！只有第二列，没有第一列】
EXPLAIN SELECT * FROM orders WHERE created_at >= '2024-07-01' LIMIT 10;
-- key = NULL, type = ALL, rows ≈ 200000
-- 这就是「最左前缀」规则

-- 【能用到】IN 相当于多个等值条件
EXPLAIN SELECT * FROM orders WHERE status IN ('paid','shipped') LIMIT 10;

-- 【★ 范围之后，后面的列失效】
EXPLAIN SELECT * FROM orders
WHERE status = 'paid' AND created_at >= '2024-07-01' AND user_id = 42;
-- key_len 停在 created_at，user_id 只能「过滤」不能「定位」

-- ============================================================
-- 索引还能用来排序
-- ============================================================
-- 反例：排序字段不在索引里 → Using filesort
EXPLAIN SELECT * FROM orders WHERE status = 'paid' ORDER BY amount DESC LIMIT 10;

-- 正解：排序列接在等值条件后面
EXPLAIN SELECT * FROM orders WHERE status = 'paid' ORDER BY created_at DESC LIMIT 10;
-- Using filesort 消失！

-- 如果是范围查询，created_at 就不能用来排序了
EXPLAIN SELECT * FROM orders WHERE status = 'paid' AND created_at >= '2024-01-01'
ORDER BY created_at LIMIT 10;

-- ============================================================
-- ★★ 实战：设计一个同时支持两种查询的索引
-- 需求 A：按状态查时间范围
-- 需求 B：按用户查时间范围
-- ============================================================
-- 现在的索引只支持 A
-- 建一个 (user_id, status, created_at) 试试
ALTER TABLE orders ADD INDEX idx_user_status_created (user_id, status, created_at);

EXPLAIN SELECT * FROM orders WHERE user_id = 42 AND status = 'paid'
AND created_at >= '2024-07-01';
-- 走新索引，rows 很小

EXPLAIN SELECT * FROM orders WHERE user_id = 42 AND created_at >= '2024-07-01';
-- user_id 等值后，created_at 仍然可以定位（status 缺失不影响，因为中间不能跳）

EXPLAIN SELECT * FROM orders WHERE user_id = 42 ORDER BY status, created_at LIMIT 10;
-- 排序也走索引

-- 关键：把等值条件的列放前面，范围条件的列放最后
-- 顺序：等值 → 等值 → 范围 → 排序列
-- 绝不要把范围列放在等值列前面

ALTER TABLE orders DROP INDEX idx_user_status_created;   -- 清理

-- ============================================================
-- 顺序很重要：同样两列，反过来差别巨大
-- ============================================================
ALTER TABLE orders ADD INDEX idx_ca (created_at, status);
EXPLAIN SELECT * FROM orders WHERE status = 'paid' AND created_at >= '2024-07-01' LIMIT 10;
-- 这里 created_at 是范围列，status 跟在后面 → status 用不上，key_len 较短
ALTER TABLE orders DROP INDEX idx_ca;

-- ============================================================
-- ★ 书签式分页为什么快（回顾第 16 篇）
-- ============================================================
SET profiling = 1;
SELECT * FROM orders ORDER BY id LIMIT 100000, 10;    -- 慢：要丢掉前 10 万行
SELECT * FROM orders WHERE id > 199990 ORDER BY id LIMIT 10;  -- 快：直接定位
SHOW PROFILES;
