-- 15-demo-explain.sql · 第 15 篇配套实验：读懂 EXPLAIN 执行计划
-- 用法：docker cp 本文件进容器后 source，输出即文章里引用的输出
-- 本文件不会改动任何基线数据；唯一的“破坏性”动作是把 order_items 的统计行数改成 0
-- 来模拟统计信息过期，段落结束立刻 ANALYZE TABLE 恢复（数据一行都没动过）

SET NAMES utf8mb4;

USE easy_mysql;

-- information_schema 默认缓存统计 24 小时，先关掉缓存拿到最新值
SET information_schema_stats_expiry = 0;

-- ============================================================
-- 1. ★ EXPLAIN 怎么读：12 列逐列拆解
-- ============================================================
-- 这条查询命中 idx_orders_user，12 列全部有值，是最好的解剖标本
EXPLAIN SELECT * FROM orders WHERE user_id = 42;

-- 12 列各自管什么（EXPLAIN 输出的列序）
SELECT 1 AS 序号, 'id' AS 列名, '相同 id 的行按顺序执行：1 是最外层，2 是子查询' AS 管什么
UNION ALL SELECT 2, 'select_type', 'SIMPLE / PRIMARY / SUBQUERY，查询是什么类型'
UNION ALL SELECT 3, 'table', '这一行在读哪张表（含别名）'
UNION ALL SELECT 4, 'partitions', '分区号，本库没分区所以全是 NULL'
UNION ALL SELECT 5, 'type', '访问方式，本篇第 2 节的八级表，最重要的列'
UNION ALL SELECT 6, 'possible_keys', '优化器考虑过的索引，NULL 表示没有可用索引'
UNION ALL SELECT 7, 'key', '实际选中的索引，NULL 就是没走索引'
UNION ALL SELECT 8, 'key_len', '用了联合索引的前几个字节（第 17 篇靠它判断截断）'
UNION ALL SELECT 9, 'ref', '和谁比：const 表示常量，表名.列 表示拿前一张表的列来查'
UNION ALL SELECT 10, 'rows', '预估要读多少行，是乘法的基数不是精确值'
UNION ALL SELECT 11, 'filtered', '读出来的行里预计有多少百分比能通过 WHERE'
UNION ALL SELECT 12, 'Extra', '额外提示：回表、排序、临时表都写在这里';

-- ============================================================
-- 2. ★ type 八级：从最好到最差
-- ============================================================

-- (a) const：主键等值，最多命中 1 行
EXPLAIN SELECT * FROM orders WHERE id = 100;

-- (b) eq_ref：join 时拿前一张表的列去查主键，每行最多配 1 行
EXPLAIN SELECT o.id, u.username FROM orders o JOIN users u ON u.id = o.user_id WHERE o.id BETWEEN 1 AND 100;

-- (c) ref：非唯一索引等值，这里预估 29 行
EXPLAIN SELECT * FROM orders WHERE user_id = 42;

-- (d) range：索引范围扫描，预估 357 行
EXPLAIN SELECT * FROM orders WHERE user_id BETWEEN 40 AND 50;

-- (e) index：全索引扫描（只读二级索引，但也是扫全表的量）
EXPLAIN SELECT user_id FROM orders;

-- (f) ALL：全表扫描，预估 199430 行
EXPLAIN SELECT * FROM orders WHERE amount > 5000;

-- (g) system：理论上是"表只有 1 行"，8.0.46 实测单行临时表给的是 ALL
CREATE TEMPORARY TABLE t_one_row (a INT);
INSERT INTO t_one_row VALUES (1);
EXPLAIN SELECT * FROM t_one_row;
DROP TEMPORARY TABLE t_one_row;

-- (h) type=NULL：子查询被提前算完，表都不用打开
EXPLAIN SELECT * FROM orders o WHERE o.id = (SELECT MAX(id) FROM orders m WHERE m.user_id = 42);

