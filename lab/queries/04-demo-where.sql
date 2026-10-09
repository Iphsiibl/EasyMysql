-- =============================================================================
-- 04-demo-where.sql · 第 04 篇配套实验
--
-- 对应 docs/04-where-filter.md 的 6 个小节，可以按小节分段跑。
-- 全文件只读（最后一段"造一个 NULL"自己插、自己删，结尾会恢复 20 行）。
-- 数据是固定的（造数据用 CRC32，不用 RAND），你的数字一定和注释里的一样。
-- =============================================================================

SET NAMES utf8mb4;


USE easy_mysql;

-- =============================================================================
-- 第 1 节：最常见的三个比较 = > <
-- =============================================================================
SELECT name, city FROM students WHERE city = '北京' ORDER BY id LIMIT 5;

SELECT COUNT(*) AS 等于北京     FROM students WHERE city = '北京';              -- 33
SELECT COUNT(*) AS 2006之后出生 FROM students WHERE birth_date > '2006-01-01'; -- 78
SELECT COUNT(*) AS 最早那天之前 FROM students WHERE birth_date < '2005-09-02'; -- 0（最早出生的是 2005-09-02）
SELECT COUNT(*) AS 不是211班    FROM students WHERE class_name <> '软工211班';  -- 150（<> 和 != 一个意思）

-- =============================================================================
-- 第 2 节：★ 括号陷阱 —— AND 先算，OR 后算
-- =============================================================================
-- 你以为"男生、211 班、北京"三个条件都要满足？先看看这三个数：
SELECT
  (SELECT COUNT(*) FROM students WHERE gender='男' AND class_name='软工211班') AS 男生且211班,
  (SELECT COUNT(*) FROM students WHERE city='北京')                             AS 北京,
  (SELECT COUNT(*) FROM students WHERE gender='男' AND class_name='软工211班' AND city='北京') AS 三个都要;
-- 25 / 33 / 8

-- 无括号：数据库读作 (男 且 211班) 或 北京 → 并集 25+33-8 = 50，不是 8
SELECT COUNT(*) AS 无括号 FROM students
WHERE gender='男' AND class_name='软工211班' OR city='北京';                    -- 50

-- 加括号：男 且 (211班 或 北京)
SELECT COUNT(*) AS 加括号 FROM students
WHERE gender='男' AND (class_name='软工211班' OR city='北京');                  -- 50
-- 也是 50，纯属巧合：北京的 33 人全是男生（下一句自查）
SELECT gender, COUNT(*) AS n FROM students WHERE city='北京' GROUP BY gender;  -- 只有一行：男 33

-- 把北京换成上海，括号的效果立刻现形（上海 34 人全是女生）
SELECT COUNT(*) AS 无括号_上海 FROM students
WHERE gender='男' AND class_name='软工211班' OR city='上海';                    -- 59
SELECT COUNT(*) AS 加括号_上海 FROM students
WHERE gender='男' AND (class_name='软工211班' OR city='上海');                  -- 25
-- 结论：有 AND 又有 OR，就把意图用括号写明白

-- 练习 2：北京或上海的男学生
SELECT name, city, gender FROM students
WHERE city IN ('北京', '上海') AND gender = '男'
ORDER BY city, name LIMIT 10;                                                   -- 全是北京的

-- =============================================================================
-- 第 3 节：LIKE —— % 是"任意多个字符"，_ 是"正好一个字符"
-- =============================================================================
SELECT name FROM students WHERE name LIKE '王%' ORDER BY name;                 -- 20 个姓王的
SELECT name, city FROM students WHERE name LIKE '%伟%' ORDER BY name;          -- 10 个，"伟"在任意位置
SELECT name FROM students WHERE name LIKE '%伟' ORDER BY name;                 -- 10 个，名字以伟结尾

SELECT name FROM students WHERE name LIKE '赵%伟' ORDER BY name;               -- 赵伟（% 可以是 0 个字符）
SELECT COUNT(*) AS 赵_伟 FROM students WHERE name LIKE '赵_伟';                 -- 0（_ 必须正好占 1 个字符）
SELECT name FROM students WHERE name LIKE '赵__' ORDER BY name;                -- 4 个（赵 + 恰好 2 个字）

SELECT COUNT(*) AS 王加一个字  FROM students WHERE name LIKE '王_';              -- 16（"王"+恰好 1 个字）
SELECT name FROM students WHERE name LIKE '王__%' ORDER BY name;               -- 4 个：姓王且名字至少 2 个字
SELECT name, birth_date FROM students
WHERE birth_date > '2005-09-01' ORDER BY birth_date LIMIT 10;                  -- 练习 3

-- =============================================================================
-- 第 4 节：IN 与 BETWEEN —— 闭区间、顺序别写反
-- =============================================================================
SELECT name, city FROM students WHERE city IN ('北京', '上海') ORDER BY city, name LIMIT 6;
SELECT COUNT(*) AS 三城 FROM students WHERE city IN ('北京', '上海', '深圳');    -- 100

