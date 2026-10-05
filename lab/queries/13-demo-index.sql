-- =============================================================================
-- 13-demo-index.sql · 第 13 篇配套实验
--
-- 对应 docs/13-index-what.md 的 6 个小节，可以按小节分段跑。
-- 每个实验都会自己清理现场，跑完不影响后面的文章。
--
-- ⚠ 如果第 4 节报「Duplicate key name idx_user」，说明你上次没跑完，
--   执行 lab/reset.ps1 重置环境即可。
--
-- 数据是固定的（造数据用 CRC32，不用 RAND），你的 rows 一定和这里一样；
-- Duration 会随机器变化，不一样是正常的。
-- =============================================================================

SET NAMES utf8mb4;
SET SESSION cte_max_recursion_depth = 100000;

USE easy_mysql;

-- =============================================================================
-- 第 1 节：先做实验，别听我说
-- =============================================================================
SET profiling = 1;

SELECT COUNT(*) FROM orders_slow WHERE user_id = 42;   -- 无索引
SELECT COUNT(*) FROM orders_slow WHERE user_id = 42;   -- 跑两遍，避免首次预热干扰
SELECT COUNT(*) FROM orders      WHERE user_id = 42;   -- 有索引
SELECT COUNT(*) FROM orders      WHERE user_id = 42;

SHOW PROFILES;
-- 本机参考值：orders_slow 0.021~0.026 秒，orders 0.0002~0.0006 秒
-- ★ 你的耗时一定和这里不一样（硬件差异），那不重要。
--   重要且稳定的是下一步 EXPLAIN 里的 rows。

-- =============================================================================
-- 第 2 节：少做了什么？问数据库自己
-- =============================================================================
EXPLAIN SELECT COUNT(*) FROM orders_slow WHERE user_id = 42;
-- type = ALL    ← 全表挨个看
-- key  = NULL   ← 没有索引可用
-- rows = 199430 ← 要读 19 万行

EXPLAIN SELECT COUNT(*) FROM orders WHERE user_id = 42;
-- type = ref                     ← 查目录
-- key  = idx_orders_user
-- rows = 29                      ← 只要读 29 行

-- =============================================================================
-- 第 3 节：目录为什么能少读 —— B+ 树"层层折半"模拟
--   假设：每个索引节点放 1000 个键，每个叶子节点放 100 行数据
-- =============================================================================
WITH RECURSIVE split AS (
    SELECT 0 AS level, 200000 AS nodes
    UNION ALL
    SELECT level + 1, CEIL(nodes / 100) FROM split WHERE nodes > 1
)
SELECT level AS layer, nodes AS node_count FROM split;
-- 20 万行 → 2000 → 20 → 1，共 3 层索引
-- 每层是上一层的百分之一，所以再大的表也只要查 3~4 层

-- =============================================================================
-- 第 4 节：回表 与 覆盖索引
--   Extra 是空的       → 需要回表（拿主键值回聚簇索引取整行）
--   Extra 有 Using index → 覆盖索引，索引本身就够，不用回表
-- =============================================================================
EXPLAIN SELECT * FROM orders WHERE user_id = 42;              -- Extra 空，回表
EXPLAIN SELECT id, user_id FROM orders WHERE user_id = 42;     -- Using index，不回表

-- 二级索引里到底存了什么？看它认为有多少个不同的值（基数）
-- 注意：CARDINALITY 是抽样估算值，不是精确值（status 实际 4 个值，这里显示 3）
-- 联合索引 idx_orders_status_created 会占两行，因为建在两个字段上（第 17 篇）
SELECT INDEX_NAME, COLUMN_NAME, CARDINALITY
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = 'easy_mysql' AND TABLE_NAME = 'orders';
-- user_id 4295 → 撑得开，索引有用
-- status    3   → 撑不开，索引没用（status 只有 4 种状态，等于放行 1/4 的数据）

-- =============================================================================
-- 第 5 节：亲手建一个索引
-- =============================================================================
ALTER TABLE orders_slow ADD INDEX idx_user (user_id);

EXPLAIN SELECT COUNT(*) FROM orders_slow WHERE user_id = 42;
-- ALL → ref，199430 → 29

SET profiling = 1;
SELECT COUNT(*) FROM orders_slow WHERE user_id = 42;
SELECT COUNT(*) FROM orders_slow WHERE user_id = 42;
SHOW PROFILES;
-- 和 orders 一样快了（0.0001 秒左右）

