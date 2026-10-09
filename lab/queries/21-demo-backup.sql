-- 21-demo-backup.sql · 第 21 篇配套实验
--
-- mysqldump 是客户端工具，SQL 文件里调不动它，所以这份实验用纯 SQL
-- 把正文第 4 节的演练走一遍：备份 → 在演练库上删 → 恢复 → 数行数。
-- 「备份」用 CREATE TABLE ... SELECT 完成：mysqldump 导出的东西说白了
-- 就是 CREATE TABLE + INSERT，这里只是把两步合成了一步。
-- 全程只对演练库 easy_mysql_restore 动手，easy_mysql 本体只读不写。

SET NAMES utf8mb4;

-- ============================================================
-- 第一步：备份（把 4 张表拷进演练库）
-- ============================================================
DROP DATABASE IF EXISTS easy_mysql_restore;
CREATE DATABASE easy_mysql_restore CHARACTER SET utf8mb4;

CREATE TABLE easy_mysql_restore.students LIKE easy_mysql.students;
INSERT INTO easy_mysql_restore.students SELECT * FROM easy_mysql.students;

CREATE TABLE easy_mysql_restore.courses LIKE easy_mysql.courses;
INSERT INTO easy_mysql_restore.courses SELECT * FROM easy_mysql.courses;

CREATE TABLE easy_mysql_restore.scores LIKE easy_mysql.scores;
INSERT INTO easy_mysql_restore.scores SELECT * FROM easy_mysql.scores;

CREATE TABLE easy_mysql_restore.users LIKE easy_mysql.users;
INSERT INTO easy_mysql_restore.users SELECT * FROM easy_mysql.users;

SELECT '1_备份之后' AS 阶段,
       (SELECT COUNT(*) FROM easy_mysql_restore.students) AS students,
       (SELECT COUNT(*) FROM easy_mysql_restore.courses) AS courses,
       (SELECT COUNT(*) FROM easy_mysql_restore.scores)  AS scores,
       (SELECT COUNT(*) FROM easy_mysql_restore.users)   AS users;

-- ============================================================
-- 第二步：事故现场（DROP 一张表 + 误删 50 行，只碰演练库）
-- ============================================================
DROP TABLE easy_mysql_restore.scores;
DELETE FROM easy_mysql_restore.students WHERE id <= 50;

SELECT '2_事故之后' AS 阶段,
       (SELECT COUNT(*) FROM easy_mysql_restore.students) AS students,
       (SELECT COUNT(*) FROM easy_mysql_restore.users)    AS users;
-- scores 已经被删掉了，这里数不了它 —— 少一张表就是事故的一部分

-- ============================================================
-- 第三步：恢复（备份文件里有 DROP TABLE + CREATE TABLE + INSERT，
--         所以恢复就是「按备份重来一遍」）
-- ============================================================
DROP TABLE easy_mysql_restore.students;
CREATE TABLE easy_mysql_restore.students LIKE easy_mysql.students;
INSERT INTO easy_mysql_restore.students SELECT * FROM easy_mysql.students;

CREATE TABLE easy_mysql_restore.scores LIKE easy_mysql.scores;
INSERT INTO easy_mysql_restore.scores SELECT * FROM easy_mysql.scores;

SELECT '3_恢复之后' AS 阶段,
       (SELECT COUNT(*) FROM easy_mysql_restore.students) AS students,
       (SELECT COUNT(*) FROM easy_mysql_restore.courses)  AS courses,
       (SELECT COUNT(*) FROM easy_mysql_restore.scores)   AS scores,
       (SELECT COUNT(*) FROM easy_mysql_restore.users)    AS users;

-- ============================================================
-- 第四步：收尾，演练库删干净，再确认本体一行没动
-- ============================================================
DROP DATABASE easy_mysql_restore;

SELECT '4_收尾' AS 阶段,
       (SELECT COUNT(*) FROM information_schema.TABLES
         WHERE TABLE_SCHEMA = 'easy_mysql_restore') AS 演练库残留表数,
       (SELECT COUNT(*) FROM easy_mysql.students)   AS students,
       (SELECT COUNT(*) FROM easy_mysql.courses)    AS courses,
       (SELECT COUNT(*) FROM easy_mysql.scores)     AS scores,
       (SELECT COUNT(*) FROM easy_mysql.users)      AS users;
