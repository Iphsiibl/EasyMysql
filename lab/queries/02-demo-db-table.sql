-- =============================================================================
-- 02-demo-db-table.sql · 第 02 篇配套实验
--
-- 对应 docs/02-db-table-row-column.md 的第 2、4、5 节：
-- 建库 → 建表 → 插数据 → 改表 → 字符集的坑，最后把演示库整个删掉，不留痕迹。
-- 只动自建的 my_school，不碰 easy_mysql 里的八张基线表。
--
-- 用法：
--   docker cp lab/queries/02-demo-db-table.sql easy-mysql:/tmp/
--   docker exec easy-mysql mysql -uroot -peasy123 -t --default-character-set=utf8mb4 easy_mysql -e "source /tmp/02-demo-db-table.sql"
-- =============================================================================

SET NAMES utf8mb4;

-- =====================================================================
-- 【1】建库：utf8mb4 才是该写的那个，别写 utf8（第 6 节解释为什么）
-- =====================================================================
DROP DATABASE IF EXISTS my_school;
CREATE DATABASE my_school DEFAULT CHARSET utf8mb4;
USE my_school;

-- =====================================================================
-- 【2】建第一张表：一列是 id，一列是姓名
-- =====================================================================
CREATE TABLE t_student (
  id   INT UNSIGNED NOT NULL AUTO_INCREMENT,
  name VARCHAR(30)  NOT NULL,
  PRIMARY KEY (id)
);

DESC t_student;

-- =====================================================================
-- 【3】插三行，看看「行」长什么样
-- =====================================================================
INSERT INTO t_student (name) VALUES ('张三'), ('李四'), ('王五');
SELECT * FROM t_student ORDER BY id;

-- =====================================================================
-- 【4】加一列：给个默认值，已有的 3 行就不会报错
-- =====================================================================
ALTER TABLE t_student ADD COLUMN class_name VARCHAR(30) NOT NULL DEFAULT '未分班';
DESC t_student;

-- =====================================================================
-- 【5】改列名：CHANGE 会把类型和约束整段重写一遍
-- =====================================================================
ALTER TABLE t_student CHANGE name student_name VARCHAR(30) NOT NULL;
SELECT id, student_name, class_name FROM t_student ORDER BY id;

-- =====================================================================
-- 【6】删掉重建：数据跟表一起没，这很残酷，但就是这么设计的
-- =====================================================================
DROP TABLE t_student;

CREATE TABLE t_student (
  id           INT UNSIGNED NOT NULL AUTO_INCREMENT,
  student_name VARCHAR(30)  NOT NULL,
  class_name   VARCHAR(30)  NOT NULL DEFAULT '未分班',
  PRIMARY KEY (id)
) DEFAULT CHARSET = utf8mb4;

DESC t_student;

-- =====================================================================
-- 【7】字符集的坑：你写的 utf8，MySQL 8.0 里其实是 utf8mb3
--      utf8mb3 一个字符最多 3 字节，emoji 是 4 字节，存不下。
--      想亲手看报错，把下面这行单独执行（批处理模式遇错即停，所以这里注释掉）：
--
--        INSERT INTO t_emoji (name) VALUES ('😀');
--        ERROR 1366 (HY000): Incorrect string value:
--          '\xF0\x9F\x98\x80' for column 'name' at row 1
-- =====================================================================
CREATE TABLE t_emoji (
  id   INT UNSIGNED NOT NULL AUTO_INCREMENT,
  name VARCHAR(30) NOT NULL,
  PRIMARY KEY (id)
) DEFAULT CHARSET = utf8;

SHOW CREATE TABLE t_emoji\G
-- 输出末行是 DEFAULT CHARSET=utf8mb3：写 utf8，建出来的是 utf8mb3

ALTER TABLE t_emoji MODIFY name VARCHAR(30) CHARACTER SET utf8mb4 NOT NULL;
INSERT INTO t_emoji (name) VALUES ('张三'), ('😀');
SELECT id, name, LENGTH(name) AS bytes, CHAR_LENGTH(name) AS chars FROM t_emoji;
-- 😀 占 4 个字节(bytes=4)、1 个字符(chars=1)：utf8mb4 的 mb = maximum bytes 4

-- =====================================================================
-- 【8】收尾：演示库整个删掉，现场恢复原状
-- =====================================================================
DROP DATABASE IF EXISTS my_school;

SELECT 'my_school_left' AS check_item, COUNT(*) AS should_be_0
FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = 'my_school';
