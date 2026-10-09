-- ============================================================
-- 17-demo-composite.sql · 第 17 篇配套实验：联合索引与最左前缀
-- 对应文档: docs/17-composite-index.md
-- 每段前面有一行 `实验` 标签，和文章的小节一一对应（输出均为真实运行结果）
-- 特性：只用临时索引/临时表，跑完自清理，可重复执行
-- 基线表行数跑完不变（orders=200000，orders_slow=200000 且只留 PRIMARY）
-- ============================================================

SET NAMES utf8mb4;
USE easy_mysql;

-- ------------------------------------------------------------
-- §2 · 联合索引的本质：两列当成一个「组合键」排序
-- ------------------------------------------------------------
-- b(c1, c2, c3) 的排序规则：先按 c1 分组，组内按 c2 排，再按 c3 排。
SELECT '--- §2 组合键排序：索引里真实存放的顺序 ---' AS 实验;
CREATE TABLE idx_demo (
    c1 VARCHAR(10),
    c2 VARCHAR(10),
    c3 VARCHAR(10)
) ENGINE=InnoDB;
INSERT INTO idx_demo VALUES
('a','y','z'),('a','y','a'),('a','x','m'),
('b','y','q'),('b','x','c'),('b','x','a');
CREATE INDEX b_idx ON idx_demo (c1, c2, c3);
SELECT c1, c2, c3 FROM idx_demo ORDER BY c1, c2, c3;
DROP TABLE idx_demo;

-- ------------------------------------------------------------
-- §4-前置 · 排序：先看 orders_slow 没有二级索引时的样子
-- （orders 和 orders_slow 是双胞胎，唯一区别就是这张没有二级索引）
-- ------------------------------------------------------------
SELECT '--- §4-前置 没索引：ORDER BY 只能自己排（Using filesort）---' AS 实验;
EXPLAIN SELECT id FROM orders_slow WHERE status = 'paid' ORDER BY created_at LIMIT 10;

-- ------------------------------------------------------------
-- §3 · 最左前缀实验：建一个 (status, created_at, user_id) 三列索引
-- orders_slow 上没有别的二级索引，优化器不会被"抢走"，实验最干净
-- ------------------------------------------------------------
ALTER TABLE orders_slow ADD INDEX idx_status_created_user (status, created_at, user_id);

SELECT '--- §3-① 三列全用上：status 等值 + created_at 范围 + user_id 等值（期望 key_len=14）---' AS 实验;
EXPLAIN SELECT id FROM orders_slow
WHERE status = 'paid' AND created_at >= '2024-01-01' AND user_id = 42;

SELECT '--- §3-② 用上第 1、2 列：status 等值 + created_at 范围（期望 key_len=6）---' AS 实验;
EXPLAIN SELECT id FROM orders_slow
WHERE status = 'paid' AND created_at >= '2024-01-01';

SELECT '--- §3-③ 只用第 1 列：status 等值（期望 key_len=1）---' AS 实验;
EXPLAIN SELECT id FROM orders_slow WHERE status = 'paid';

SELECT '--- §3-④ 跳过第 1 列直接查第 3 列 user_id：没法「定位」，只能整个索引从头扫一遍（type=index）---' AS 实验;
EXPLAIN SELECT id FROM orders_slow WHERE user_id = 42;

SELECT '--- §3-⑤ 跳过第 1 列直接查第 2 列：MySQL 8 用 skip scan 兜底，但估算仍要扫几万行 ---' AS 实验;
EXPLAIN SELECT id FROM orders_slow WHERE created_at >= '2024-01-01';

SELECT '--- §3-⑥ status 用 IN（本质仍是等值）+ created_at 范围收窄：两列都用上（key_len=6）---' AS 实验;
EXPLAIN SELECT id FROM orders_slow
WHERE status IN ('paid', 'shipped') AND created_at >= '2024-11-01';

-- ------------------------------------------------------------
-- §5 · 范围截断：范围之后的列只能过滤，不能再定位
-- ------------------------------------------------------------
SELECT '--- §5-① 第 3 列 user_id 是等值：range 起点用到 3 列（key_len=14），但 rows 仍是 created_at 范围的 15256 ---' AS 实验;
EXPLAIN SELECT id FROM orders_slow
WHERE status = 'paid' AND created_at >= '2024-11-01' AND user_id = 42;

SELECT '--- §5-② 第 3 列变范围：key_len、rows 都没变，user_id 只写在 filtered 列里（事后过滤）---' AS 实验;
EXPLAIN SELECT id FROM orders_slow
WHERE status = 'paid' AND created_at >= '2024-11-01' AND user_id BETWEEN 40 AND 60;

SELECT '--- §5-② 真跑一遍（EXPLAIN ANALYZE）：实际扫描量 ≈ created_at 范围的行数 ---' AS 实验;
EXPLAIN ANALYZE SELECT id FROM orders_slow
WHERE status = 'paid' AND created_at >= '2024-11-01' AND user_id BETWEEN 40 AND 60\G

SELECT '--- §5-③ 同样的条件换成 orders（优化器选了 user_id 索引）：范围从 user_id 起步 ---' AS 实验;
EXPLAIN SELECT id FROM orders
WHERE status = 'paid' AND created_at >= '2024-11-01' AND user_id BETWEEN 40 AND 60;

SELECT '--- §5-③ 真跑一遍（EXPLAIN ANALYZE）：实际扫描量小两个数量级 ---' AS 实验;
EXPLAIN ANALYZE SELECT id FROM orders
WHERE status = 'paid' AND created_at >= '2024-11-01' AND user_id BETWEEN 40 AND 60\G

