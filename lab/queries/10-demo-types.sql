-- 10-demo-types.sql · 第 10 篇配套实验（反面教材实锤）
--
-- ⚠ 本文件有且只有 1 条故意写错的语句：最后一句（想把 price 列事后改成 DECIMAL）。
--   故意的错误会让 source 停在那一句，所以它必须放在最后，
--   前面的实验和清理才能全部执行完。

SET NAMES utf8mb4;

USE easy_mysql;

-- ===== 1. 先看清这张丑表 =====
DESC bad_design_demo;
SELECT * FROM bad_design_demo LIMIT 5;
-- VARCHAR(200) 里的 200 数的是「字符」不是「字节」：utf8mb4 下一个汉字吃 4 个字节
SELECT CHAR_LENGTH('张三吃饱了') AS 字符数, LENGTH('张三吃饱了') AS 字节数;

-- ===== 罪证 1：生日是字符串，排序按字典序走 =====
-- 基线数据是脚本生成的，格式统一，先看一眼（这时候还看不出问题）
SELECT user_name, birthday FROM bad_design_demo ORDER BY birthday LIMIT 5;
-- 混进一条 Excel 导出的不补零日期，排序立刻乱：1 月 1 日出生的排到了最后
CREATE TEMPORARY TABLE t_date_sort (
  user_name VARCHAR(20) NOT NULL,
  birthday  VARCHAR(20) NOT NULL
);
INSERT INTO t_date_sort VALUES
  ('张三','2005-09-18'), ('李四','2005-1-1'),
  ('王五','2005-02-11'), ('刘六','2005-7-15');
SELECT user_name, birthday FROM t_date_sort ORDER BY birthday;
DROP TEMPORARY TABLE t_date_sort;
-- 同样四条数据换成 DATE 列，顺序就对了（顺便被规整成补零格式）
CREATE TEMPORARY TABLE t_date_sort_ok (
  user_name VARCHAR(20) NOT NULL,
  birthday  DATE        NOT NULL
);
INSERT INTO t_date_sort_ok VALUES
  ('张三','2005-09-18'), ('李四','2005-1-1'),
  ('王五','2005-02-11'), ('刘六','2005-7-15');
SELECT user_name, birthday FROM t_date_sort_ok ORDER BY birthday;
DROP TEMPORARY TABLE t_date_sort_ok;
-- 对照：students.birth_date 是 DATE，200 个不同生日排序一次到位
SELECT name, birth_date FROM students ORDER BY birth_date LIMIT 5;

-- ===== 罪证 2：金额是字符串，求和靠猜 =====
SELECT SUM(price) FROM bad_design_demo;
SHOW WARNINGS;   -- 20 条 Truncated incorrect DOUBLE value
-- 单位和千分位更狠：不报错，结果直接是错的（3 vs 2001）
CREATE TEMPORARY TABLE t_money (
  label VARCHAR(10) NOT NULL,
  price VARCHAR(20) NOT NULL
);
INSERT INTO t_money VALUES ('A','1,999.00元'), ('B','2.00元');
SELECT SUM(price) AS 字符串直接求和,
       SUM(CAST(REPLACE(REPLACE(price,'元',''),',','') AS DECIMAL(10,2))) AS 清洗后再求和
FROM t_money;
SHOW WARNINGS;
DROP TEMPORARY TABLE t_money;
-- 对照：DECIMAL 列求和，一次到位
SELECT ROUND(SUM(amount), 2) AS 订单总额 FROM orders;

-- ===== 罪证 3：浮点数不能存钱 =====
-- MySQL 把 0.1 / 0.2 当精确小数，直接写看不出误差，必须显式转成 DOUBLE
SELECT 0.1 + 0.2 = 0.3 AS 字面量直接比,
       CAST(0.1 AS DOUBLE) + CAST(0.2 AS DOUBLE) AS DOUBLE相加,
       CAST(0.1 AS DOUBLE) + CAST(0.2 AS DOUBLE) = 0.3 AS DOUBLE比,
       CAST(0.1 AS DECIMAL(10,2)) + CAST(0.2 AS DECIMAL(10,2)) = 0.3 AS DECIMAL比;
