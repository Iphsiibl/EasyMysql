-- 07-demo-join.sql · 第 07 篇配套实验

SET NAMES utf8mb4;


USE easy_mysql;

-- ===== INNER JOIN：把三张表拼起来 =====
SELECT s.name, c.name AS 课程, sc.score, c.teacher
FROM students s
JOIN scores  sc ON sc.student_id = s.id
JOIN courses  c ON c.id = sc.course_id
LIMIT 10;

-- ===== 写 JOIN 的 4 种等价写法（只要会一种就行）=====
SELECT s.name, sc.score FROM students s JOIN scores sc ON sc.student_id = s.id LIMIT 3;
SELECT s.name, sc.score FROM students s, scores sc WHERE sc.student_id = s.id LIMIT 3;
SELECT s.name, sc.score FROM students s
  INNER JOIN scores sc ON sc.student_id = s.id LIMIT 3;
SELECT s.name, sc.score FROM students s
  STRAIGHT_JOIN scores sc ON sc.student_id = s.id LIMIT 3;

-- ===== ★ LEFT JOIN：找出没参加任何考试的学生 =====
-- 注意：本数据集 200 人全都参加了考试，所以结果是 0 行。
-- 教学建议：先 INSERT 一条没有成绩的学生记录再查。
SELECT s.id, s.name
FROM students s
LEFT JOIN scores sc ON sc.student_id = s.id
WHERE sc.id IS NULL;

-- 造一个「没考试的学生」来演示
INSERT INTO students (id, name, gender, class_name, birth_date, city)
VALUES (999, '测试转学生', '男', '软工213班', '2006-05-01', '北京');
SELECT s.id, s.name
FROM students s
LEFT JOIN scores sc ON sc.student_id = s.id
WHERE sc.id IS NULL;                    -- 出现 999 了
DELETE FROM students WHERE id = 999;    -- 清理

-- ===== ★★ LEFT JOIN 的头号坑：ON 和 WHERE 的区别 =====
-- 需求：查所有学生的成绩，但只要及格的
-- 写法 A（正确）：条件写在 ON 里，配不上的行补 NULL，LEFT 语义保留
SELECT s.name, sc.score
FROM students s
LEFT JOIN scores sc ON sc.student_id = s.id AND sc.score >= 60
LIMIT 5;

-- 写法 B（写成了 INNER 的效果）：条件写在 WHERE 里
-- LEFT JOIN 被降级成 INNER JOIN，配不上 60 分的学生被 WHERE 整行删掉
SELECT s.name, sc.score
FROM students s
LEFT JOIN scores sc ON sc.student_id = s.id
WHERE sc.score >= 60
LIMIT 5;

-- ===== ★ 换成 LEFT JOIN + 95 分，ON 和 WHERE 的差别才看得见 =====
-- 60 分这条线上面两条结果一样（本数据集人人有及格成绩，两边都返回 1332 行）
-- 95 分这条线：65 个学生一门 95+ 都没有
-- 写法 A：条件在 ON —— 200 个学生一个不少，配不上的用 NULL 补位
SELECT COUNT(*) AS 行数, SUM(sc.id IS NULL) AS 其中NULL行
FROM students s LEFT JOIN scores sc ON sc.student_id = s.id AND sc.score >= 95;

-- 写法 B：条件在 WHERE —— 这 65 个学生被整个删掉，LEFT 已经退化成 INNER
SELECT COUNT(*) AS 行数
FROM students s LEFT JOIN scores sc ON sc.student_id = s.id
WHERE sc.score >= 95;

-- NULL 补位的行长这样
SELECT s.id, s.name, sc.score
FROM students s LEFT JOIN scores sc ON sc.student_id = s.id AND sc.score >= 95
WHERE sc.id IS NULL LIMIT 3;

-- ===== ★ JOIN 出重复行：一对多 =====
-- 一个订单有 3 条明细，JOIN 后订单出现了 3 次
SELECT o.id, o.amount, COUNT(*) AS 出现次数
FROM orders o JOIN order_items i ON i.order_id = o.id
GROUP BY o.id, o.amount
ORDER BY o.id LIMIT 3;

-- ===== ★★ 由此引出的经典 bug：金额被重复累加 =====
-- 错的：同一个订单的 amount 被算了 3 次
SELECT ROUND(SUM(o.amount), 2) AS 错误总额
FROM orders o JOIN order_items i ON i.order_id = o.id
WHERE o.id <= 100;

-- 对的：订单表本身就有金额，不该去 JOIN 明细再求和
SELECT ROUND(SUM(amount), 2) AS 正确总额 FROM orders WHERE id <= 100;

-- 真的需要「订单 × 明细」的场景，正确写法是先聚合再 JOIN
SELECT o.id, o.amount, t.明细数, t.明细金额
FROM orders o
JOIN (SELECT order_id, COUNT(*) AS 明细数, ROUND(SUM(price*quantity),2) AS 明细金额
      FROM order_items GROUP BY order_id) t ON t.order_id = o.id
WHERE o.id <= 3;

-- ===== 三表 JOIN：订单 → 明细 → 用户 =====
SELECT u.username, o.id AS 订单号, i.product_name, i.quantity
FROM orders o
JOIN users u       ON u.id = o.user_id
JOIN order_items i ON i.order_id = o.id
WHERE o.id = 1;

-- ===== 驱动表：EXPLAIN 里排第一的就是它 =====
EXPLAIN SELECT u.username, o.id AS 订单号, i.product_name, i.quantity
FROM orders o
JOIN users u       ON u.id = o.user_id
JOIN order_items i ON i.order_id = o.id
WHERE o.id = 1;

-- ===== 补充：200 个学生人人有成绩，换张表体会 LEFT JOIN =====
-- 20 门课里有 10 门一个学生都没选过 —— 同一套「左表全留、右表补 NULL」语义
SELECT c.id, c.name, c.teacher
FROM courses c LEFT JOIN scores sc ON sc.course_id = c.id
WHERE sc.id IS NULL;

-- INNER JOIN 写同一件事：10 门没人选的课会无声无息地消失
SELECT COUNT(DISTINCT c.id) AS INNER版只剩这么多门课
FROM courses c JOIN scores sc ON sc.course_id = c.id;
