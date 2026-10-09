-- 11-demo-constraints.sql · 第 11 篇配套实验
--
-- ⚠ 本文件有且只有 1 条故意写错的语句：最后一句（分数超范围 1500）。
--   故意的错误会让 source 停在那一句，所以它必须放在最后，
--   前面的建表、实验、清理才能全部执行完。
--   其余几条「被拦截」的报错原文（1048 / 1062 / 3819 / 1452 / 1451）
--   在文章正文里逐条给出，放这里会把文件提前中断。

SET NAMES utf8mb4;

USE easy_mysql;

-- ===== 1. 约束长在建表语句里：一眼看全 =====
SHOW CREATE TABLE scores\G

-- 五种约束对应的信息（NOT NULL / DEFAULT 那两列）
SELECT COLUMN_NAME, IS_NULLABLE, COLUMN_DEFAULT, DATA_TYPE, EXTRA
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = 'easy_mysql' AND TABLE_NAME = 'students'
ORDER BY ORDINAL_POSITION;

-- ===== 2. 基线数据本身是干净的：同一学生同一门课只有一条成绩 =====
SELECT COUNT(*) AS 成绩行数,
       COUNT(DISTINCT CONCAT(student_id, '-', course_id)) AS 不同学生课程组合
FROM scores;
SELECT student_id, course_id, COUNT(*) AS 次数
FROM scores GROUP BY student_id, course_id HAVING COUNT(*) > 1;   -- 0 行

-- ===== 3. CHECK 约束：加进来，看一眼，再摘掉 =====
ALTER TABLE scores ADD CONSTRAINT chk_score_range CHECK (score BETWEEN 0 AND 100);
SHOW CREATE TABLE scores\G
ALTER TABLE scores DROP CHECK chk_score_range;

