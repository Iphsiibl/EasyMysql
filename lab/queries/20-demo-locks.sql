-- 20-demo-locks.sql · 第 20 篇配套实验

SET NAMES utf8mb4;

-- ★ 需要【开两个窗口】，标了「窗口 1」「窗口 2」
-- ⚠ 行锁实验请在 users / scores 小表上做，不要在 orders 上做（会拖很久）

USE easy_mysql;

SELECT id, username, balance FROM users WHERE id IN (1, 2, 3);

-- ============================================================
-- 实验 1：写锁互斥（最基础的现象）
-- ============================================================
-- 【窗口 1】
--   START TRANSACTION;
--   SELECT * FROM users WHERE id = 1 FOR UPDATE;   -- 拿到 1 号行的排他锁
--   -- 停在这里
--
-- 【窗口 2】
--   SELECT * FROM users WHERE id = 1;             -- 读操作
--   -- 注意：普通 SELECT 不加锁，不会等（MVCC 读的快照）
--
-- 【窗口 2】换成写操作
--   UPDATE users SET balance = balance + 1 WHERE id = 1;
--   -- 卡住了！一直 Waiting
--
-- 【窗口 1】
--   ROLLBACK;    -- 释放锁
--
-- 【窗口 2】
--   -- 立刻执行成功
--   UPDATE users SET balance = balance + 1 WHERE id = 1;
--   ROLLBACK;

-- ============================================================
-- 实验 2：★ 行锁 vs 表锁 —— UPDATE 忘了加 WHERE 会锁全表
-- ============================================================
-- 【窗口 1】
--   START TRANSACTION;
--   UPDATE users SET balance = balance + 1;      -- ★ 没有 WHERE！
--   -- 整个 users 表被锁住
--
-- 【窗口 2】
--   UPDATE users SET balance = balance + 1 WHERE id = 2;
--   -- 卡住
--
-- 【窗口 1】ROLLBACK;
--
-- 对照实验：加上 WHERE 就只锁一行
-- 【窗口 1】
--   START TRANSACTION;
--   UPDATE users SET balance = balance + 1 WHERE id = 1;
-- 【窗口 2】
--   UPDATE users SET balance = balance + 1 WHERE id = 2;   -- 正常执行，不卡
--
-- ★ 结论：UPDATE / DELETE 永远要带 WHERE，这是铁律

-- ============================================================
-- 实验 3：间隙锁（RR 级别下防止幻读）
-- ============================================================
-- 准备一段连续 id（students 1~10）
SELECT id, name FROM students WHERE id BETWEEN 5 AND 8;
-- CREATE TABLE demo_gap (id INT PRIMARY KEY);
-- 已有 1,2,3,4,6,7 （缺 5）

-- 【窗口 1】RR 级别下锁一个范围，会把「不存在的行」的间隙也锁住
--   SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
--   START TRANSACTION;
--   SELECT * FROM students WHERE id BETWEEN 5 AND 8 FOR UPDATE;
--
-- 【窗口 2】
--   INSERT INTO students (id, name, gender, class_name, birth_date, city)
--   VALUES (5, '插不进去', '男', '软工213班', '2006-01-01', '北京');
--   -- 卡住！因为 5 这个「空隙」被锁了
--   -- 这就是 RR 级别如何避免幻读：靠间隙锁，而不是靠 MVCC
--
-- 【窗口 1】ROLLBACK;
-- 【窗口 2】插入成功

-- ============================================================
-- 实验 4：★ 手动造一个死锁（本篇高潮）
--   死锁四要素：互斥、持有并等待、不可剥夺、循环等待
--   这里靠「加锁顺序不一致」制造循环等待
-- ============================================================
-- 【窗口 1】
--   START TRANSACTION;
--   UPDATE users SET balance = balance - 1 WHERE id = 1;   -- 先锁 1 号
--   -- 停在这里
--
-- 【窗口 2】
--   START TRANSACTION;
--   UPDATE users SET balance = balance - 1 WHERE id = 2;   -- 先锁 2 号
--   -- 停在这里
--
-- 【窗口 1】
--   UPDATE users SET balance = balance - 1 WHERE id = 2;   -- 等 2 号 → 等到了？
--   -- 不会！窗口 2 正拿着 2 号的锁，窗口 1 会一直等
--
-- 【窗口 2】
--   UPDATE users SET balance = balance - 1 WHERE id = 1;   -- ★ 也在等 1 号
--   -- 循环等待 → MySQL 检测到死锁，立刻回滚其中一方
--   -- ERROR 1213 (40001): Deadlock found when trying to get lock;
--   -- try restarting transaction
--
-- 两个窗口都 ROLLBACK; 清理

-- 防止死锁的写法（★ 永远按 id 从小到大加锁）
-- 【窗口 1】
--   START TRANSACTION;
--   UPDATE users SET balance = balance - 1 WHERE id IN (1, 2) ORDER BY id;
--
-- 【窗口 2】
--   START TRANSACTION;
--   UPDATE users SET balance = balance - 1 WHERE id IN (1, 2) ORDER BY id;
--   -- 不会死锁，只会排队

-- ============================================================
-- 实验 5：看锁信息
-- ============================================================
-- 【窗口 1】开一个事务锁住 1 号
--   START TRANSACTION;
--   SELECT * FROM users WHERE id = 1 FOR UPDATE;
--
-- 【窗口 2】另开一个连接查
--   SELECT * FROM performance_schema.data_locks\G
--   SELECT * FROM performance_schema.data_lock_waits\G
--
-- 【窗口 1】ROLLBACK;

-- 查死锁历史（最近一次）
SHOW ENGINE INNODB STATUS\G
-- 找到 LATEST DETECTED DEADLOCK 那一段，能看到两个事务各自持有什么锁、等什么锁

-- 相关系统变量
SELECT @@innodb_lock_wait_timeout AS 锁等待超时秒;    -- 默认 50
SELECT @@innodb_deadlock_detect  AS 是否检测死锁;      -- 默认 ON

-- ============================================================
-- 清理
-- ============================================================
DELETE FROM users WHERE id IN (1, 2, 3) AND balance < 0;
SELECT id, username, balance FROM users WHERE id IN (1, 2, 3);
