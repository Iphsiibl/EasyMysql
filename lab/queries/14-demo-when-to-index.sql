-- 14-demo-when-to-index.sql · 第 14 篇配套实验：该不该建索引
-- 用法：docker cp 本文件进容器后 source，输出即文章里引用的输出
-- 本文件会自己清理：临时索引全部 DROP，插入的行全部 DELETE

SET NAMES utf8mb4;

USE easy_mysql;

-- ============================================================
-- 1. ★ 开场实验：给每个字段都加上索引，会怎样
-- ============================================================
-- information_schema 默认缓存统计 24 小时，先关掉缓存拿到最新体积
SET information_schema_stats_expiry = 0;

SELECT COUNT(*) AS 行数 FROM orders_slow;
SELECT ROUND((DATA_LENGTH+INDEX_LENGTH)/1024) AS 加索引前_体积KB
FROM information_schema.TABLES
WHERE TABLE_SCHEMA='easy_mysql' AND TABLE_NAME='orders_slow';

-- 基线：orders_slow 只有主键，没有二级索引
SHOW INDEX FROM orders_slow;

-- 写入基线 A：没有任何二级索引时，插 2000 行
SET @t0 = NOW(6);
INSERT INTO orders_slow (user_id, product_id, quantity, amount, status, created_at, updated_at)
SELECT user_id, product_id, quantity, amount, status, created_at, updated_at
FROM orders WHERE id <= 2000;
SELECT ROUND(TIMESTAMPDIFF(MICROSECOND,@t0,NOW(6))/1000,1) AS 无索引插入2000行_毫秒;
DELETE FROM orders_slow WHERE id > 200000;

-- 把 7 个非主键字段全部加上索引
ALTER TABLE orders_slow
  ADD INDEX idx_i_user (user_id),
  ADD INDEX idx_i_product (product_id),
  ADD INDEX idx_i_quantity (quantity),
  ADD INDEX idx_i_amount (amount),
  ADD INDEX idx_i_status (status),
  ADD INDEX idx_i_created (created_at),
  ADD INDEX idx_i_updated (updated_at);

-- 新索引刚建好，统计信息还没算，先 ANALYZE 才能看到体积变化
ANALYZE TABLE orders_slow;
SELECT ROUND((DATA_LENGTH+INDEX_LENGTH)/1024) AS 加满索引后_体积KB
FROM information_schema.TABLES
WHERE TABLE_SCHEMA='easy_mysql' AND TABLE_NAME='orders_slow';

-- 写入基线 B：同样插 2000 行
SET @t0 = NOW(6);
INSERT INTO orders_slow (user_id, product_id, quantity, amount, status, created_at, updated_at)
SELECT user_id, product_id, quantity, amount, status, created_at, updated_at
FROM orders WHERE id <= 2000;
SELECT ROUND(TIMESTAMPDIFF(MICROSECOND,@t0,NOW(6))/1000,1) AS 加满索引插入2000行_毫秒;
DELETE FROM orders_slow WHERE id > 200000;

-- 索引全加上之后，status 查询也只是扫半张表（白花的空间）
EXPLAIN SELECT * FROM orders_slow WHERE status = 'paid';

-- ★ 清理：7 个索引全部删掉，恢复成只有主键
ALTER TABLE orders_slow
  DROP INDEX idx_i_user, DROP INDEX idx_i_product, DROP INDEX idx_i_quantity,
  DROP INDEX idx_i_amount, DROP INDEX idx_i_status, DROP INDEX idx_i_created,
  DROP INDEX idx_i_updated;
ANALYZE TABLE orders_slow;

SELECT ROUND((DATA_LENGTH+INDEX_LENGTH)/1024) AS 恢复后_体积KB
FROM information_schema.TABLES
WHERE TABLE_SCHEMA='easy_mysql' AND TABLE_NAME='orders_slow';
SELECT COUNT(*) AS 恢复后行数 FROM orders_slow;

-- ============================================================
-- 2. status 这种字段值不值得单独建索引
-- ============================================================
-- 4 个值，每个值正好 5 万行 = 25% 的行
SELECT status, COUNT(*) AS cnt FROM orders GROUP BY status;

-- 用 status 查：索引"用上了"，但估算要扫 9.5 万行（半张表）
EXPLAIN SELECT * FROM orders WHERE status = 'paid';

-- 对照：user_id = 42 只有 29 单
EXPLAIN SELECT * FROM orders WHERE user_id = 42;

-- ============================================================
-- 3. 区分度怎么量：COUNT(DISTINCT) / COUNT
-- ============================================================
-- 越接近 1 越值得建索引；接近 0 的单独建索引没意义
SELECT 'user_id' AS 字段, COUNT(DISTINCT user_id) AS 不同值, COUNT(*) AS 总行数,
       ROUND(COUNT(DISTINCT user_id)/COUNT(*),4) AS 区分度 FROM orders
UNION ALL SELECT 'product_id', COUNT(DISTINCT product_id), COUNT(*),
       ROUND(COUNT(DISTINCT product_id)/COUNT(*),4) FROM orders
UNION ALL SELECT 'status', COUNT(DISTINCT status), COUNT(*),
       ROUND(COUNT(DISTINCT status)/COUNT(*),4) FROM orders
