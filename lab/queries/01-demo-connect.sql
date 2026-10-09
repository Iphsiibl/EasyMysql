-- =============================================================================
-- 01-demo-connect.sql · 第 01 篇配套实验
--
-- 对应 docs/01-what-is-mysql.md 的第 4、5 节：连接参数 + 验证连对了。
-- 全是只读语句（SELECT / SHOW），跑多少遍、跑几遍都不会改坏任何东西。
--
-- 用法：
--   docker cp lab/queries/01-demo-connect.sql easy-mysql:/tmp/
--   docker exec easy-mysql mysql -uroot -peasy123 -t --default-character-set=utf8mb4 easy_mysql -e "source /tmp/01-demo-connect.sql"
-- =============================================================================

SET NAMES utf8mb4;

USE easy_mysql;

-- 【1】连上的到底是哪一个服务器 —— 第一个该敲的语句
SELECT VERSION() AS version;

-- 【2】这台服务器上有哪些库
SHOW DATABASES;

-- 【3】端口是谁的端口：服务器进程自己报的（容器里是 3306，宿主机映射成 3307）
SELECT @@port AS port,
       @@character_set_server AS charset_server,
       @@collation_server AS collation_server;

-- 【4】sql_mode：服务器对「不规矩 SQL」的容忍度，第 11、12 篇会再碰到它
SELECT @@sql_mode AS sql_mode;

-- 【5】这台服务器支持哪些存储引擎（InnoDB 是默认那个，第 18 篇讲事务时要用它）
SHOW ENGINES;

-- 【6】数据真的在：students 必须数出 200 行
SELECT COUNT(*) AS students_rows FROM students;
