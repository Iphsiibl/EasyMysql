-- 05-demo-aggregate.sql · 第 05 篇配套实验

SET NAMES utf8mb4;


USE easy_mysql;

-- ===== 聚合函数五个都试一遍 =====
SELECT COUNT(*) AS 成绩条数,
       SUM(score) AS 总分,
       ROUND(AVG(score), 2) AS 平均分,
       MAX(score) AS 最高分,
       MIN(score) AS 最低分
FROM scores;

-- ===== COUNT(*) vs COUNT(列) =====
-- students.city 是 NOT NULL，所以两个数字一样；换成允许 NULL 的表才有区别
SELECT COUNT(*) AS count_star, COUNT(city) AS count_col, COUNT(DISTINCT city) AS 城市数
FROM students;

-- ===== 条件聚合：只算及格分 =====
SELECT COUNT(*) AS 总条数,
       SUM(score >= 60) AS 及格条数,
       ROUND(SUM(score >= 60) / COUNT(*), 4) AS 及格率
FROM scores;

-- ===== 分页的两个写法 =====
SELECT id, user_id, amount FROM orders ORDER BY id LIMIT 10;         -- 第 1~10 条
SELECT id, user_id, amount FROM orders ORDER BY id LIMIT 10 OFFSET 10; -- 第 11~20 条
SELECT id, user_id, amount FROM orders ORDER BY id LIMIT 10, 10;      -- 同上，更常用

-- ===== ★ 深分页的大坑（第 16 篇会优化它）=====
-- OFFSET 100000：数据库必须先读出并丢掉前 10 万行
SELECT id, amount FROM orders ORDER BY id LIMIT 100000, 10;

-- ===== Top-N 的标准写法 =====
-- 金额最高的 10 笔
SELECT id, user_id, amount FROM orders ORDER BY amount DESC LIMIT 10;

-- 金额最高的 10 笔，用索引方式（amount 无索引，这里只是展示写法）
SELECT id, user_id, amount FROM orders FORCE INDEX (PRIMARY) ORDER BY id LIMIT 10;

-- ===== 求最高分是哪位学生：子查询 + JOIN =====
SELECT s.name, c.name AS 课程, sc.score
FROM scores sc
JOIN students s ON s.id = sc.student_id
JOIN courses  c ON c.id = sc.course_id
WHERE sc.score = (SELECT MAX(score) FROM scores);

-- ===== ★ 为什么 AVG 和 COUNT 不能直接配 WHERE（第 06 篇解决）=====
-- 这一句的结果是「所有人的平均分」，不是「及格的人的平均分」
SELECT AVG(score) FROM scores WHERE score >= 60;