-- 大纲里那句区间太宽：出生日期最早 2005-09-02、最晚 2006-03-20，200 人全中
SELECT COUNT(*) AS 大纲区间 FROM students WHERE birth_date BETWEEN '2005-09-01' AND '2006-09-01';  -- 200
-- 换个窄区间，并验证两端都算（闭区间）
SELECT COUNT(*) AS 十月 FROM students WHERE birth_date BETWEEN '2005-10-01' AND '2005-10-31';      -- 31
SELECT COUNT(*) AS 单日 FROM students WHERE birth_date BETWEEN '2005-10-01' AND '2005-10-01';      -- 1
-- 顺序写反：不报错，安静地给你 0 行
SELECT COUNT(*) AS 写反 FROM students WHERE birth_date BETWEEN '2006-09-01' AND '2005-09-01';      -- 0

-- 练习：圣诞到元旦之间出生的
SELECT name, birth_date FROM students
WHERE birth_date BETWEEN '2005-12-25' AND '2006-01-05' ORDER BY birth_date;    -- 12 人

-- =============================================================================
-- 第 5 节：★ NULL 陷阱 —— = NULL 永远查不出东西
-- =============================================================================
-- 大纲里那句会报错（order_items 表根本没有 remark 列），错误原文：
--   ERROR 1054 (42S22): Unknown column 'remark' in 'where clause'
-- SELECT * FROM order_items WHERE remark IS NULL;

-- 全库只有这两列允许 NULL
SELECT TABLE_NAME, COLUMN_NAME FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = 'easy_mysql' AND IS_NULLABLE = 'YES'
ORDER BY TABLE_NAME, ORDINAL_POSITION;
-- bad_design_demo.extra / bad_design_demo.remark

-- "允许 NULL" ≠ "现在有 NULL"：这 20 行的 remark 都填了值
SELECT COUNT(*) AS remark为空的 FROM bad_design_demo WHERE remark IS NULL;      -- 0

-- 就地造一个 NULL（不碰任何表），看两种写法的差别
SELECT COUNT(*) AS 用IS_NULL FROM (SELECT NULL AS n) t WHERE t.n IS NULL;      -- 1
SELECT COUNT(*) AS 用等号    FROM (SELECT NULL AS n) t WHERE t.n = NULL;       -- 0
SELECT NULL = NULL AS 等号结果, NULL IS NULL AS IS结果;                        -- NULL / 1

SELECT COUNT(*) AS students用等号 FROM students WHERE city = NULL;             -- 0
SELECT COUNT(*) AS students用IS   FROM students WHERE city IS NULL;            -- 0（本表恰好没有 NULL 行）

-- 练习 6：亲手插一行 NULL，跑完自己清理
SELECT user_name, remark FROM bad_design_demo WHERE remark IS NULL;            -- 0 行
INSERT INTO bad_design_demo (user_name, birthday, phone, price, is_man, create_time, remark)
VALUES ('测试NULL', '2005-01-01', 13800000000, '1.00', '是', '2024-01-01 10:00:00', NULL);
SELECT id, user_name, remark FROM bad_design_demo WHERE remark IS NULL;        -- 1 行，查到了
SELECT id, user_name, remark FROM bad_design_demo WHERE remark = NULL;         -- 0 行，还是查不到
DELETE FROM bad_design_demo WHERE remark IS NULL;                              -- 清理

-- =============================================================================
-- 第 6 节：实战 —— 北京或上海、2006 年前出生、名字里带"伟"的男生
--   一条写不完就分四步，每步看一眼还剩多少人
-- =============================================================================
SELECT COUNT(*) AS 1京沪     FROM students WHERE city IN ('北京', '上海');                                -- 67
SELECT COUNT(*) AS 2再减2006 FROM students WHERE city IN ('北京', '上海') AND birth_date < '2006-01-01';  -- 41
SELECT COUNT(*) AS 3再减带伟 FROM students WHERE city IN ('北京', '上海') AND birth_date < '2006-01-01'
                                                                AND name LIKE '%伟%';                     -- 3
SELECT COUNT(*) AS 4再减男生 FROM students WHERE city IN ('北京', '上海') AND birth_date < '2006-01-01'
                                                                AND name LIKE '%伟%' AND gender = '男';   -- 0

-- 第四步之前那 3 个人（性别全是"女"，所以加了 gender='男' 就是 0 行）
SELECT name, city, birth_date, gender FROM students
WHERE city IN ('北京', '上海') AND birth_date < '2006-01-01' AND name LIKE '%伟%'
ORDER BY name;

-- =============================================================================
-- 常用条件速查
-- =============================================================================
SELECT '比较运算符' AS 类别;
SELECT name, birth_date FROM students WHERE birth_date BETWEEN '2005-09-01' AND '2006-09-01' LIMIT 5;
SELECT name, class_name FROM students WHERE class_name <> '软工211班' LIMIT 5;
SELECT name FROM students WHERE name NOT LIKE '王%' LIMIT 5;

-- =============================================================================
-- 收尾自检：确认实验没留下痕迹
-- =============================================================================
SELECT 'students' AS check_item, COUNT(*) AS 应为 FROM students
UNION ALL SELECT 'bad_design_demo', COUNT(*) FROM bad_design_demo
UNION ALL SELECT 'order_items',     COUNT(*) FROM order_items;
-- 期望：200 / 20 / 600000
