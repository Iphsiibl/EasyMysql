-- 19-demo-isolation.sql · 第 19 篇配套实验

SET NAMES utf8mb4;

--
-- ★ 本文件的实验必须【开两个客户端窗口】对照执行，步骤里标了「窗口 1」「窗口 2」
--   开两个窗口的方法（两个终端里各执行一遍）：
--        docker exec -it easy-mysql mysql -uroot -peasy123 -t --default-character-set=utf8mb4 easy_mysql
--   图形界面也可以：Adminer 开两个浏览器标签页（http://localhost:8080）
--
-- ⚠ 事务是连接级别的：一个窗口看不到另一个窗口的未提交数据，所以必须开两个。
-- ⚠ 文件开头的基线部分、以及最后的「清理」部分可以顺序执行；
--   中间标了窗口的步骤请在两个窗口里手动对照跑。
-- ⚠ 每个实验做完，两个窗口都要 ROLLBACK（或 COMMIT），再做下一个。

USE easy_mysql;

-- ============================================================
-- 0. 基线：1 号订单的金额，每个实验都从它出发
-- ============================================================
SELECT id, user_id, amount, status FROM orders WHERE id = 1;

-- ============================================================
-- 实验 1：脏读（Dirty Read）—— 读到别人「还没提交」的数据
--   MySQL 默认级别 REPEATABLE READ 下脏读复现不出来，所以两边都要先降级
-- ============================================================
-- 【窗口 1】
--   SET SESSION TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
--   START TRANSACTION;
--   UPDATE orders SET amount = 99999 WHERE id = 1;
--   -- 不提交，停在这里，切到窗口 2
--
-- 【窗口 2】
--   SET SESSION TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
--   START TRANSACTION;
--   SELECT amount FROM orders WHERE id = 1;      -- 看到 99999！这就是脏读
--   ROLLBACK;
--
-- 【窗口 1】ROLLBACK;   -- 窗口 2 刚才看到的 99999 从来没真正存在过
--
-- 【窗口 2】SELECT amount FROM orders WHERE id = 1;   -- 变回 2663.13
--
-- 对照：把两个窗口都换成默认级别 REPEATABLE READ 再做一遍，
--       窗口 2 读到的是 2663.13 —— 脏读在默认级别下出现不了

-- ============================================================
-- 实验 2：不可重复读（Non-repeatable Read）
--   同一个事务里读两次同一行，结果不一样
-- ============================================================
-- 【窗口 1】
--   SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
--   START TRANSACTION;
--   SELECT amount FROM orders WHERE id = 1;      -- 第一次读，2663.13
--   -- 切到窗口 2 操作并提交，再切回来
--
-- 【窗口 2】
--   SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
--   UPDATE orders SET amount = 88888 WHERE id = 1;   -- autocommit 自动提交
--
-- 【窗口 1】
--   SELECT amount FROM orders WHERE id = 1;      -- 第二次读，88888，变了！
--   ROLLBACK;
--
-- 对照：两个窗口都换成 REPEATABLE READ 再做一遍，
--       第二次读还是 2663.13 —— 这就是 MySQL 默认级别「可重复读」的字面意思

-- ============================================================
-- 实验 3：幻读（Phantom Read）
--   同一个事务里两次同样的查询，第二次多出「凭空出现的行」
-- ============================================================
-- 【窗口 1】
--   SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
--   START TRANSACTION;
--   SELECT COUNT(*) FROM orders WHERE amount BETWEEN 80000 AND 90000;  -- 0
--   -- 切到窗口 2
--
-- 【窗口 2】
--   SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
--   INSERT INTO orders (user_id, product_id, quantity, amount, status, created_at, updated_at)
--   VALUES (1, 1, 1, 85000, 'paid', NOW(), NOW());   -- autocommit 自动提交
--
-- 【窗口 1】
--   SELECT COUNT(*) FROM orders WHERE amount BETWEEN 80000 AND 90000;  -- 1，行凭空多出来
--   ROLLBACK;
--
-- 对照：两个窗口都换成 REPEATABLE READ 再做一遍，第二次还是 0

-- ============================================================
-- 实验 4：SERIALIZABLE —— 最高级别，读也会堵写
-- ============================================================
-- 【窗口 1】
--   SET SESSION TRANSACTION ISOLATION LEVEL SERIALIZABLE;
--   START TRANSACTION;
--   SELECT COUNT(*) FROM users WHERE age > 0;    -- 普通读在这里会加共享锁
--   -- 切到窗口 2，等 5 秒再切回来看
--
-- 【窗口 2】
--   UPDATE users SET age = age WHERE id = 1;     -- 卡住！直到窗口 1 COMMIT/ROLLBACK
--
-- 【窗口 1】ROLLBACK;

-- ============================================================
-- 实验 5：看当前级别 + 切换级别
-- ============================================================
SELECT @@transaction_isolation   AS 本会话级别;
SELECT @@global.transaction_isolation AS 全局默认级别;
-- MySQL 8.0 默认 REPEATABLE-READ，这是它和 Oracle / PostgreSQL 默认值的最大区别

SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
SELECT @@transaction_isolation AS 切换后;
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SELECT @@transaction_isolation AS 改回默认;

-- ============================================================
-- 汇总表（背下来）
-- ============================================================
-- 隔离级别          脏读    不可重复读   幻读
-- READ UNCOMMITTED   可能     可能        可能
-- READ COMMITTED     不会     可能        可能
-- REPEATABLE READ    不会     不会        基本不会（靠间隙锁，第 20 篇）
-- SERIALIZABLE       不会     不会        不会（但并发性能极差）
--
-- 怎么选：绝大多数业务用默认的 REPEATABLE READ 就够，别改。
-- 需要「读到最新提交的数据」时才用 RC；极罕见的场景才上 SERIALIZABLE。

-- ============================================================
-- 清理：无论中间实验做到哪一步，跑这里恢复原状
-- ============================================================
-- 两个窗口里如果有没结束的事务，先执行 ROLLBACK;
UPDATE orders SET amount = 2663.13 WHERE id = 1;   -- 实验 2 改过金额
DELETE FROM orders WHERE id > 200000;              -- 实验 3 插入的幻影行
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

SELECT id, user_id, amount FROM orders WHERE id = 1;
SELECT COUNT(*) AS orders行数 FROM orders;
SELECT @@transaction_isolation AS 最终级别;
