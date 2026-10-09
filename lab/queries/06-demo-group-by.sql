-- =============================================================================
-- 06-demo-group-by.sql · 第 06 篇配套实验
--
-- 对应 docs/06-group-by-having.md 的 6 个小节，可以按小节分段跑。
-- 全文件只读。数据是固定的，你的数字一定和注释里的一样。
-- =============================================================================

SET NAMES utf8mb4;


USE easy_mysql;

-- =============================================================================
-- 第 1 节：从一列数字到一张报表 —— 每班多少人
-- =============================================================================
SELECT class_name, COUNT(*) AS 人数
FROM students
GROUP BY class_name
ORDER BY class_name;
-- 软工210~213 班各 50 人

-- =============================================================================
-- 第 2 节：★ ONLY_FULL_GROUP_BY —— 非聚合列必须进 GROUP BY
-- =============================================================================
-- 下面这句会报错（name 不在分组键里，每组不知道该显示谁的 name），错误原文：
--   ERROR 1055 (42000): Expression #1 of SELECT list is not in GROUP BY clause and
--   contains nonaggregated column 'easy_mysql.s.name' which is not functionally
--   dependent on columns in GROUP BY clause; this is incompatible with
--   sql_mode=only_full_group_by
-- SELECT s.name, COUNT(*) FROM students s JOIN scores sc ON sc.student_id=s.id GROUP BY s.class_name;

-- 解法 1：只留分组键和聚合
SELECT s.class_name, COUNT(*) AS 成绩条数
FROM students s JOIN scores sc ON sc.student_id = s.id
GROUP BY s.class_name
ORDER BY s.class_name;

-- 解法 2：把 name 也加进 GROUP BY（这样每行是一个学生）
SELECT s.class_name, s.name, COUNT(*) AS 科目数
FROM students s JOIN scores sc ON sc.student_id = s.id
GROUP BY s.class_name, s.name
ORDER BY s.class_name, s.name
LIMIT 10;

-- =============================================================================
-- 第 3 节：本篇主菜 —— JOIN 之后再分组，算每班平均分
-- =============================================================================
SELECT s.class_name,
       COUNT(*)                AS 成绩条数,
       ROUND(AVG(sc.score), 2) AS 平均分,
       MAX(sc.score)           AS 最高分
FROM students s
JOIN scores sc ON sc.student_id = s.id
GROUP BY s.class_name
ORDER BY 平均分 DESC;

-- =============================================================================
-- 第 4 节：执行顺序（口诀，不用跑）
--   FROM → WHERE → GROUP BY → HAVING → SELECT → ORDER BY → LIMIT
--   WHERE  分的是"行"，那时还没分组 → 不能用聚合
--   HAVING 分的是"组"，分组已经完成 → 可以用聚合
-- =============================================================================

-- =============================================================================
-- 第 5 节：★ WHERE vs HAVING —— 同一个需求，两种写法，两个不同的数
-- =============================================================================
-- 需求 A：只统计"及格成绩"的平均分（WHERE 先扔掉不及格的行）
SELECT s.class_name, ROUND(AVG(sc.score), 2) AS 及格平均分
FROM students s JOIN scores sc ON sc.student_id = s.id
WHERE sc.score >= 60
GROUP BY s.class_name
ORDER BY s.class_name;

-- 需求 B：先算每班全科平均分，再筛掉平均分不到 70 的班（HAVING 筛的是组）
SELECT s.class_name, ROUND(AVG(sc.score), 2) AS 全科平均分
FROM students s JOIN scores sc ON sc.student_id = s.id
GROUP BY s.class_name
HAVING AVG(sc.score) >= 70
ORDER BY s.class_name;
-- 只剩 210、212 两个班（211 是 69.78，213 是 69.57，整组被删掉）

-- =============================================================================
-- 第 6 节：多字段分组 —— 城市 × 性别
-- =============================================================================
SELECT city, gender, COUNT(*) AS 人数
FROM students
GROUP BY city, gender
ORDER BY city, gender;
-- 这份数据里每城只有一种性别（造数据时故意的，方便你一眼看出分组结果）

-- =============================================================================
-- 第 7 节：ROLLUP —— 分组小计 + 总计
-- =============================================================================
-- ORDER BY 分组列：汇总行的 class_name 是 NULL，默认排在最前面
SELECT s.class_name, ROUND(AVG(sc.score), 2) AS 平均分, COUNT(*) AS 成绩条数
FROM students s JOIN scores sc ON sc.student_id = s.id
GROUP BY s.class_name WITH ROLLUP
ORDER BY s.class_name;

-- ORDER BY 聚合列：MySQL 8.0.46 实测能跑（网络上"ROLLUP 不能按聚合列排序"的说法不成立）
-- 但汇总行会按自己的平均分 69.97 插进队伍中间，想要"总计在最后"还是得按分组列排
SELECT s.class_name, ROUND(AVG(sc.score), 2) AS 平均分
FROM students s JOIN scores sc ON sc.student_id = s.id
GROUP BY s.class_name WITH ROLLUP
ORDER BY 平均分 DESC;

-- =============================================================================
-- 练习 1：每门课的报名人数、平均分、最高分，只留平均分 >= 60 的课
-- =============================================================================
SELECT c.name AS 课程, COUNT(*) AS 报名人数, ROUND(AVG(sc.score), 2) AS 平均分, MAX(sc.score) AS 最高分
FROM scores sc JOIN courses c ON c.id = sc.course_id
GROUP BY c.id, c.name
HAVING AVG(sc.score) >= 60
ORDER BY 平均分 DESC;
-- 10 门全过（最低的 Python 入门也有 67.74）；把 60 改成 70 再跑，只剩 5 门

-- =============================================================================
-- 练习 2：每个学生的不及格科目数，只看有不及格的
-- =============================================================================
SELECT s.name, COUNT(*) AS 不及格门数
FROM students s JOIN scores sc ON sc.student_id = s.id
WHERE sc.score < 60                -- 先筛行：只要不及格的成绩
GROUP BY s.id, s.name
HAVING COUNT(*) >= 1               -- 再筛组：有不及格的才留下（写 >= 1 是为了让你看清这里在筛组）
ORDER BY 不及格门数 DESC, s.name
LIMIT 10;
-- 全校 197 人至少挂一科，最多的一个挂了 8 科

-- =============================================================================
-- 收尾自检
-- =============================================================================
SELECT 'students' AS check_item, COUNT(*) AS 应为 FROM students
UNION ALL SELECT 'scores', COUNT(*) FROM scores
UNION ALL SELECT 'courses', COUNT(*) FROM courses;
-- 期望：200 / 2000 / 20