-- 八级速查表
SELECT 1 AS 等级, 'system' AS type, '表只有 1 行' AS 含义, '8.0.46 实测没出现（单行表给 ALL）' AS 本库实测
UNION ALL SELECT 2, 'const', '主键/唯一索引等值，最多 1 行', 'orders WHERE id = 100'
UNION ALL SELECT 3, 'eq_ref', 'join 时查主键/唯一索引，每行配 1 行', 'o JOIN u ON u.id = o.user_id'
UNION ALL SELECT 4, 'ref', '非唯一索引等值', 'orders WHERE user_id = 42'
UNION ALL SELECT 5, 'range', '索引范围扫描', 'orders WHERE user_id BETWEEN 40 AND 50'
UNION ALL SELECT 6, 'index', '扫完整个二级索引', 'SELECT user_id FROM orders'
UNION ALL SELECT 7, 'ALL', '全表扫描，最差', 'orders WHERE amount > 5000'
UNION ALL SELECT 8, 'NULL', 'Select tables optimized away，子查询提前算完', 'WHERE id = (SELECT MAX(id) ...)';

-- ============================================================
-- 3. ★ rows × filtered：预估的乘法
-- ============================================================
-- rows=199430（读这么多行）× filtered=33.33%（其中 1/3 能过 WHERE）≈ 预估 66470 行有用
EXPLAIN SELECT * FROM orders WHERE amount > 5000;

-- 加了 ORDER BY id LIMIT 10：扫到 10 行就停，rows 直接变成 10
EXPLAIN SELECT * FROM orders WHERE amount > 5000 ORDER BY id LIMIT 10;

-- 覆盖索引：要的列都在索引里，Extra 出现 Using index，不回表
EXPLAIN SELECT status, created_at FROM orders WHERE status = 'paid';

-- ============================================================
-- 4. ★ 拆一次三表 JOIN
-- ============================================================
-- 先看三张表单独查是什么计划
EXPLAIN SELECT id FROM users WHERE id = 42;
EXPLAIN SELECT * FROM orders WHERE user_id = 42;
EXPLAIN SELECT * FROM order_items WHERE product_name = '显示器';

-- 优化器选的顺序：users 全表扫(5070, 留10%) → 每行查 orders(ref 41, 留47.96%) → 每行查 order_items(ref 3, 留10%)
EXPLAIN SELECT o.id, i.product_name
FROM users u JOIN orders o ON o.user_id = u.id JOIN order_items i ON i.order_id = o.id
WHERE u.city = '北京' AND o.status = 'paid' AND i.product_name = '显示器';

-- 用 STRAIGHT_JOIN 强按书写顺序 join：先扫 orders 全索引 199430 行，再回 users、order_items
EXPLAIN SELECT o.id, i.product_name
FROM orders o STRAIGHT_JOIN users u ON u.id = o.user_id STRAIGHT_JOIN order_items i ON i.order_id = o.id
WHERE u.city = '北京' AND o.status = 'paid' AND i.product_name = '显示器';

-- ============================================================
-- 5. ★ 估算 vs 实际：EXPLAIN ANALYZE 与统计信息过期
-- ============================================================
-- 先 ANALYZE 一下，保证读者看到的统计值和这里一致
ANALYZE TABLE order_items;
SELECT TABLE_ROWS AS order_items_估算行数 FROM information_schema.TABLES
 WHERE TABLE_SCHEMA = 'easy_mysql' AND TABLE_NAME = 'order_items';

-- 估算 25872 行，实际跑出 13364 行：预估翻了近一倍
EXPLAIN ANALYZE SELECT * FROM orders WHERE user_id = 1\G

-- 估算 66470 行，实际 42198 行
EXPLAIN ANALYZE SELECT COUNT(*) FROM orders WHERE amount > 5000\G

-- ============================================================
-- 5.5 ★ EXPLAIN FORMAT=JSON：把成本摊开给机器读
-- ============================================================
-- 表格版只给你结果，JSON 版连"为什么"一起给：读了哪些键、成本多少
EXPLAIN FORMAT=JSON SELECT * FROM orders WHERE user_id = 42\G
EXPLAIN FORMAT=JSON SELECT COUNT(*) FROM orders WHERE status='paid' AND created_at >= '2024-07-01'\G
-- JSON 里的 query_cost 就是优化器算出来的代价：
-- 第一条 10.15，第二条 10357.10 —— 差一千倍，优化器不傻

