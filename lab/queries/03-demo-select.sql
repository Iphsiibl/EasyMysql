-- 03-demo-select.sql · 第 03 篇配套实验

SET NAMES utf8mb4;

-- 用法：在命令行执行  docker exec -i easy-mysql mysql -uroot -peasy123 -t --default-character-set=utf8mb4 < queries/03-demo-select.sql
--       或把整个文件拖进 Adminer / Navicat 的查询窗口

USE easy_mysql;

-- 【1】查全部（200 行 7 列，屏幕上会很难看）
SELECT * FROM students;

-- 【2】只看前 10 行
SELECT * FROM students LIMIT 10;

-- 【3】只要两列
SELECT name, city FROM students LIMIT 10;

-- 【4】用 AS 改个名字看
SELECT name AS 姓名, city AS 城市, birth_date AS 出生日期
FROM students LIMIT 5;

-- 【5】按出生日期倒序，看最新的 5 个
SELECT name, birth_date FROM students ORDER BY birth_date DESC LIMIT 5;

-- 【6】按城市分组排序（用到了后面才讲的 GROUP BY，先看效果）
SELECT city, COUNT(*) AS 人数 FROM students GROUP BY city ORDER BY 人数 DESC;

-- 【7】多列排序：先按城市，同城再按 id
SELECT name, city, id FROM students ORDER BY city, id LIMIT 12;