-- ------------------------------------------------------------
-- §4 · 排序：索引有序 vs 无序（Using filesort）
-- ------------------------------------------------------------
SELECT '--- §4-① 排序列在索引里：Using filesort 消失 ---' AS 实验;
EXPLAIN SELECT id FROM orders_slow WHERE status = 'paid' ORDER BY created_at LIMIT 10;

SELECT '--- §4-② 换个排序列 amount（不在索引里）：Using filesort 回来了 ---' AS 实验;
EXPLAIN SELECT id, amount FROM orders_slow WHERE status = 'paid' ORDER BY amount DESC LIMIT 10;

SELECT '--- §4-③ 范围之后的列既不能定位，也不能排序：ORDER BY user_id 又要 filesort ---' AS 实验;
EXPLAIN SELECT id FROM orders_slow
WHERE status = 'paid' AND created_at >= '2024-12-01' ORDER BY user_id LIMIT 10;

SELECT '--- §4-④ MySQL 8 支持索引反向扫：ORDER BY created_at DESC 不用 filesort ---' AS 实验;
EXPLAIN SELECT id FROM orders_slow WHERE status = 'paid' ORDER BY created_at DESC LIMIT 10;

-- ------------------------------------------------------------
-- §4-ICP · 索引下推（Index Condition Pushdown）一句话版
-- ------------------------------------------------------------
SELECT '--- §ICP 索引下推：Extra 的 Using index condition = 条件先在索引里筛一遍再回表 ---' AS 实验;
EXPLAIN SELECT * FROM orders WHERE status = 'paid' AND created_at >= '2024-12-15';

ALTER TABLE orders_slow DROP INDEX idx_status_created_user;

-- ------------------------------------------------------------
-- §6 · 优化器选错索引：FORCE INDEX 用对了才救场（orders 上实测）
-- ------------------------------------------------------------
SELECT '--- §6-① 默认计划：走 status 索引，扫 95652 行 + filesort ---' AS 实验;
EXPLAIN SELECT id, user_id FROM orders
WHERE status = 'paid' AND user_id BETWEEN 1 AND 100 ORDER BY user_id;

SELECT '--- §6-② 强制走 user_id 索引：不用 filesort（注意 rows 变成 1 —— 强制后的估算已失真，看下面 ANALYZE）---' AS 实验;
EXPLAIN SELECT id, user_id FROM orders FORCE INDEX (idx_orders_user)
WHERE status = 'paid' AND user_id BETWEEN 1 AND 100 ORDER BY user_id;

SELECT '--- §6-① 真跑一遍（EXPLAIN ANALYZE）---' AS 实验;
EXPLAIN ANALYZE SELECT id, user_id FROM orders
WHERE status = 'paid' AND user_id BETWEEN 1 AND 100 ORDER BY user_id\G

SELECT '--- §6-② 真跑一遍（EXPLAIN ANALYZE）---' AS 实验;
EXPLAIN ANALYZE SELECT id, user_id FROM orders FORCE INDEX (idx_orders_user)
WHERE status = 'paid' AND user_id BETWEEN 1 AND 100 ORDER BY user_id\G

-- ------------------------------------------------------------
-- §7 · 别滥用 FORCE INDEX：用错了比不用还惨
-- ------------------------------------------------------------
SELECT '--- §7-① 默认：created_at 范围先筛掉大部分行（key_len=6, rows=2181）---' AS 实验;
EXPLAIN SELECT id FROM orders
WHERE status = 'paid' AND created_at >= '2024-12-15' AND user_id BETWEEN 1 AND 100;

SELECT '--- §7-② 强制 user_id 索引：估算 rows=1（严重低估），真实扫描量看下面 ANALYZE ---' AS 实验;
EXPLAIN SELECT id FROM orders FORCE INDEX (idx_orders_user)
WHERE status = 'paid' AND created_at >= '2024-12-15' AND user_id BETWEEN 1 AND 100;

SELECT '--- §7-① 真跑一遍（EXPLAIN ANALYZE）---' AS 实验;
EXPLAIN ANALYZE SELECT id FROM orders
WHERE status = 'paid' AND created_at >= '2024-12-15' AND user_id BETWEEN 1 AND 100\G

SELECT '--- §7-② 真跑一遍（EXPLAIN ANALYZE）---' AS 实验;
EXPLAIN ANALYZE SELECT id FROM orders FORCE INDEX (idx_orders_user)
WHERE status = 'paid' AND created_at >= '2024-12-15' AND user_id BETWEEN 1 AND 100\G

-- ------------------------------------------------------------
-- §8 · 动手练参考答案：为三类查询设计索引
--   A. WHERE status=?                        → (status)
--   B. WHERE status=? ORDER BY created_at    → (status, created_at)
--   C. WHERE user_id=? ORDER BY created_at   → (user_id, created_at)
-- ------------------------------------------------------------
SELECT '--- §8-① 建 (user_id, created_at) 后：等值 + 排序都命中，无 filesort ---' AS 实验;
ALTER TABLE orders ADD INDEX idx_user_created (user_id, created_at);
EXPLAIN SELECT id FROM orders WHERE user_id = 42 ORDER BY created_at LIMIT 10;

SELECT '--- §8-② 对照：强制单列索引 idx_orders_user：ORDER BY 立刻回到 filesort ---' AS 实验;
EXPLAIN SELECT id FROM orders FORCE INDEX (idx_orders_user) WHERE user_id = 42 ORDER BY created_at LIMIT 10;

ALTER TABLE orders DROP INDEX idx_user_created;

-- ------------------------------------------------------------
-- 收尾自检：orders / orders_slow 必须回到基线
-- ------------------------------------------------------------
SELECT COUNT(*) AS orders行数 FROM orders;
SELECT COUNT(*) AS orders_slow行数 FROM orders_slow;
SHOW INDEX FROM orders;
SHOW INDEX FROM orders_slow;