-- 正常统计下：先扫 orders 索引，再按 order_id 查明细（i 行预估 3 行）
EXPLAIN SELECT COUNT(*) FROM orders o JOIN order_items i ON i.order_id = o.id;

-- ★ 模拟统计信息过期：把 order_items 的持久化统计行数直接改成 0
-- （真实场景：批量灌完数据统计还没算，优化器就看到这么一个"空表"）
UPDATE mysql.innodb_table_stats SET n_rows = 0
 WHERE database_name = 'easy_mysql' AND table_name = 'order_items';
FLUSH TABLE order_items;

SELECT TABLE_ROWS AS 过期后估算行数 FROM information_schema.TABLES
 WHERE TABLE_SCHEMA = 'easy_mysql' AND TABLE_NAME = 'order_items';

-- 行数变 0 之后 join 计划翻转：优化器以为明细表只有 1 行，改先扫它
EXPLAIN SELECT COUNT(*) FROM orders o JOIN order_items i ON i.order_id = o.id;

-- 实际跑：预估 1 行的子表被扫了 600000 行（估算 1 / 实际 600000）
EXPLAIN ANALYZE SELECT COUNT(*) FROM orders o JOIN order_items i ON i.order_id = o.id\G

-- ★ 现场恢复：ANALYZE 把统计算回来，计划翻回原样（数据全程未动）
ANALYZE TABLE order_items;
SELECT TABLE_ROWS AS 恢复后估算行数 FROM information_schema.TABLES
 WHERE TABLE_SCHEMA = 'easy_mysql' AND TABLE_NAME = 'order_items';
EXPLAIN SELECT COUNT(*) FROM orders o JOIN order_items i ON i.order_id = o.id;
SELECT COUNT(*) AS order_items实际行数 FROM order_items;

-- ============================================================
-- 6. Extra 列常见取值（每条都是实测）
-- ============================================================
-- Using index：覆盖索引，不回表
EXPLAIN SELECT status, created_at FROM orders WHERE status = 'paid';
-- Using index condition：索引下推，先在索引里过滤再回表
EXPLAIN SELECT * FROM orders WHERE status = 'paid' AND amount > 8000;
-- Using filesort：ORDER BY 的列不在索引里，得额外排序
EXPLAIN SELECT * FROM orders WHERE status = 'paid' ORDER BY amount DESC LIMIT 10;
-- Using temporary：GROUP BY 没走索引，建了临时表
EXPLAIN SELECT product_id, COUNT(*) FROM orders GROUP BY product_id;
-- Backward index scan：8.0 反向扫索引，不是排序
EXPLAIN SELECT * FROM orders WHERE status = 'paid' ORDER BY created_at DESC LIMIT 10;
-- Select tables optimized away：MAX 直接从索引取，表都不扫
EXPLAIN SELECT MAX(id) FROM orders;

-- ============================================================
-- 7. 慢查询日志：把阈值调小抓一条真凶
-- ============================================================
SHOW VARIABLES LIKE 'slow_query_log';
SHOW VARIABLES LIKE 'long_query_time';
SHOW VARIABLES LIKE 'slow_query_log_file';
SHOW VARIABLES LIKE 'log_output';

-- ★ 先把原值记下来（会话级改动，连接断开也会自动失效，但还是恢复回去）
SET @old_lqt = @@SESSION.long_query_time;

-- 阈值调到 0 秒（只影响当前会话），跑一条慢的
SET SESSION long_query_time = 0;
SELECT COUNT(*) FROM orders o JOIN order_items i ON i.order_id = o.id;

-- ★ 恢复原值
SET SESSION long_query_time = @old_lqt;
SHOW VARIABLES LIKE 'long_query_time';

-- 日志内容不在 SQL 里看，用容器 shell：
--   docker exec easy-mysql tail -n 5 /var/lib/mysql/<容器ID>-slow.log
-- 文件名里的容器 ID 每台机器不一样，以上面 SHOW VARIABLES 的输出为准

-- ============================================================
-- 8. 收尾自检：确认没有改动任何基线数据
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

SET information_schema_stats_expiry = 86400;
