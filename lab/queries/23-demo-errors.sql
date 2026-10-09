-- 23-demo-errors.sql · 第 23 篇配套实验
--
-- 这份文件故意触发 11 条报错，每一条都对应正文速查表里的一行。
-- 两种跑法看到的东西不一样：
--   标准输入 + --force（正文第 1 节那条命令）：11 条全打出来，文件跑到底
--   source（配套实验那条命令）：第一条报错就停，后面的语句不再执行
-- 演示表用 CREATE TEMPORARY TABLE 建：会话一关自动消失，
-- 就算执行停在半路，也不会留下任何垃圾。

SET NAMES utf8mb4;

USE easy_mysql;

-- ============================================================
-- 0. 先建一张临时表，插一行正常数据（下面 11 条报错都围绕它）
-- ============================================================
CREATE TEMPORARY TABLE err_probe (
  id    INT UNSIGNED NOT NULL AUTO_INCREMENT,
  code  TINYINT UNSIGNED NOT NULL,     -- 故意用最小的整数类型，好演示溢出
  name  VARCHAR(3) NOT NULL,           -- 故意只给 3 个字符宽
  note  VARCHAR(20) NOT NULL,
  grade ENUM('good','bad') NOT NULL,   -- 枚举只认这两个值
  PRIMARY KEY (id),
  UNIQUE KEY uk_code (code)
) ENGINE=InnoDB;
INSERT INTO err_probe (code, name, note, grade) VALUES (1, 'a', 'x', 'good');
SELECT id, code, name, note, grade FROM err_probe;

-- ============================================================
-- ★ 下面 11 条语句全部故意写错，每条前面的注释说明它演示什么
-- 【错误 1 · 1064 语法错】SQL 里比较相等写 =，== 是 C 系语言的习惯
SELECT * FROM err_probe WHERE code == 1;

-- 【错误 2 · 1054 列名拼错】nam 不是这张表里的列，真列名叫 name
SELECT nam FROM err_probe;

-- 【错误 3 · 1146 表名拼错】order_detail 是想当然的叫法，本库没有这张表
SELECT * FROM order_detail;

-- 【错误 4 · 1049 库名不存在】这个库从来没建过
SELECT * FROM no_such_database.anything;

-- 【错误 5 · 1062 撞唯一键】code=1 已经被插进去了（uk_code）
INSERT INTO err_probe (code, name, note, grade) VALUES (1, 'b', 'y', 'good');

-- 【错误 6 · 1048 非空约束】code 列定义是 NOT NULL，NULL 进不来
INSERT INTO err_probe (code, name, note, grade) VALUES (NULL, 'c', 'z', 'good');

-- 【错误 7 · 1366 类型不匹配】'abc' 塞不进整数列，严格模式直接拒
INSERT INTO err_probe (code, name, note, grade) VALUES ('abc', 'c', 'z', 'good');

-- 【错误 8 · 1264 数值超范围】TINYINT UNSIGNED 最大 255，300 超了
INSERT INTO err_probe (code, name, note, grade) VALUES (300, 'c', 'z', 'good');

-- 【错误 9 · 1406 字符串超长】name 只有 3 个字符宽，'abcdef' 有 6 个
INSERT INTO err_probe (code, name, note, grade) VALUES (2, 'abcdef', 'z', 'good');

-- 【错误 10 · 1265 枚举值不在列表里】grade 只认 good 和 bad
INSERT INTO err_probe (code, name, note, grade) VALUES (3, 'c', 'z', 'excellent');

-- 【错误 11 · 1452 外键】students 表里没有 999999 号学生，子表插不进这条
INSERT INTO scores (student_id, course_id, score, exam_date) VALUES (999999, 1, 88.00, '2026-01-01');

-- ============================================================
-- 收尾：数一遍行数（失败的 INSERT 一条都没进去），再把临时表删掉
-- ============================================================
SELECT COUNT(*) AS 报错之后还剩几行 FROM err_probe;
SELECT (SELECT COUNT(*) FROM students) AS students行数, (SELECT COUNT(*) FROM scores) AS scores行数;
DROP TEMPORARY TABLE err_probe;
SELECT '临时表已清理' AS 收尾;
