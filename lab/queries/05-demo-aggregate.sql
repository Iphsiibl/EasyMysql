-- =============================================================================
-- 05-demo-aggregate.sql · 第 05 篇配套实验
--
-- 对应 docs/05-order-limit-aggregate.md 的 6 个小节，可以按小节分段跑。
-- 全文件只读。数据是固定的，rows 一定和注释一样；Duration 随机器变化。
-- =============================================================================

SET NAMES utf8mb4;


USE easy_mysql;

-- =============================================================================
-- 第 1 节：五个聚合函数，把 2000 条成绩压成一行
-- =============================================================================
SELECT COUNT(*)         AS 成绩条数,
       SUM(score)       AS 总分,
       ROUND(AVG(score), 2) AS 平均分,
       MAX(score)       AS 最高分,
       MIN(score)       AS 最低分
FROM scores;
-- 2000 / 139936.00 / 69.97 / 100.00 / 40.00

-- =============================================================================
-- 第 2 节：COUNT(*) vs COUNT(列) vs COUNT(DISTINCT 列)
-- =============================================================================
-- students 的每一列都是 NOT NULL，所以前两个数字必然一样
SELECT COUNT(*) AS count_star, COUNT(city) AS count_col, COUNT(DISTINCT city) AS 城市数
FROM students;
-- 200 / 200 / 6

-- COUNT(列) 的规则是"跳过 NULL"。用 COUNT(NULL) 人为造一列 NULL 看效果
SELECT COUNT(*) AS 全部行, COUNT(NULL) AS 永远不算 FROM students;
-- 200 / 0

-- DISTINCT：去重计数
SELECT COUNT(*) AS 行数, COUNT(DISTINCT student_id) AS 人数, COUNT(DISTINCT course_id) AS 门数
FROM scores;
-- 2000 / 200 / 10

-- 条件聚合：把 WHERE 的条件塞进 SUM 里，一次算出及格率
SELECT COUNT(*) AS 总条数,
       SUM(score >= 60) AS 及格条数,
       ROUND(SUM(score >= 60) / COUNT(*), 4) AS 及格率
FROM scores;

-- =============================================================================
-- 第 3 节：聚合函数不能出现在 WHERE 里（想筛"平均分"要等第 06 篇的 HAVING）
-- =============================================================================
-- 下面这句会直接报错，错误原文：
--   ERROR 1111 (HY000): Invalid use of group function
-- SELECT AVG(score) FROM scores WHERE AVG(score) >= 60;

-- 想筛行只能筛原始行（这是合法的，筛的是"分数"不是"平均分"）
SELECT ROUND(AVG(score), 2) AS 及格分的平均分 FROM scores WHERE score >= 60;
-- 注意：这是"及格成绩的平均分"，不是"全体的平均分"，两个概念别混

-- =============================================================================
-- 第 4 节：分页与深分页的坑
-- =============================================================================
SELECT id, user_id, amount FROM orders ORDER BY id LIMIT 10;              -- 第 1~10 条
SELECT id, user_id, amount FROM orders ORDER BY id LIMIT 10 OFFSET 10;    -- 第 11~20 条
SELECT id, user_id, amount FROM orders ORDER BY id LIMIT 10, 10;          -- 同上，更常用

-- ★ 深分页：OFFSET 100000 时，数据库要先读出并丢掉前 10 万行
EXPLAIN SELECT id, user_id, amount FROM orders ORDER BY id LIMIT 10;
-- rows = 10

EXPLAIN SELECT id, user_id, amount FROM orders ORDER BY id LIMIT 100000, 20;
-- rows = 100020 ← 代价全在 OFFSET 上

