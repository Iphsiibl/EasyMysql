-- 09-demo-functions.sql · 第 09 篇配套实验

SET NAMES utf8mb4;


USE easy_mysql;

-- ===== 字符串 =====
SELECT CONCAT(name, '（', city, '）') AS 标签 FROM students LIMIT 5;
SELECT name,
       LEFT(name, 1)                 AS 姓,
       RIGHT(name, 1)                AS 最后一个字,
       CHAR_LENGTH(name)             AS 字符数,
       LENGTH(name)                  AS 字节数_utf8
FROM students LIMIT 5;

-- ===== 日期：按月统计（这一段第 15 篇会用到）=====
SELECT DATE_FORMAT(created_at, '%Y-%m') AS 月份,
       COUNT(*)              AS 订单数,
       ROUND(SUM(amount),2)  AS 销售额
FROM orders
GROUP BY 月份
ORDER BY 月份 LIMIT 5;

-- ===== ★★ 反模式 vs 正确写法（重点）=====
-- 反模式：对索引列套函数，只能全索引扫（type=index, rows=199430）
EXPLAIN SELECT COUNT(*) FROM orders WHERE YEAR(created_at) = 2024;
-- 正确：改成范围条件，type 变 range，rows 降到 22154
EXPLAIN SELECT COUNT(*) FROM orders
WHERE created_at >= '2024-01-01' AND created_at < '2025-01-01';

-- 按年看不出差别（本库订单全在 2024 年），按月对比最清楚
EXPLAIN SELECT COUNT(*) FROM orders WHERE MONTH(created_at) = 6;
EXPLAIN SELECT COUNT(*) FROM orders
WHERE created_at >= '2024-06-01' AND created_at < '2024-07-01';

-- 联合索引 (status, created_at) 的对照：看 key_len 就知道第 2 列用没用上
EXPLAIN SELECT COUNT(*) FROM orders WHERE status = 'paid' AND YEAR(created_at) = 2024;
EXPLAIN SELECT COUNT(*) FROM orders
WHERE status = 'paid' AND created_at >= '2024-06-01' AND created_at < '2024-07-01';

-- ===== DATEDIFF：距今天多少天 =====
SELECT name, birth_date, DATEDIFF(CURDATE(), birth_date) AS 出生天数
FROM students LIMIT 5;

-- ===== LAST_DAY：某个月的最后一天 =====
SELECT LAST_DAY('2024-02-01') AS 二月最后一天;

-- ===== NULL 三兄弟 =====
SELECT id, remark, IFNULL(remark, '（空）')      AS 用_IFNULL,
       COALESCE(remark, '（空）')                AS 用_COALESCE,
       NULLIF(remark, '教学用反面教材')           AS 用_NULLIF
FROM bad_design_demo LIMIT 3;
-- IFNULL 只能接 1 个兜底值；COALESCE 可以接多个，优先用 COALESCE
-- 本数据集 20 行的 remark / extra 都有值（没有真 NULL），所以补一组字面量演示
SELECT IFNULL(NULL, '（空）')                        AS 用_IFNULL,
       COALESCE(NULL, '中间值', '（兜底）')           AS 用_COALESCE,
       NULLIF('教学用反面教材', '教学用反面教材')      AS 用_NULLIF;
-- 聚合函数会跳过 NULL：80 和 90 的平均是 85，NULL 不参与也不报错
SELECT AVG(x) AS 平均分 FROM (SELECT 80 AS x UNION ALL SELECT 90 UNION ALL SELECT NULL) t;

-- ===== ★ CASE WHEN 做分类（本篇最容易出成果的技巧）=====
SELECT s.name,
       SUM(CASE WHEN sc.score >= 90 THEN 1 ELSE 0 END) AS 优秀,
       SUM(CASE WHEN sc.score >= 80 THEN 1 ELSE 0 END) AS 良好,
       SUM(CASE WHEN sc.score >= 60 THEN 1 ELSE 0 END) AS 及格,
       SUM(CASE WHEN sc.score <  60 THEN 1 ELSE 0 END) AS 不及格
FROM students s
JOIN scores sc ON sc.student_id = s.id
GROUP BY s.id, s.name
ORDER BY 优秀 DESC LIMIT 10;

-- ===== IF()：三元表达式 =====
SELECT city, IF(COUNT(*) > 60, '人很多', '人不多') AS 规模
FROM students GROUP BY city;

-- ===== 条件聚合做行转列 =====
SELECT
  SUM(status = 'created')  AS 待付款,
  SUM(status = 'paid')     AS 已付款,
  SUM(status = 'shipped')  AS 已发货,
  SUM(status = 'cancelled') AS 已取消
FROM orders;