ALTER TABLE orders_slow DROP INDEX idx_user;   -- 还原成"无索引"，第 14 篇要用

-- =============================================================================
-- 第 6 节：代价 —— 空间和写入都要钱
-- =============================================================================

-- 【空间】同样 20 万行，唯一差别是有没有索引
SELECT TABLE_NAME,
       ROUND(DATA_LENGTH/1024)  AS data_kb,
       ROUND(INDEX_LENGTH/1024) AS index_kb,
       ROUND((DATA_LENGTH+INDEX_LENGTH)/1024) AS total_kb
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'easy_mysql' AND TABLE_NAME IN ('orders','orders_slow');
-- orders 的索引(14336KB)比数据本身(12816KB)还大

-- 【写入】同一张表、同一批数据，唯一差别是有没有索引
-- 先把源数据准备好，避免"造数据的开销"混进结果
DROP TABLE IF EXISTS tmp_batch;
CREATE TABLE tmp_batch AS
WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM seq WHERE n < 2000)
SELECT 7 AS user_id, 1 AS product_id, 1 AS quantity, 10.00 AS amount,
       'created' AS status, NOW() AS created_at, NOW() AS updated_at
FROM seq;

SET profiling = 1;
INSERT INTO orders_slow (user_id, product_id, quantity, amount, status, created_at, updated_at)
SELECT * FROM tmp_batch;
INSERT INTO orders_slow (user_id, product_id, quantity, amount, status, created_at, updated_at)
SELECT * FROM tmp_batch;                                 -- 跑两遍，看稳定的那个
SHOW PROFILES;                                           -- 本机约 0.054 秒
DELETE FROM orders_slow WHERE id > 200000;

ALTER TABLE orders_slow ADD INDEX idx_user (user_id);
SET profiling = 1;
INSERT INTO orders_slow (user_id, product_id, quantity, amount, status, created_at, updated_at)
SELECT * FROM tmp_batch;
INSERT INTO orders_slow (user_id, product_id, quantity, amount, status, created_at, updated_at)
SELECT * FROM tmp_batch;
SHOW PROFILES;                                           -- 本机约 0.065 秒，慢 15%~20%
DELETE FROM orders_slow WHERE id > 200000;

-- 清理
ALTER TABLE orders_slow DROP INDEX idx_user;
DROP TABLE tmp_batch;

-- 【加索引本身也很贵】20 万行的表加一个索引要 1 秒多。
-- 5 亿行的生产表可能要几个小时，所以加索引要挑时间。
-- 用下面这行自己感受一下（本机约 1.1 秒）：
-- ALTER TABLE orders_slow ADD INDEX idx_user (user_id);
-- ALTER TABLE orders_slow DROP INDEX idx_user;

-- =============================================================================
-- 第 7 节：预告 —— 索引也不是万能的
--   本数据集故意让 20% 的订单集中在 3 个"超级大客户"上
-- =============================================================================
SELECT user_id, COUNT(*) AS order_cnt
FROM orders WHERE user_id IN (1, 2, 3, 42)
GROUP BY user_id ORDER BY user_id;
-- user_id = 1  有 13364 笔订单  → 用索引定位到 13364 个主键，然后回表 13364 次
-- user_id = 42 只有 29 笔      → 回表 29 次，索引帮了大忙
-- 同一个索引，一个天堂一个地狱。这就是"区分度"，第 14 篇讲这个。

-- =============================================================================
-- 收尾自检：确认实验没有留下痕迹
-- =============================================================================
SELECT 'orders_slow_indexes' AS check_item, COUNT(*) AS should_be_1
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA='easy_mysql' AND TABLE_NAME='orders_slow' AND INDEX_NAME='PRIMARY'
UNION ALL
SELECT 'orders_rows', COUNT(*) FROM orders
UNION ALL
SELECT 'orders_slow_rows', COUNT(*) FROM orders_slow
UNION ALL
SELECT 'tmp_batch_dropped', IF(COUNT(*)=0, 1, 0)
FROM information_schema.TABLES WHERE TABLE_SCHEMA='easy_mysql' AND TABLE_NAME='tmp_batch';
-- 期望：1 / 200000 / 200000 / 1