-- 实测耗时（跑两遍避免首次预热干扰）
SET profiling = 1;
SELECT id, user_id, amount FROM orders ORDER BY id LIMIT 100000, 20;
SELECT id, user_id, amount FROM orders ORDER BY id LIMIT 100000, 20;
SELECT o.id, o.user_id, o.amount FROM orders o JOIN (SELECT id FROM orders ORDER BY id LIMIT 100000, 20) t ON t.id = o.id ORDER BY o.id;
SELECT o.id, o.user_id, o.amount FROM orders o JOIN (SELECT id FROM orders ORDER BY id LIMIT 100000, 20) t ON t.id = o.id ORDER BY o.id;
SELECT id, user_id, amount FROM orders WHERE id > 150000 ORDER BY id LIMIT 20;
SELECT id, user_id, amount FROM orders WHERE id > 150000 ORDER BY id LIMIT 20;
SELECT id, user_id, amount FROM orders ORDER BY id LIMIT 10;
SHOW PROFILES;
-- ★ 你的 Duration 和这里肯定不一样，这正常。要记的是数量级：
--   深分页 ≈ 0.02 秒，延迟关联 ≈ 0.02 秒（同一数量级），游标分页 ≈ 0.001 秒（快约一个数量级），
--   第一页 ≈ 0.0002 秒

-- =============================================================================
-- 第 5 节：Top-N 的两种正确写法
-- =============================================================================

-- 【写法 A】游标分页：记住上一页最后一条 id，下一页从它后面开始
SELECT id, user_id, amount FROM orders WHERE id > 150000 ORDER BY id LIMIT 20;
-- 结果和 OFFSET 100000, 20 一模一样，但不用"跳过"任何一行

EXPLAIN SELECT id, user_id, amount FROM orders WHERE id > 150000 ORDER BY id LIMIT 20;
-- type = range ← 直接定位到 id>150000 的位置开始读，读够 20 行就停

-- 【写法 B】延迟关联：必须用 OFFSET 时，让内层子查询只取 id
SELECT o.id, o.user_id, o.amount FROM orders o
JOIN (SELECT id FROM orders ORDER BY id LIMIT 100000, 20) t ON t.id = o.id
ORDER BY o.id;
-- 输出和普通深分页完全一样（20 行）

EXPLAIN SELECT o.id, o.user_id, o.amount FROM orders o
JOIN (SELECT id FROM orders ORDER BY id LIMIT 100000, 20) t ON t.id = o.id
ORDER BY o.id;
-- 内层 DERIVED：Using index，只在主键索引上数数，不取别的列
-- 外层 o：eq_ref rows=1，拿到 20 个 id 后每个只查 1 次

-- 金额最高的 10 笔（amount 上没索引，会 filesort，第 16 篇优化它）
SELECT id, user_id, amount FROM orders ORDER BY amount DESC LIMIT 10;

-- =============================================================================
-- 第 6 节：最高分是谁 —— 先聚合拿到数字，再回表找人
-- =============================================================================
-- 满分不止一个人：
SELECT COUNT(*) AS 满分条数 FROM scores WHERE score = (SELECT MAX(score) FROM scores);  -- 27

SELECT s.name, c.name AS 课程, sc.score
FROM scores sc
JOIN students s ON s.id = sc.student_id
JOIN courses  c ON c.id = sc.course_id
WHERE sc.score = (SELECT MAX(score) FROM scores)
ORDER BY sc.id LIMIT 8;

-- =============================================================================
-- 常见错误（注释掉的，想看报错就解开跑）
-- =============================================================================
-- 想要"班级 + 人数"却忘了 GROUP BY：
--   SELECT class_name, COUNT(*) FROM students;
--   ERROR 1140 (42000): In aggregated query without GROUP BY, expression #1 of SELECT
--   list contains nonaggregated column 'easy_mysql.students.class_name'; this is
--   incompatible with sql_mode=only_full_group_by
-- 解法：GROUP BY class_name（第 06 篇）

-- =============================================================================
-- 收尾自检
-- =============================================================================
SELECT 'students' AS check_item, COUNT(*) AS 应为 FROM students
UNION ALL SELECT 'scores',   COUNT(*) FROM scores
UNION ALL SELECT 'orders',   COUNT(*) FROM orders;
-- 期望：200 / 2000 / 200000
