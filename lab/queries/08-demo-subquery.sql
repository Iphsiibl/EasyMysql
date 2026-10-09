-- 08-demo-subquery.sql · 第 08 篇配套实验

SET NAMES utf8mb4;


USE easy_mysql;

-- ===== 标量子查询：结果是一个值 =====
SELECT student_id, score FROM scores WHERE score > (SELECT AVG(score) FROM scores) LIMIT 5;

-- 顺便看看这个平均值是多少
SELECT ROUND(AVG(score),2) AS 全校平均分 FROM scores;

-- ===== IN 子查询：查有订单的用户 =====
-- ★ 注意：LIMIT 不能直接写在 IN 的子查询里，MySQL 会报
--   ERROR 1235 (42000): This version of MySQL doesn't yet support 'LIMIT & IN/ALL/ANY/SOME subquery'
--   想截断就截断最外层（下面的 LIMIT 5 写在最外层，合法）；
--   子查询里确实要截断时，把 LIMIT 放进一层派生表也能跑
SELECT id, username FROM users
WHERE id IN (SELECT user_id FROM (SELECT DISTINCT user_id FROM orders) t)
LIMIT 5;

-- 等价的 JOIN 写法：本机实测和 IN 差不多（都是 0.02~0.05 秒），挑可读性顺眼的用
SELECT u.id, u.username FROM users u
JOIN (SELECT DISTINCT user_id FROM orders) t ON t.user_id = u.id
LIMIT 5;

-- ===== EXISTS：逐行去右表探一下，查到一行就算真 =====
-- 老版本 MySQL 里 EXISTS 往往更快；8.0 会把 IN 改写成同样的半连接计划（见下面两条 EXPLAIN）
SELECT u.id, u.username FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id) LIMIT 5;

-- 两种写法各 EXPLAIN 一次：MySQL 8 常把它们优化成同一个计划
EXPLAIN SELECT id FROM users WHERE id IN (SELECT user_id FROM orders);
EXPLAIN SELECT u.id FROM users u WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

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

-- ===== ★ NOT IN 的 NULL 陷阱：子查询里混进一个 NULL，整条查询一行都不返回 =====
SELECT COUNT(*) AS 正常结果
FROM students WHERE id NOT IN (SELECT student_id FROM scores WHERE score < 60);
SELECT COUNT(*) AS 混入NULL之后
FROM students WHERE id NOT IN (SELECT student_id FROM scores WHERE score < 60 UNION SELECT NULL);

-- ===== ★ UNION vs UNION ALL：行数差在哪 =====
SELECT COUNT(*) AS 去重后 FROM (
  SELECT city FROM students GROUP BY city
  UNION
  SELECT city FROM users GROUP BY city) t;
SELECT COUNT(*) AS 不去重 FROM (
  SELECT city FROM students GROUP BY city
  UNION ALL
  SELECT city FROM users GROUP BY city) t;

-- ===== 综合实战：订单数超过所在城市平均订单数的用户 =====
-- 第一步：先看每个城市的人均订单数
SELECT city, ROUND(AVG(cnt),2) AS 人均订单数, COUNT(*) AS 有单用户数
FROM (SELECT u.city, o.user_id, COUNT(*) AS cnt
      FROM users u JOIN orders o ON o.user_id = u.id
      GROUP BY u.city, o.user_id) t
GROUP BY city ORDER BY 人均订单数 DESC;
-- 第二步：拿每个用户和自己城市的平均值比
SELECT u.id, u.username, u.city, t.cnt AS 订单数, a.城市平均
FROM (SELECT user_id, COUNT(*) AS cnt FROM orders GROUP BY user_id) t
JOIN users u ON u.id = t.user_id
JOIN (SELECT city, AVG(cnt) AS 城市平均
      FROM (SELECT user_id, COUNT(*) AS cnt FROM orders GROUP BY user_id) x
      JOIN users u2 ON u2.id = x.user_id
      GROUP BY city) a ON a.city = u.city
WHERE t.cnt > a.城市平均
ORDER BY t.cnt DESC
LIMIT 5;