UNION ALL SELECT 'quantity', COUNT(DISTINCT quantity), COUNT(*),
       ROUND(COUNT(DISTINCT quantity)/COUNT(*),4) FROM orders
UNION ALL SELECT 'amount', COUNT(DISTINCT amount), COUNT(*),
       ROUND(COUNT(DISTINCT amount)/COUNT(*),4) FROM orders
UNION ALL SELECT 'created_at', COUNT(DISTINCT created_at), COUNT(*),
       ROUND(COUNT(DISTINCT created_at)/COUNT(*),4) FROM orders;

-- ============================================================
-- 4. 索引失效的 8 种写法（每条都给前后对照）
-- ============================================================

-- 失效① 在索引列上套函数
-- 先给 created_at 建个临时索引，好让"正确写法"能用上
ALTER TABLE orders ADD INDEX idx_tmp_created (created_at);
EXPLAIN SELECT * FROM orders WHERE DATE(created_at) = '2024-07-01';
-- 正确写法：范围条件
EXPLAIN SELECT * FROM orders WHERE created_at >= '2024-07-01' AND created_at < '2024-07-02';
ALTER TABLE orders DROP INDEX idx_tmp_created;

-- 失效② 在索引列上做运算
EXPLAIN SELECT * FROM orders WHERE user_id + 1 = 43;
-- 正确写法：把运算挪到常量侧
EXPLAIN SELECT * FROM orders WHERE user_id = 42;

-- 失效③ 隐式类型转换（转换发生在"列"这一侧，索引就废了）
EXPLAIN SELECT * FROM students WHERE name = 0;
-- 正确写法：字符串列就跟字符串比
EXPLAIN SELECT * FROM students WHERE name = '王伟';
-- 注意：反过来（int 列比字符串常量）MySQL 会把常量转成数字，索引还在
EXPLAIN SELECT * FROM orders WHERE user_id = '42';

-- 失效④ 前导模糊 LIKE '%xx'
EXPLAIN SELECT * FROM students WHERE name LIKE '%伟';
-- 后缀模糊能用上索引
EXPLAIN SELECT * FROM students WHERE name LIKE '王%';

-- 失效⑤ OR 连接了没索引的列
EXPLAIN SELECT * FROM orders WHERE user_id = 42 OR amount > 5000;
-- 改写：UNION ALL，第一个分支走索引
EXPLAIN SELECT id, user_id, amount FROM orders WHERE user_id = 42
UNION ALL
SELECT id, user_id, amount FROM orders WHERE amount > 5000;

-- 失效⑤ 附赠：OR 两边其实都有索引，照样全表扫
-- （两个条件的并集覆盖了大半张表，优化器认为不值当开索引合并）
EXPLAIN SELECT COUNT(*) FROM orders WHERE user_id = 42 OR status = 'paid';
-- 但同一个索引列上的 OR 会被改写成 IN，走 range
EXPLAIN SELECT COUNT(*) FROM orders WHERE user_id = 42 OR user_id = 43;

-- 失效⑥ !=
EXPLAIN SELECT * FROM orders WHERE user_id != 42;
-- 反转：加了 LIMIT 之后，优化器又肯用索引了
EXPLAIN SELECT * FROM orders WHERE user_id != 42 LIMIT 10;

-- 失效⑦ NOT IN
EXPLAIN SELECT * FROM orders WHERE user_id NOT IN (42, 43);

-- 失效⑧ 写法没错、索引也在，但要命中一半的行 → 优化器主动放弃
EXPLAIN SELECT * FROM orders WHERE status IN ('created','paid');

-- ============================================================
-- 5. 联合索引预览：idx_orders_status_created (status, created_at) 的 6 种查询方式
-- ============================================================
-- ① 只查第 1 列（等值）→ key_len=1
EXPLAIN SELECT * FROM orders WHERE status = 'paid';
-- ② 第 1 列等值 + 第 2 列范围 → key_len=6，两列都用上
EXPLAIN SELECT * FROM orders WHERE status = 'paid' AND created_at >= '2024-07-01';
-- ③ 跳过第 1 列直接查第 2 列 → 最左前缀断了，全表扫
EXPLAIN SELECT * FROM orders WHERE created_at >= '2024-07-01';
-- ④ 第 1 列用 IN（本质仍是等值）→ 还是只用第 1 列
EXPLAIN SELECT * FROM orders WHERE status IN ('paid', 'shipped');
-- ⑤ 索引里没有的第 3 列：优化器没走联合索引，而是换了更便宜的 user_id 索引（29 行）
EXPLAIN SELECT * FROM orders WHERE status = 'paid' AND created_at >= '2024-07-01' AND user_id = 42;
-- ⑥ 同样两个条件，但命中大半张表 → 优化器判断不如全表扫（不是写法错，是不值当）
EXPLAIN SELECT * FROM orders WHERE status IN ('paid','shipped') AND created_at >= '2024-07-01';

-- ============================================================
-- 6. 收尾自检：索引恢复成基线
-- ============================================================
SET information_schema_stats_expiry = 86400;
SHOW INDEX FROM orders;
SHOW INDEX FROM orders_slow;
SELECT COUNT(*) AS orders行数 FROM orders;
SELECT COUNT(*) AS orders_slow行数 FROM orders_slow;