-- ===== 4. 没有外键的对照表：99999 想写就写（演示完就删干净）=====
CREATE TABLE t_orphan_demo (
  id         INT NOT NULL AUTO_INCREMENT,
  student_id INT NOT NULL COMMENT '没有外键，学生不存在也进得来',
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='演示：没有外键的表';
INSERT INTO t_orphan_demo (student_id) VALUES (99999);
SELECT id, student_id, 'students 里根本没有这个学生' AS 说明 FROM t_orphan_demo;
DELETE FROM t_orphan_demo;

-- ===== 5. 外键的三种删除行为（自建三张表）=====
CREATE TABLE t_dept_demo (
  id    INT NOT NULL,
  dname VARCHAR(20) NOT NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='部门';
CREATE TABLE t_emp_cascade (
  id      INT NOT NULL,
  ename   VARCHAR(20) NOT NULL,
  dept_id INT NULL,
  PRIMARY KEY (id),
  KEY idx_dept (dept_id),
  CONSTRAINT fk_emp_cascade FOREIGN KEY (dept_id) REFERENCES t_dept_demo (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='删部门 → 员工连带删';
CREATE TABLE t_emp_setnull (
  id      INT NOT NULL,
  ename   VARCHAR(20) NOT NULL,
  dept_id INT NULL,
  PRIMARY KEY (id),
  KEY idx_dept (dept_id),
  CONSTRAINT fk_emp_setnull FOREIGN KEY (dept_id) REFERENCES t_dept_demo (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='删部门 → 员工部门变 NULL';
CREATE TABLE t_emp_restrict (
  id      INT NOT NULL,
  ename   VARCHAR(20) NOT NULL,
  dept_id INT NOT NULL,
  PRIMARY KEY (id),
  KEY idx_dept (dept_id),
  CONSTRAINT fk_emp_restrict FOREIGN KEY (dept_id) REFERENCES t_dept_demo (id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='部门还有人 → 不许删';
INSERT INTO t_dept_demo VALUES (1,'研发部'),(2,'测试部'),(3,'运维部');
INSERT INTO t_emp_cascade  VALUES (101,'张三',1);
INSERT INTO t_emp_setnull  VALUES (201,'王五',2);
INSERT INTO t_emp_restrict VALUES (301,'孙七',3);
SELECT '初始状态' AS 阶段, 'cascade' AS 表, id, ename, dept_id FROM t_emp_cascade
UNION ALL SELECT '初始状态', 'setnull',  id, ename, dept_id FROM t_emp_setnull
UNION ALL SELECT '初始状态', 'restrict', id, ename, dept_id FROM t_emp_restrict;

-- CASCADE：删掉研发部，张三跟着走
DELETE FROM t_dept_demo WHERE id = 1;
SELECT 'CASCADE 删完' AS 阶段, COUNT(*) AS 剩余员工 FROM t_emp_cascade;
-- SET NULL：删掉测试部，王五的部门变成 NULL
DELETE FROM t_dept_demo WHERE id = 2;
SELECT 'SET NULL 删完' AS 阶段, id, ename, IFNULL(dept_id, 'NULL') AS dept_id FROM t_emp_setnull;
-- RESTRICT：删运维部会报 ERROR 1451（正文里单独跑），约束在这里看得见
SELECT 'RESTRICT 还没删' AS 阶段, id, ename, dept_id FROM t_emp_restrict;

-- ===== 6. 主键怎么选：自增、UUID、业务号 =====
-- 自增主键（本仓库所有表都这么干）：8 字节以内、连续、索引最省
-- UUID：全局唯一但无序，插入会在索引里到处跳页；要用就存 BINARY(16)
SELECT UUID() AS uuid例子, LENGTH(UUID()) AS 字符串形式字节数;
SELECT HEX(UUID_TO_BIN(UUID())) AS 转二进制看十六进制, LENGTH(UUID_TO_BIN(UUID())) AS 二进制字节数;
-- 雪花 ID：趋势递增的 64 位整数，自己生成，适合分库分表
-- 自然主键：拿业务字段当主键（比如邮箱），除非它永远不变，否则别赌

-- ===== 7. UNIQUE 允许几条 NULL？三条都进得去 =====
CREATE TEMPORARY TABLE t_uk_null (
  id    INT NOT NULL PRIMARY KEY,
  email VARCHAR(60) NULL,
  UNIQUE KEY uk_email (email)
);
INSERT INTO t_uk_null VALUES (1, NULL), (2, NULL), (3, NULL);
SELECT id, IFNULL(email, 'NULL') AS email FROM t_uk_null;
DROP TEMPORARY TABLE t_uk_null;
-- （重复邮箱那条会报 ERROR 1062，报错原文在正文里）

-- ===== 8. DEFAULT 与 ON UPDATE CURRENT_TIMESTAMP =====
CREATE TEMPORARY TABLE t_default_demo (
  id         INT NOT NULL AUTO_INCREMENT,
  name       VARCHAR(20) NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  is_deleted TINYINT   NOT NULL DEFAULT 0,
  PRIMARY KEY (id)
);
INSERT INTO t_default_demo (name) VALUES ('第一版');
SELECT id, name, created_at, updated_at, is_deleted FROM t_default_demo;
DO SLEEP(1);
UPDATE t_default_demo SET name = '第二版' WHERE id = 1;
SELECT id, name, created_at, updated_at, is_deleted FROM t_default_demo;
DROP TEMPORARY TABLE t_default_demo;

-- ===== 9. 外键不是白用的：每插一行都要回父表查一次 =====
-- 注意两点：
--   1. sid 必须和 students.id 一样是 UNSIGNED，否则外键建不起来（ERROR 1215）
--   2. 临时表不能建外键，所以 t_fk 是普通表，量完就删
CREATE TEMPORARY TABLE t_nofk (
  id  INT NOT NULL PRIMARY KEY,
  sid INT UNSIGNED NOT NULL,
  KEY idx_sid (sid)
);
CREATE TABLE t_fk (
  id  INT NOT NULL PRIMARY KEY,
  sid INT UNSIGNED NOT NULL,
  KEY idx_sid (sid),
  CONSTRAINT fk_speed FOREIGN KEY (sid) REFERENCES students (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='演示：有外键的对照表';
SET @t0 = NOW(6);
INSERT INTO t_nofk SELECT a.id*1000 + b.id, 1 + (a.id*1000 + b.id) MOD 200 FROM students a JOIN students b;
SET @t1 = NOW(6);
INSERT INTO t_fk    SELECT a.id*1000 + b.id, 1 + (a.id*1000 + b.id) MOD 200 FROM students a JOIN students b;
SET @t2 = NOW(6);
SELECT COUNT(*) AS 插入行数 FROM t_nofk;
SELECT ROUND(TIMESTAMPDIFF(MICROSECOND, @t0, @t1) / 1000) AS 无外键毫秒,
       ROUND(TIMESTAMPDIFF(MICROSECOND, @t1, @t2) / 1000) AS 有外键毫秒;
DROP TABLE t_fk;
DROP TEMPORARY TABLE t_nofk;

-- ===== 10. 收尾：自建的演示表全部删干净 =====
DROP TABLE t_orphan_demo, t_dept_demo, t_emp_cascade, t_emp_setnull, t_emp_restrict;
SHOW TABLES;

-- ===== ★ 故意写错（本文件唯一一条 ERROR）：分数超范围 =====
-- score 是 DECIMAL(5,2)，最大 999.99，1500 直接被拦
INSERT INTO scores (student_id, course_id, score, exam_date)
VALUES (1, 1, 1500, '2025-06-20');
