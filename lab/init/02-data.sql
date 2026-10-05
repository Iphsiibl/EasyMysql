-- =============================================================================
-- 02-data.sql  造数据脚本
--
-- 设计原则：
--   1) 用递归 CTE 批量生成，几秒钟出几十万行，不依赖外部数据文件
--   2) 全部用 CRC32() 算「伪随机」——同一台机器跑出来的数据完全一致，
--      你在本地看到的输出和教程里贴的一模一样，方便对照
--   3) 故意让 20% 的订单集中在 3 个用户身上，制造热点数据
--
-- ★ SET NAMES utf8mb4 见 01-schema.sql 里的说明，不能删
-- =============================================================================

SET NAMES utf8mb4;

USE easy_mysql;

-- 递归 CTE 默认最多 1000 层，这里放开（只影响当前会话）
SET SESSION cte_max_recursion_depth = 1000000;

-- -----------------------------------------------------------------------------
-- 1. 课程 20 门
-- -----------------------------------------------------------------------------
INSERT INTO courses (id, name, credit, teacher)
VALUES
  (1,  '高等数学',     5.0, '张伟'),
  (2,  '大学英语',     4.0, '李静'),
  (3,  '数据结构',     4.0, '王强'),
  (4,  '计算机网络',   3.0, '刘敏'),
  (5,  '操作系统',     4.0, '陈磊'),
  (6,  '数据库原理',   3.5, '杨洋'),
  (7,  'Java 程序设计',4.0, '黄娟'),
  (8,  'Python 入门',  2.0, '周涛'),
  (9,  '算法设计与分析',3.5, '吴军'),
  (10, '软件工程',     3.0, '徐明'),
  (11, '计算机组成原理',4.5, '胡超'),
  (12, '数字逻辑',     3.0, '朱琳'),
  (13, '概率论与数理统计',3.5, '高翔'),
  (14, '线性代数',     3.5, '林峰'),
  (15, '大学物理',     4.0, '何洁'),
  (16, '马克思主义原理',2.0, '罗宇'),
  (17, '中国近现代史纲要',2.0, '梁爽'),
  (18, '体育',         1.0, '宋丹'),
  (19, '音乐鉴赏',     1.0, '谢婷'),
  (20, '机器学习导论', 3.0, '韩雪');

-- -----------------------------------------------------------------------------
-- 2. 学生 200 人
--    10 个姓 × 20 个名 = 200 个不重复组合，靠 (n-1) 的除法和取模算出来
-- -----------------------------------------------------------------------------
INSERT INTO students (id, name, gender, class_name, birth_date, city)
WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 200)
SELECT
  n,
  CONCAT(
    ELT(1 + (n - 1) DIV 20, '赵','钱','孙','李','周','吴','郑','王','冯','陈'),
    ELT(1 + (n - 1) MOD 20, '伟','芳','娜','秀英','敏','静','丽','强磊','洋','艳',
                          '勇','军杰','娟','涛','明超','霞','平','刚','桂','英')
  ),
  ELT(1 + n MOD 2, '男', '女'),
  CONCAT('软工', 210 + (n - 1) DIV 50, '班'),
  DATE_ADD('2005-09-01', INTERVAL n MOD 700 DAY),
  ELT(1 + n MOD 6, '北京', '上海', '广州', '深圳', '杭州', '成都')
FROM seq;

-- -----------------------------------------------------------------------------
-- 3. 成绩 2000 行 = 200 个学生 × 每人 10 门课
--    (n-1) DIV 10 得到学生，(n-1) MOD 10 得到课程，保证每组不重复
-- -----------------------------------------------------------------------------
INSERT INTO scores (student_id, course_id, score, exam_date)
WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 2000)
SELECT
  1 + (n - 1) DIV 10,
  1 + (n - 1) MOD 10,
  40 + CRC32(CONCAT('score', n)) MOD 61,          -- 40~100
  DATE_ADD('2025-06-20', INTERVAL (n MOD 7) - 3 DAY)
FROM seq;

-- -----------------------------------------------------------------------------
-- 4. 用户 5000 人
-- -----------------------------------------------------------------------------
INSERT INTO users (id, username, email, city, age, status, balance, created_at)
WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 5000)
SELECT
  n,
  CONCAT('user_', LPAD(n, 5, '0')),
  CONCAT('user', n, '@example.com'),
  ELT(1 + CRC32(CONCAT('city', n)) MOD 6, '北京', '上海', '广州', '深圳', '杭州', '成都'),
  18 + CRC32(CONCAT('age', n)) MOD 25,             -- 18~42
  IF(CRC32(CONCAT('st', n)) MOD 10 < 8, 1, 0),    -- 80% 正常
  ROUND(CRC32(CONCAT('bal', n)) MOD 1000000 / 100, 2),
  DATE_ADD('2023-01-01 08:00:00', INTERVAL CRC32(CONCAT('ct', n)) MOD 600 DAY)
FROM seq;

