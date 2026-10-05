-- 11-demo-constraints.sql · 第 11 篇配套实验

SET NAMES utf8mb4;

-- ⚠ 本文件包含【故意的错误语句】，用来演示数据库如何拦住脏数据。
--   mysql 客户端遇到错误会停止，所以请分条执行，或加 --force 参数：
--   docker exec -i easy-mysql mysql -uroot -peasy123 -t --force < queries/11-demo-constraints.sql

USE easy_mysql;

-- ===== 先看约束长什么样 =====
SHOW CREATE TABLE scores\G

-- ===== 罪证 1：分数可以是 1500 =====
INSERT INTO scores (student_id, course_id, score, exam_date)
VALUES (1, 1, 1500, '2025-06-20');
-- ERROR 1264 (22003): Out of range value for column 'score' at row 1
-- 兜底：score 是 DECIMAL(5,2)，最大 999.99
DELETE FROM scores WHERE score > 999;   -- 保险起见清一下

-- ===== 加上 CHECK 约束，再试一次 =====
ALTER TABLE scores DROP CHECK chk_score_range;
ALTER TABLE scores ADD CONSTRAINT chk_score_range CHECK (score BETWEEN 0 AND 100);

INSERT INTO scores (student_id, course_id, score, exam_date)
VALUES (1, 1, 1500, '2025-06-20');
-- ERROR 3819 (HY000): Check constraint 'chk_score_range' is violated.

-- 注意：MySQL 8.0.16 之前 CHECK 只被解析不生效。查一下当前版本
SELECT VERSION();

-- ===== 罪证 2：可以给同一个学生同一门课插两条成绩 =====
INSERT INTO scores (student_id, course_id, score, exam_date)
VALUES (1, 1, 88, '2025-06-20');
-- ERROR 1062 (23000): Duplicate entry '1-1' for key 'scores.uk_scores_student_course'
-- 这就是 UNIQUE KEY uk_scores_student_course 的作用

-- ===== 罪证 3：可以给不存在的学生记成绩 =====
-- scores.student_id 上有外键，所以这条会被拦住
INSERT INTO scores (student_id, course_id, score, exam_date)
VALUES (99999, 1, 90, '2025-06-20');
-- ERROR 1452 (23000): Cannot add or update a child row: a foreign key constraint fails
-- 对照实验：临时删掉外键再试
ALTER TABLE scores DROP FOREIGN KEY fk_scores_student;
INSERT INTO scores (student_id, course_id, score, exam_date)
VALUES (99999, 1, 90, '2025-06-20');   -- 这次成功了，脏数据进来了
SELECT * FROM scores WHERE student_id = 99999;   -- 亲眼看看
DELETE FROM scores WHERE student_id = 99999;
ALTER TABLE scores ADD CONSTRAINT fk_scores_student
  FOREIGN KEY (student_id) REFERENCES students (id);
-- ★ 讨论：外键挡住了脏数据，也带来了写入开销和锁。大表常常靠应用层保证

-- ===== 外键的三种删除行为 =====
-- 先造一个测试学生
INSERT INTO students (id, name, gender, class_name, birth_date, city)
VALUES (998, '待删除的学生', '男', '软工213班', '2006-01-01', '北京');
INSERT INTO scores (student_id, course_id, score, exam_date) VALUES (998, 1, 88, '2025-06-20');

-- RESTRICT（默认）：有成绩就不许删
DELETE FROM students WHERE id = 998;
-- ERROR 1451 (23000): Cannot delete or update a parent row: a foreign key constraint fails

-- 体验 CASCADE：连带把成绩一起删
ALTER TABLE scores DROP FOREIGN KEY fk_scores_student;
ALTER TABLE scores ADD CONSTRAINT fk_scores_student
  FOREIGN KEY (student_id) REFERENCES students (id) ON DELETE CASCADE;
DELETE FROM students WHERE id = 998;   -- 成功，成绩也跟着没了
SELECT COUNT(*) AS 残留成绩 FROM scores WHERE student_id = 998;   -- 0

-- 还原
ALTER TABLE scores DROP FOREIGN KEY fk_scores_student;
ALTER TABLE scores ADD CONSTRAINT fk_scores_student
  FOREIGN KEY (student_id) REFERENCES students (id);

-- ===== 恢复原状 =====
ALTER TABLE scores DROP CHECK chk_score_range;
