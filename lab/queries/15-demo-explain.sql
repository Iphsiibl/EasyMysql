-- 15-demo-explain.sql · 第 15 篇配套实验（EXPLAIN 逐列拆解）

SET NAMES utf8mb4;


USE easy_mysql;

-- ============================================================
-- 1. EXPLAIN 怎么用：加在 SELECT 前面就行
-- ============================================================
EXPLAIN SELECT * FROM orders WHERE user_id = 42;
EXPLAIN SELECT * FROM orders WHERE user_id = 42\G   -- \G 竖排显示，列多时用

-- ============================================================
-- 2. 12 列逐个是什么意思
-- ============================================================
EXPLAIN SELECT o.id, o.amount, i.product_name
FROM orders o JOIN order_items i ON i.order_id = o.id
WHERE o.status = 'paid' AND o.created_at >= '2024-07-01'
ORDER BY o.amount DESC LIMIT 10;

-- 列的含义速查：
--   id            查询序号（子查询越多越大）
--   select_type   SIMPLE / PRIMARY / SUBQUERY / DERIVED
--   table         当前这张表
--   type          ★ 最重要，见下表
--   possible_keys 优化器考虑过的索引
--   key           实际选用的索引，NULL = 没用到
--   key_len       用了索引的前几个字节
--   ref           与索引比较的是常量还是别的表
--   rows          ★ 估算要读多少行，第二重要
--   filtered      按 WHERE 过滤后剩余百分比
--   Extra         ★ 额外信息，关键词最有价值

-- ============================================================
-- 3. ★ type 列：从好到坏的优先级（建议截图保存）
-- ============================================================
-- const：主键等值，最快
EXPLAIN SELECT * FROM orders WHERE id = 100;
-- type = const, rows = 1

-- eq_ref：JOIN 时被驱动表的唯一索引
EXPLAIN SELECT * FROM scores sc JOIN students s ON s.id = sc.student_id WHERE sc.id = 1;

-- ref：非唯一索引等值，普通业务里最常见
EXPLAIN SELECT * FROM orders WHERE user_id = 42;
-- type = ref

-- range：索引范围
EXPLAIN SELECT * FROM orders WHERE created_at >= '2024-07-01' AND created_at < '2024-08-01';

-- index：扫整个索引（比全表快一点，但本质还是全扫）
EXPLAIN SELECT id FROM orders;

-- ALL：全表扫描，最差
EXPLAIN SELECT * FROM orders WHERE amount > 5000;
-- type = ALL，因为 amount 没索引

-- ============================================================
-- 4. ★ Extra 列里最该警惕的三个词
-- ============================================================
-- Using where：Server 层还要再过滤一次，正常现象，不用紧张
EXPLAIN SELECT * FROM orders WHERE status = 'paid' AND amount > 100;

-- Using filesort：★ 无法利用索引顺序，需要额外排序（不是磁盘排序！）
EXPLAIN SELECT * FROM orders WHERE status = 'paid' ORDER BY amount DESC LIMIT 10;
-- 解法见第 17 篇：建 (status, amount) 联合索引

-- Using temporary：★ 用了临时表，常见于 GROUP BY / DISTINCT
EXPLAIN SELECT city, COUNT(*) FROM students GROUP BY city HAVING COUNT(*) > 60;

-- Using index：覆盖索引，读索引就够了，不用回表 —— 这是好事
EXPLAIN SELECT id, user_id FROM orders WHERE user_id = 42;

-- Using index condition：索引条件下推，优化器帮你在索引层面就过滤
EXPLAIN SELECT * FROM orders WHERE user_id = 42 AND status = 'paid';

-- ============================================================
-- 5. EXPLAIN FORMAT=JSON：看更细的估算过程
-- ============================================================
EXPLAIN FORMAT=JSON SELECT * FROM orders WHERE user_id = 42\G

-- ============================================================
-- 6. ★ EXPLAIN ANALYZE：真的跑一遍，给出真实耗时
--    需要 MySQL 8.0.18 以上
-- ============================================================
EXPLAIN ANALYZE SELECT * FROM orders WHERE user_id = 42;
EXPLAIN ANALYZE SELECT * FROM orders WHERE status = 'paid' AND created_at >= '2024-07-01'
ORDER BY created_at LIMIT 10;
-- 看 output 里的 actual time= 和 rows=，和 EXPLAIN 的估算对比
-- 估算和实际差很多 = 统计信息过期，需要 ANALYZE TABLE

ANALYZE TABLE orders;

-- ============================================================
-- 7. 慢查询日志：本仓库已开启（long_query_time = 0.2 秒）
-- ============================================================
SELECT @@slow_query_log AS 慢日志开关, @@long_query_time AS 阈值秒;
-- 故意造一条慢查询
SELECT SLEEP(1);
-- 然后到容器里看日志：
--   docker exec easy-mysql cat /var/lib/mysql/$(hostname).log
--   docker exec easy-mysql ls /var/lib/mysql/
