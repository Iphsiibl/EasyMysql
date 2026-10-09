-- 20-demo-locks.sql · 第 20 篇配套实验

SET NAMES utf8mb4;

-- ★ 需要【开两个客户端窗口】，标了「窗口 1」「窗口 2」（开法见 19 号文件头部）
--   docker exec -it easy-mysql mysql -uroot -peasy123 -t --default-character-set=utf8mb4 easy_mysql
-- ⚠ 行锁实验在 users / scores / demo_gap 这些小表上做，别拿 20 万行的 orders 练手
-- ⚠ 每个实验做完，两个窗口都 ROLLBACK

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
--   SELECT * FROM users WHERE id = 1;             -- 普通读不加锁，立刻返回（MVCC 快照）
--
-- 【窗口 2】换成写操作
--   UPDATE users SET balance = balance + 1 WHERE id = 1;
--   -- 卡住了！用第三个窗口执行下面这句能看到它在等：
--   --   SELECT OBJECT_NAME, LOCK_MODE, LOCK_STATUS, LOCK_DATA
--   --   FROM performance_schema.data_locks WHERE OBJECT_NAME = 'users';
--
-- 【窗口 1】ROLLBACK;    -- 释放锁
-- 【窗口 2】UPDATE 立刻执行成功 → ROLLBACK（别提交，保持数据干净）

-- ============================================================
-- 实验 2：★ 表锁 vs 行锁 —— UPDATE 忘了加 WHERE 会锁全表
--   InnoDB 没有真正的「表锁」，但全表扫描会把每一行都锁上，效果一样
-- ============================================================
EXPLAIN UPDATE users SET balance = balance + 1;                    -- rows ≈ 5070，全表扫
EXPLAIN UPDATE users SET balance = balance + 1 WHERE id = 2;       -- rows = 1，只碰一行

-- 【窗口 1】
--   START TRANSACTION;
--   UPDATE users SET balance = balance + 1;      -- ★ 没有 WHERE！5000 行全被锁住
--   -- 停在这里
--
-- 【窗口 2】
--   UPDATE users SET balance = balance + 1 WHERE id = 2;
--   -- 卡住：明明只改一行，也被别人的大 UPDATE 堵了
--
-- 【窗口 1】ROLLBACK;   -- 【窗口 2】成功后 ROLLBACK
--
-- 对照实验：加上 WHERE 就只锁一行
-- 【窗口 1】START TRANSACTION; UPDATE users SET balance = balance + 1 WHERE id = 1;
-- 【窗口 2】UPDATE users SET balance = balance + 1 WHERE id = 2;   -- 不卡，立刻成功
-- 两个窗口都 ROLLBACK
-- ★ 铁律：UPDATE / DELETE 永远要带 WHERE

-- ============================================================
-- 实验 3：间隙锁（Gap Lock）—— RR 级别下连「不存在的行」都锁住
-- ============================================================
CREATE TABLE demo_gap (id INT PRIMARY KEY) ENGINE=InnoDB;
INSERT INTO demo_gap VALUES (1), (2), (3), (4), (6), (7);   -- 故意缺一个 5
SELECT id FROM demo_gap ORDER BY id;

-- 【窗口 1】
--   SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
--   START TRANSACTION;
--   SELECT id FROM demo_gap WHERE id BETWEEN 3 AND 6 FOR UPDATE;   -- 锁住 3、4、6 和它们之间的空隙
--   -- 停在这里
--
-- 【窗口 2】
--   INSERT INTO demo_gap VALUES (5);       -- 卡住！5 这个「空隙」被锁了
--   -- 这就是 RR 靠间隙锁抑制幻读的原理（第 19 篇实验 3 的对照）
--
-- 【窗口 1】ROLLBACK;   -- 【窗口 2】插入成功 → DELETE FROM demo_gap WHERE id = 5;

DROP TABLE demo_gap;

