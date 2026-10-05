-- 04-demo-where.sql · 第 04 篇配套实验（6 道题 + 答案）

SET NAMES utf8mb4;


USE easy_mysql;

-- ===== 练习 1：查姓王的学生 =====
SELECT name, city FROM students WHERE name LIKE '王%';

-- ===== 练习 2：查北京或上海的男学生 =====
SELECT name, city, gender FROM students
WHERE city IN ('北京', '上海') AND gender = '男';

-- ===== 练习 3：查 2005-09-01 之后出生的 =====
SELECT name, birth_date FROM students WHERE birth_date > '2005-09-01' LIMIT 10;

-- ===== 练习 4：查名字里带「伟」的（任意位置）=====
SELECT name FROM students WHERE name LIKE '%伟%' LIMIT 10;

-- ===== 练习 5：★ 括号陷阱 =====
-- 下面这句有多少人？先自己算，再看结果
--   读作：城市是北京 或者（性别男 且 211班）
SELECT COUNT(*) AS 错误理解的结果 FROM students
WHERE city = '北京' OR gender = '男' AND class_name = '软工211班';

--   正确写法：想表达「北京的男生」
SELECT COUNT(*) AS 正确理解的结果 FROM students
WHERE city = '北京' AND gender = '男';

-- ===== 练习 6：★ NULL 陷阱 =====
-- 两条都执行，对比结果行数
SELECT COUNT(*) AS 用等号的结果 FROM students WHERE city = NULL;      -- 0
SELECT COUNT(*) AS 用_IS_NULL_的结果 FROM students WHERE city IS NULL; -- 0（本表无 NULL）

-- 造一个 NULL 出来看效果
SELECT user_name, remark FROM bad_design_demo WHERE remark IS NULL;  -- 0 行
INSERT INTO bad_design_demo (user_name, birthday, phone, price, is_man, create_time, remark)
VALUES ('测试NULL', '2005-01-01', 13800000000, '1.00', '是', '2024-01-01 10:00:00', NULL);
SELECT id, user_name, remark FROM bad_design_demo WHERE remark IS NULL;  -- 1 行
DELETE FROM bad_design_demo WHERE remark IS NULL;  -- 清理

-- ===== 常用条件速查 =====
SELECT '比较运算符' AS 类别;
SELECT name, birth_date FROM students WHERE birth_date BETWEEN '2005-09-01' AND '2006-09-01' LIMIT 5;
SELECT name, class_name FROM students WHERE class_name <> '软工211班' LIMIT 5;
SELECT name FROM students WHERE name NOT LIKE '王%' LIMIT 5;