-- -----------------------------------------------------------------------------
-- 5. 订单 20 万行（同时灌进 orders 和对照表 orders_slow）
--    每 5 单里有 1 单属于 1~3 号「超级大客户」，制造数据倾斜
-- -----------------------------------------------------------------------------
INSERT INTO orders (user_id, product_id, quantity, amount, status, created_at, updated_at)
WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 200000)
SELECT
  IF(n MOD 5 = 0, 1 + n MOD 3, 1 + CRC32(CONCAT('u', n)) MOD 5000),
  1 + CRC32(CONCAT('p', n)) MOD 1000,
  1 + CRC32(CONCAT('q', n)) MOD 5,
  ROUND((1 + CRC32(CONCAT('q', n)) MOD 5) * (9.9 + CRC32(CONCAT('up', n)) MOD 200000 / 100), 2),
  ELT(1 + CRC32(CONCAT('s', n)) MOD 4, 'created', 'paid', 'shipped', 'cancelled'),
  DATE_ADD(DATE_ADD('2024-01-01 00:00:00', INTERVAL n MOD 365 DAY), INTERVAL n MOD 86400 SECOND),
  DATE_ADD(DATE_ADD('2024-01-01 00:00:00', INTERVAL n MOD 365 DAY), INTERVAL (n MOD 86400) + 3600 SECOND)
FROM seq;

INSERT INTO orders_slow (user_id, product_id, quantity, amount, status, created_at, updated_at)
WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 200000)
SELECT
  IF(n MOD 5 = 0, 1 + n MOD 3, 1 + CRC32(CONCAT('u', n)) MOD 5000),
  1 + CRC32(CONCAT('p', n)) MOD 1000,
  1 + CRC32(CONCAT('q', n)) MOD 5,
  ROUND((1 + CRC32(CONCAT('q', n)) MOD 5) * (9.9 + CRC32(CONCAT('up', n)) MOD 200000 / 100), 2),
  ELT(1 + CRC32(CONCAT('s', n)) MOD 4, 'created', 'paid', 'shipped', 'cancelled'),
  DATE_ADD(DATE_ADD('2024-01-01 00:00:00', INTERVAL n MOD 365 DAY), INTERVAL n MOD 86400 SECOND),
  DATE_ADD(DATE_ADD('2024-01-01 00:00:00', INTERVAL n MOD 365 DAY), INTERVAL (n MOD 86400) + 3600 SECOND)
FROM seq;

-- -----------------------------------------------------------------------------
-- 6. 订单明细 60 万行 = 每单 3 条
-- -----------------------------------------------------------------------------
INSERT INTO order_items (order_id, product_name, price, quantity)
WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 600000)
SELECT
  1 + (n - 1) MOD 200000,
  ELT(1 + n MOD 50,
      '机械键盘','人体工学椅','显示器','笔记本电脑','鼠标','耳机','摄像头','麦克风',
      '硬盘','内存条','显卡','主板','电源','机箱','散热器','路由器','交换机','网线',
      '数据线','充电宝','耳机套','鼠标垫','屏幕贴膜','支架','理线器','转换器',
      '优盘','读卡器','摄像头支架','键盘手托','脚垫','书架','台灯','插线板',
      '洗衣液','纸巾','水杯','饭盒','保温杯','雨伞','口罩','手套','围巾','帽子',
      -- ↑ 到这里正好 50 个，索引是 1 + n MOD 50，改列表长度必须同步改 MOD
      '手机壳','笔记本包','小风扇','折叠桌','文件柜','手机支架'),
  ROUND(1 + CRC32(CONCAT('pr', n)) MOD 99999 / 100, 2),
  1 + CRC32(CONCAT('iq', n)) MOD 5
FROM seq;

-- -----------------------------------------------------------------------------
-- 7. 反面教材 20 行
-- -----------------------------------------------------------------------------
INSERT INTO bad_design_demo
  (user_name, birthday, phone, price, is_man, create_time, extra, remark)
WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 20)
SELECT
  CONCAT(ELT(1 + n MOD 10, '赵','钱','孙','李','周','吴','郑','王','冯','陈'), '小', n),
  CONCAT('2005-0', 1 + n MOD 9, '-1', n MOD 9),                    -- 字符串日期
  CAST(13800000000 + n * 1000 AS DOUBLE),                          -- 数值手机号
  CONCAT(n, '.99元'),                                              -- 字符串金额
  ELT(1 + n MOD 2, '是', '否'),                                    -- 字符串布尔
  CONCAT('2024-01-0', 1 + n MOD 9, ' 10:00:00'),                   -- 字符串时间
  JSON_OBJECT('vip', IF(n MOD 3 = 0, 1, 0), 'source', ELT(1 + n MOD 4, 'app', 'web', 'mini', 'pc')),
  '教学用反面教材'
FROM seq;

-- -----------------------------------------------------------------------------
-- 8. 数据量自检：对照 README 里的「数据规模表」应该完全一致
-- -----------------------------------------------------------------------------
SELECT 'students'    AS 表名, COUNT(*) AS 行数 FROM students
UNION ALL SELECT 'courses',       COUNT(*) FROM courses
UNION ALL SELECT 'scores',        COUNT(*) FROM scores
UNION ALL SELECT 'users',         COUNT(*) FROM users
UNION ALL SELECT 'orders',        COUNT(*) FROM orders
UNION ALL SELECT 'orders_slow',   COUNT(*) FROM orders_slow
UNION ALL SELECT 'order_items',   COUNT(*) FROM order_items
UNION ALL SELECT 'bad_design_demo', COUNT(*) FROM bad_design_demo;
