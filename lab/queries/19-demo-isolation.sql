-- 19-demo-isolation.sql · 第 19 篇配套实验

SET NAMES utf8mb4;

--
-- ★ 本文件必须【开两个客户端窗口】对照执行，标了「窗口 1」「窗口 2」
--   开两个方法：
--   1. 命令行：两个终端都执行
--        docker exec -it easy-mysql mysql -uroot -peasy123 -t
--   2. 图形界面：Adminer 打开两个浏览器标签页（http://localhost:8080）
--
-- ⚠ 事务是连接级别的，所以必须开两个窗口，一个窗口看不到另一个窗口的未提交数据。
-- ⚠ 实验用 orders 表，每次实验前请先跑一次「还原数据」。

-- ============================================================
-- 0. 还原数据
-- ============================================================
USE easy_mysql;
SELECT id, user_id, amount, status FROM orders WHERE id = 1;

-- ============================================================
-- 实验 1：脏读（Dirty Read）
--   读到了别人「还没提交」的数据
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
--   SELECT amount FROM orders WHERE id = 1;      -- 看到 99999 了！
--   -- 这个数据随时可能被回滚，你却拿它做了决策
--   ROLLBACK;
--
-- 【窗口 1】ROLLBACK;  -- 刚才窗口2 看到的 99999 从来没真正存在过
--
-- 【窗口 2】再查一次 → 金额变回原值
--   SELECT amount FROM orders WHERE id = 1;

-- ============================================================
-- 实验 2：不可重复读（Non-repeatable Read）
--   同一个事务里读两次同一行，结果不一样
-- ============================================================
-- 【窗口 1】
--   SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
--   START TRANSACTION;
--   SELECT amount FROM orders WHERE id = 1;   -- 第一次读，记下金额
--   -- 切到窗口 2 操作并提交，再切回来
--
-- 【窗口 2】
--   SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
--   UPDATE orders SET amount = 88888 WHERE id = 1;
--   COMMIT;
--
-- 【窗口 1】
--   SELECT amount FROM orders WHERE id = 1;   -- 第二次读，金额变了！
--   ROLLBACK;
--   -- 结论：适合「先查一下，没有就插入」的场景（库存扣减）

-- ============================================================
-- 实验 3：幻读（Phantom Read）
--   同一个事务里两次同样的查询，第二次多出了「凭空出现的行」
-- ============================================================
-- 【窗口 1】
--   SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
--   START TRANSACTION;
--   SELECT COUNT(*) FROM orders WHERE amount BETWEEN 80000 AND 90000;  -- 第一次
--   -- 切到窗口 2
--
-- 【窗口 2】
--   SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
--   INSERT INTO orders (user_id, product_id, quantity, amount, status, created_at, updated_at)
--   VALUES (1, 1, 1, 85000, 'paid', NOW(), NOW());
--   COMMIT;
--
-- 【窗口 1】
--   SELECT COUNT(*) FROM orders WHERE amount BETWEEN 80000 AND 90000;  -- 多了一行！
--   ROLLBACK;

-- ============================================================
-- 实验 4：RR 级别下重复读
--   上面实验 2、3 的两个窗口，都把隔离级别换成 REPEATABLE READ 再做一遍
--   你会发现两次读到的结果一样
--
--   SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
--
--   ★ 但要注意：RR 只保证「快照读」结果一致。
--     下面这句是「当前读」，读的是最新数据，不受快照保护：
--       SELECT amount FROM orders WHERE id = 1 FOR UPDATE;

-- ============================================================
-- 实验 5：MySQL 默认级别
-- ============================================================
SELECT @@transaction_isolation AS 当前级别;
SELECT @@global.transaction_isolation AS 全局默认级别;
-- 默认是 REPEATABLE-READ，这是 MySQL 和 PostgreSQL / Oracle 最大的不同点

-- ============================================================
-- 汇总表（背下来）
-- ============================================================
-- 隔离级别          脏读    不可重复读   幻读
-- READ UNCOMMITTED   可能     可能        可能
-- READ COMMITTED     不会     可能        可能
-- REPEATABLE READ    不会     不会        基本不会（靠间隙锁）
-- SERIALIZABLE       不会     不会        不会（但并发性能极差）
--
-- 怎么选：99% 的业务用 REPEATABLE READ 就够，别改。
-- 需要「读到最新数据」时才用 RC；极罕见的场景才用 SERIALIZABLE。

-- ============================================================
-- 清理
-- ============================================================
DELETE FROM orders WHERE id = 200001;
