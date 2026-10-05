-- 10-demo-types.sql · 第 10 篇配套实验（反面教材实锤）

SET NAMES utf8mb4;


USE easy_mysql;

-- ===== 先看清这张丑表长什么样 =====
DESC bad_design_demo;
SELECT * FROM bad_design_demo LIMIT 5;

-- ===== 罪证 1：字符串日期没法正确排序 =====
-- 生日用 VARCHAR 存，比较是逐字符比的
SELECT user_name, birthday FROM bad_design_demo ORDER BY birthday LIMIT 5;
-- 现在用正确类型（students 表）排序看看
SELECT name, birth_date FROM students ORDER BY birth_date LIMIT 5;

-- ===== 罪证 2：金额用字符串，求和直接报错 =====
SELECT SUM(price) FROM bad_design_demo;
-- 报错：Truncated incorrect DOUBLE value: '1.99元'
-- 想「凑合」算也不行，结果是错的
SELECT SUM(CAST(price AS DECIMAL(10,2))) FROM bad_design_demo;
-- 对照：DECIMAL 类型求和
SELECT ROUND(SUM(amount), 2) FROM orders;

-- ===== 罪证 3：★ 浮点数不能存钱 =====
SELECT 0.1 + 0.2 = 0.3            AS 浮点相等吗,      -- 0，不相等
       0.1 + 0.2                  AS 实际结果,        -- 0.30000000000000004
       CAST(0.1 AS DECIMAL(10,2)) + CAST(0.2 AS DECIMAL(10,2)) = 0.3 AS DECIMAL相等吗;  -- 1

-- ===== 罪证 4：手机号用 DOUBLE，前导 0 和精度都保不住 =====
SELECT 13800000001 AS 应该是整数;
-- DOUBLE 是浮点，只能精确表示约 15~17 位有效数字，超过就不准
SELECT CAST(138123456789012 AS DOUBLE) AS 原值,
       CAST(CAST(138123456789012 AS DOUBLE) AS UNSIGNED) AS 转回来,
       (CAST(138123456789012 AS DOUBLE) = CAST(138123456789012 AS UNSIGNED)) AS 相等吗;  -- 0！

-- ===== 罪证 5：布尔值用字符串，'false' 在 MySQL 里等于 0 =====
SELECT 'false' = 0 AS 字符串false等于0吗,   -- 1（注意：是 0 不是 1！）
       'false' = 1 AS 字符串false等于1吗;   -- 0

-- ===== 罪证 6：字符串时间没法做范围查询 =====
SELECT COUNT(*) AS 2024年的订单数_错误写法 FROM bad_design_demo
WHERE create_time LIKE '2024%';
SELECT COUNT(*) AS 2024年的订单数_正确写法 FROM orders
WHERE created_at >= '2024-01-01' AND created_at < '2025-01-01';

-- ===== ★ 动手改造：建一张正确版本 =====
CREATE DATABASE IF NOT EXISTS good_demo DEFAULT CHARSET utf8mb4;
USE good_demo;
DROP TABLE IF EXISTS good_design_demo;
CREATE TABLE good_design_demo (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_name   VARCHAR(30)   NOT NULL COMMENT '名字不需要 200 字符',
  birthday    DATE          NOT NULL COMMENT '日期用 DATE',
  phone       VARCHAR(20)   NOT NULL COMMENT '手机号是字符串，含前导 0 和 +86',
  price       DECIMAL(10,2) NOT NULL COMMENT '金额用 DECIMAL',
  is_man      TINYINT(1)    NOT NULL COMMENT '布尔用 TINYINT，1/0',
  create_time DATETIME      NOT NULL COMMENT '时间用 DATETIME',
  extra       JSON          NULL     COMMENT 'JSON 可以用，但别当万能口袋',
  remark      TEXT          NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_phone (phone)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='正面教材';

DESC good_design_demo;
-- 把反面教材的数据改对后插进来
INSERT INTO good_design_demo (user_name, birthday, phone, price, is_man, create_time)
SELECT
  LEFT(user_name, 10),
  STR_TO_DATE(birthday, '%Y-%m-%d'),
  CAST(phone AS CHAR),
  CAST(price AS DECIMAL(10,2)),
  is_man = '是',
  STR_TO_DATE(create_time, '%Y-%m-%d %H:%i:%s')
FROM easy_mysql.bad_design_demo;
SELECT * FROM good_design_demo LIMIT 5;

-- 排序正确了吗？
SELECT user_name, birthday FROM good_design_demo ORDER BY birthday LIMIT 5;
USE easy_mysql;