-- 真正用 FLOAT 列存钱的样子
CREATE TEMPORARY TABLE t_float (price FLOAT NOT NULL);
INSERT INTO t_float VALUES (0.1), (0.2);
SELECT SUM(price) AS FLOAT列求和, SUM(price) = 0.3 AS `等于0.3吗` FROM t_float;
DROP TEMPORARY TABLE t_float;

-- ===== 罪证 4：手机号是数值，前导 0 和精度都保不住 =====
CREATE TEMPORARY TABLE t_phone (
  phone DOUBLE NOT NULL,
  note  VARCHAR(30) NOT NULL
);
INSERT INTO t_phone VALUES ('01381234567', '前导 0 写进 DOUBLE');
SELECT phone, CAST(phone AS UNSIGNED) AS 读回来的样子 FROM t_phone;
DROP TEMPORARY TABLE t_phone;
-- 19 位数字：存进去和读回来已经不是一个数
SELECT 1381234567890123456 AS 原始号码,
       CAST(1381234567890123456 AS DOUBLE) AS 存进DOUBLE,
       CAST(CAST(1381234567890123456 AS DOUBLE) AS UNSIGNED) AS 读回来,
       CAST(CAST(1381234567890123456 AS DOUBLE) AS UNSIGNED) = 1381234567890123456 AS 读回来还一样吗;
-- 换成 BIGINT 也一样：前导 0 直接没了
SELECT CAST('01381234567' AS UNSIGNED) AS BIGINT结果;

-- ===== 罪证 5：布尔值用字符串，数值上下文里 'false' 就是 0 =====
SELECT 'false' + 0 AS 加法里是几,
       'false' = 0 AS 等于0吗,
       'false' = 1 AS 等于1吗;
SELECT COUNT(*) AS 用is_man等于0来找 FROM bad_design_demo WHERE is_man = 0;
SELECT COUNT(*) AS 用is_man等于否来找 FROM bad_design_demo WHERE is_man = '否';
SELECT COUNT(*) AS 用is_man等于false来找 FROM bad_design_demo WHERE is_man = 'false';

-- ===== 罪证 6：字符串时间做不了范围查询 =====
SELECT COUNT(*) AS 字符串表LIKE出的2024年 FROM bad_design_demo WHERE create_time LIKE '2024%';
SELECT COUNT(*) AS 日期列范围查出的 FROM orders
WHERE created_at >= '2024-01-01' AND created_at < '2025-01-01';

-- ===== 日期三兄弟：DATE / DATETIME / TIMESTAMP =====
CREATE TEMPORARY TABLE t_dates (
  id INT NOT NULL,
  d  DATE NULL,
  dt DATETIME NULL,
  ts TIMESTAMP NULL,
  PRIMARY KEY (id)
);
SET time_zone = '+00:00';
INSERT INTO t_dates (id, d, dt, ts) VALUES (1, '2025-06-01', '2025-06-01 13:00:00', '2025-06-01 13:00:00');
SELECT '+00:00 会话里读' AS 会话时区, d, dt, ts FROM t_dates;
SET time_zone = '+08:00';
SELECT '+08:00 会话里读' AS 会话时区, d, dt, ts FROM t_dates;
INSERT INTO t_dates (id, d, dt, ts) VALUES (2, '9999-12-31', '9999-12-31 23:59:59', NULL);
SELECT 'DATETIME 撑到 9999' AS 提示, id, d, dt, ts FROM t_dates WHERE id = 2;
SET time_zone = SYSTEM;
DROP TEMPORARY TABLE t_dates;
-- 2038 边界那条（TIMESTAMP 越界报错）在正文里单独跑，放这儿会中断文件

