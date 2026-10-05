-- 08-demo-subquery.sql · 第 08 篇配套实验

SET NAMES utf8mb4;


USE easy_mysql;

-- ===== 标量子查询：结果是一个值 =====
SELECT student_id, score FROM scores WHERE score > (SELECT AVG(score) FROM scores) LIMIT 5;

-- 顺便看看这个平均值是多少
SELECT ROUND(AVG(score),2) AS 全校平均分 FROM scores;

-- ===== IN 子查询：查有订单的用户 =====
-- ★ 先注意：如果直接把子查询写进 IN 的括号，MySQL 会报
--   ERROR 1235 (42000): This version of MySQL doesn't yet support 'LIMIT & IN/ALL/ANY/SOME subquery'
--   解决办法是包一层派生表
SELECT id, username FROM users
WHERE id IN (SELECT user_id FROM (SELECT DISTINCT user_id FROM orders) t)
LIMIT 5;

-- 更好的写法：JOIN（本仓库 20 万行订单，实测比 IN 快很多）
SELECT u.id, u.username FROM users u
JOIN (SELECT DISTINCT user_id FROM orders) t ON t.user_id = u.id
LIMIT 5;

-- ===== EXISTS：写法更直白，数据量大时常常更快 =====
SELECT u.id, u.username FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id) LIMIT 5;

-- ===== NOT EXISTS：找出没有订单的用户 =====
SELECT COUNT(*) AS 没有订单的用户数 FROM users u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

-- ===== 派生表：子查询当表用 =====
SELECT t.uid AS 用户id, t.cnt AS 订单数
FROM (SELECT user_id AS uid, COUNT(*) AS cnt FROM orders GROUP BY user_id) t
WHERE t.cnt > 100
ORDER BY t.cnt DESC;

-- ===== 相关子查询：每个学生都跑一遍内层查询 =====
-- 找出「高于自己班级平均分」的成绩
SELECT s.name, s.class_name, sc.score
FROM students s
JOIN scores sc ON sc.student_id = s.id
WHERE sc.score > (SELECT AVG(sc2.score)
                  FROM students s2 JOIN scores sc2 ON sc2.student_id = s2.id
                  WHERE s2.class_name = s.class_name)
LIMIT 10;

-- ===== UNION vs UNION ALL =====
SELECT '学生' AS 来源, city, COUNT(*) AS 人数 FROM students GROUP BY city
UNION ALL
SELECT '用户', city, COUNT(*) FROM users GROUP BY city
ORDER BY 来源, city;

-- UNION（去重版）会把两行里 city 相同但来源不同的行保留
-- 如果两列完全一样才会被合并，所以慎用

-- ===== 经典：最高薪不低于自己部门平均薪 =====
SELECT u.id, u.username, u.balance, u.city
FROM users u
WHERE u.balance >= (SELECT AVG(u2.balance) FROM users u2 WHERE u2.city = u.city)
ORDER BY u.balance DESC
LIMIT 5;
