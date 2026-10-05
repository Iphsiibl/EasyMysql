-- 06-demo-group-by.sql · 第 06 篇配套实验

SET NAMES utf8mb4;


USE easy_mysql;

-- ===== 最基本的分组：每班多少人 =====
SELECT class_name, COUNT(*) AS 人数
FROM students
GROUP BY class_name;

-- ===== 本篇主菜：JOIN 之后分组，算每班平均分 =====
SELECT s.class_name,
       COUNT(*)              AS 成绩条数,
       ROUND(AVG(sc.score), 2) AS 平均分,
       MAX(sc.score)         AS 最高分
FROM students s
JOIN scores sc ON sc.student_id = s.id
GROUP BY s.class_name
ORDER BY 平均分 DESC;

-- ===== ★ WHERE vs HAVING 对比（同一个需求，两种写法）=====
-- 需求：统计每班「及格成绩」的平均分
-- 写法 A：WHERE 过滤行
SELECT s.class_name, ROUND(AVG(sc.score), 2) AS 及格平均分
FROM students s JOIN scores sc ON sc.student_id = s.id
WHERE sc.score >= 60
GROUP BY s.class_name;

-- 写法 B：先算每组平均分，HAVING 再筛掉平均分低的组
SELECT s.class_name, ROUND(AVG(sc.score), 2) AS 全科平均分
FROM students s JOIN scores sc ON sc.student_id = s.id
GROUP BY s.class_name
HAVING AVG(sc.score) >= 60;

-- ===== 多字段分组：城市 × 性别 =====
SELECT city, gender, COUNT(*) AS 人数
FROM students
GROUP BY city, gender
ORDER BY city, gender;

-- ===== ONLY_FULL_GROUP_BY：SELECT 里的非聚合列必须出现在 GROUP BY 里 =====
-- 这一句会报错，解法是把 name 也加进 GROUP BY
-- SELECT s.name, COUNT(*) FROM students s JOIN scores sc ON sc.student_id=s.id GROUP BY s.class_name;
SELECT s.class_name, s.name, COUNT(*) AS 科目数
FROM students s JOIN scores sc ON sc.student_id = s.id
GROUP BY s.class_name, s.name
LIMIT 10;

-- ===== ROLLUP：多汇总行（班级小计 + 全校总计）=====
SELECT s.class_name, ROUND(AVG(sc.score), 2) AS 平均分, COUNT(*) AS 人数
FROM students s JOIN scores sc ON sc.student_id = s.id
GROUP BY s.class_name WITH ROLLUP;