-- ===== ENUM / SET =====
SELECT status, COUNT(*) AS 单数 FROM orders GROUP BY status;   -- ENUM 的真实用法
CREATE TEMPORARY TABLE t_enum_set (
  gender ENUM('男','女') NOT NULL,
  hobbies SET('篮球','唱歌','游戏') NOT NULL
);
INSERT INTO t_enum_set VALUES ('女','篮球,游戏'), ('男','篮球');
SELECT gender, hobbies, gender = '女' AS 是女吗,
       FIND_IN_SET('唱歌', hobbies) > 0 AS 喜欢唱歌吗,
       gender + 0 AS 内部序号
FROM t_enum_set ORDER BY gender;
DROP TEMPORARY TABLE t_enum_set;

-- ===== NULL 与空字符串不是一回事 =====
CREATE TEMPORARY TABLE t_null_demo (
  id     INT NOT NULL,
  remark VARCHAR(50) NULL,
  PRIMARY KEY (id)
);
INSERT INTO t_null_demo VALUES (1, ''), (2, NULL), (3, '写了内容');
SELECT id, remark, remark IS NULL AS 是NULL吗, remark = '' AS 等于空串吗 FROM t_null_demo;
SELECT COUNT(*) AS 用空串条件找到的 FROM t_null_demo WHERE remark = '';
SELECT COUNT(*) AS 用IS_NULL找到的 FROM t_null_demo WHERE remark IS NULL;
SELECT NULL = '' AS NULL等于空串吗, COALESCE(NULL,'x') AS A, COALESCE('','x') AS B;
DROP TEMPORARY TABLE t_null_demo;

-- ===== JSON：能用，但不是「不想设计表」的借口 =====
SELECT user_name, extra,
       JSON_EXTRACT(extra, '$.source') AS 来源,
       JSON_UNQUOTE(JSON_EXTRACT(extra, '$.source')) AS 来源文本
FROM bad_design_demo LIMIT 3;
SELECT user_name, extra ->> '$.source' AS 箭头写法
FROM bad_design_demo WHERE JSON_EXTRACT(extra, '$.vip') = 1 LIMIT 3;

-- ===== ★ 动手改造：把 8 个字段改对 =====
CREATE TABLE good_design_demo (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_name   VARCHAR(30)   NOT NULL COMMENT '名字不需要 200 字符',
  birthday    DATE          NOT NULL COMMENT '日期用 DATE',
  phone       VARCHAR(20)   NOT NULL COMMENT '手机号是字符串：有前导 0、有 +86',
  price       DECIMAL(10,2) NOT NULL COMMENT '金额用 DECIMAL',
  is_man      TINYINT(1)    NOT NULL COMMENT '布尔用 TINYINT：1 是 0 否',
  create_time DATETIME      NOT NULL COMMENT '时间用 DATETIME',
  extra       JSON          NULL     COMMENT 'JSON 可以用，但别当万能口袋',
  remark      TEXT          NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_phone (phone)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='正面教材';
DESC good_design_demo;
INSERT INTO good_design_demo (user_name, birthday, phone, price, is_man, create_time)
SELECT LEFT(user_name, 10),
       STR_TO_DATE(birthday, '%Y-%m-%d'),
       CAST(phone AS CHAR),
       CAST(REPLACE(price, '元', '') AS DECIMAL(10,2)),
       is_man = '是',
       STR_TO_DATE(create_time, '%Y-%m-%d %H:%i:%s')
FROM bad_design_demo;
SELECT * FROM good_design_demo LIMIT 5;
SELECT user_name, birthday FROM good_design_demo ORDER BY birthday LIMIT 5;
DROP TABLE good_design_demo;

-- ===== ★ 故意写错（本文件唯一一条 ERROR）：事后想把列改成 DECIMAL =====
-- '1.99元' 转不成 DECIMAL，严格模式直接拒绝；DDL 原子回滚，表结构原封不动
ALTER TABLE bad_design_demo MODIFY price DECIMAL(10,2) NOT NULL;