-- ============================================================
-- 实验 4：★ 手动造一个死锁（本篇高潮）
--   加锁顺序不一致 → 循环等待 → InnoDB 检测到后回滚其中一个
-- ============================================================
-- 【窗口 1】
--   START TRANSACTION;
--   UPDATE users SET balance = balance - 1 WHERE id = 1;   -- 先锁 1 号
--   SELECT SLEEP(4);                                       -- 等一下，让窗口 2 先动手
--   UPDATE users SET balance = balance - 1 WHERE id = 2;   -- 再要 2 号 → 循环等待
--   -- ERROR 1213 (40001): Deadlock found when trying to get lock;
--   -- try restarting transaction
--
-- 【窗口 2】（在窗口 1 SLEEP 期间执行）
--   START TRANSACTION;
--   UPDATE users SET balance = balance - 1 WHERE id = 2;   -- 先锁 2 号
--   UPDATE users SET balance = balance - 1 WHERE id = 1;   -- 再要 1 号
--
-- ★ 抓死锁报告（任意窗口，越快越好）：
SHOW ENGINE INNODB STATUS\G
-- 找 LATEST DETECTED DEADLOCK 那一段：
-- 事务 (1) 持有 id=2 在等 id=1，事务 (2) 持有 id=1 在等 id=2，
-- 最后 *** WE ROLL BACK TRANSACTION (2) 说明 (2) 是被牺牲的那个
-- 两个窗口都 ROLLBACK

-- ★ 预防死锁的写法：所有事务按同一顺序（id 从小到大）加锁
-- 【窗口 1】START TRANSACTION; UPDATE users SET balance = balance - 1 WHERE id IN (1, 2) ORDER BY id;
-- 【窗口 2】START TRANSACTION; UPDATE users SET balance = balance - 1 WHERE id IN (1, 2) ORDER BY id;
--          -- 不会死锁，只会排队，两个窗口都 ROLLBACK

-- ============================================================
-- 实验 5：锁等待超时 innodb_lock_wait_timeout（默认 50 秒）
-- ============================================================
-- 【窗口 1】开事务锁住 3 号：
--   START TRANSACTION;
--   SELECT * FROM users WHERE id = 3 FOR UPDATE;
--   SELECT SLEEP(10);
--   ROLLBACK;
--
-- 【窗口 2】把超时调小，再去抢：
--   SET SESSION innodb_lock_wait_timeout = 3;
--   UPDATE users SET balance = balance + 1 WHERE id = 3;
--   -- ERROR 1205 (HY000): Lock wait timeout exceeded; try restarting transaction
--   -- 超时只是「等腻了」，不是死锁；事务还活着，要自己 ROLLBACK
--   ROLLBACK;
--   SET SESSION innodb_lock_wait_timeout = 50;   -- ★ 改回默认

-- ============================================================
-- 实验 6：看锁（哪个会话在等谁）
-- ============================================================
-- 【窗口 1】开一个事务锁住 1 号：
--   START TRANSACTION;
--   SELECT * FROM users WHERE id = 1 FOR UPDATE;
--
-- 【窗口 2】另开一个连接查：
--   SELECT OBJECT_SCHEMA, OBJECT_NAME, INDEX_NAME, LOCK_TYPE, LOCK_MODE, LOCK_STATUS, LOCK_DATA
--   FROM performance_schema.data_locks WHERE OBJECT_NAME = 'users';
--   SELECT * FROM performance_schema.data_lock_waits\G
--   -- LOCK_MODE 是 X,REC_NOT_GAP = 记录锁；X = Next-Key Lock（含间隙）
-- 【窗口 1】ROLLBACK;

-- 相关系统变量
SELECT @@innodb_lock_wait_timeout  AS 锁等待超时秒;    -- 默认 50
SELECT @@innodb_deadlock_detect    AS 是否自动检测死锁; -- 默认 ON
SELECT @@transaction_isolation     AS 当前隔离级别;     -- 默认 REPEATABLE-READ

-- ============================================================
-- 清理：无论实验做到哪一步，跑这里恢复原状
-- ============================================================
-- 两个窗口里如果有没结束的事务，先执行 ROLLBACK;
DROP TABLE IF EXISTS demo_gap;
SET SESSION innodb_lock_wait_timeout = 50;

SELECT id, username, balance FROM users WHERE id IN (1, 2, 3);
SELECT COUNT(*) AS users行数, SUM(balance) AS 余额总和 FROM users;
SELECT COUNT(*) AS demo_gap还存在吗
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'easy_mysql' AND TABLE_NAME = 'demo_gap';
