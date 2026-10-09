-- 18-demo-transaction.sql · 第 18 篇配套实验

SET NAMES utf8mb4;

-- ⚠ 事务是「连接级别」的：所有语句必须在同一个客户端窗口里按顺序执行。
--   命令行 `source` 执行本文件时全程保持同一会话，交互式逐条粘贴也没问题。

USE easy_mysql;

-- 每个场景都从这个起点出发、回到这个起点
SELECT id, username, balance FROM users WHERE id IN (1, 2);

-- ============================================================
-- 场景 1：★ 没有事务的事故：钱只扣了一半
--   autocommit = 1（默认）时，每条 UPDATE 自己就是一个事务，立刻落盘
-- ============================================================
UPDATE users SET balance = balance - 100 WHERE id = 1;
-- ⚠ 程序在这里崩了（断网 / 进程被杀），下面这条加钱的语句永远没执行
SELECT id, username, balance FROM users WHERE id IN (1, 2);
-- 1 号白扣 100，2 号一分没多 —— 这就是「没有事务」的下场
UPDATE users SET balance = balance + 100 WHERE id = 1;   -- 手动补救
SELECT id, username, balance FROM users WHERE id IN (1, 2);

-- ============================================================
-- 场景 2：加上事务，中途放弃 → 数据完好无损（本篇核心）
-- ============================================================
START TRANSACTION;
UPDATE users SET balance = balance - 100 WHERE id = 1;
UPDATE users SET balance = balance + 100 WHERE id = 2;
SELECT id, username, balance FROM users WHERE id IN (1, 2);   -- 事务内的中间态
ROLLBACK;                      -- ★ 假装程序崩了，回滚
SELECT id, username, balance FROM users WHERE id IN (1, 2);   -- 和起点一模一样

-- ============================================================
-- 场景 3：转账成功 → COMMIT（落盘生效，再做一笔反向转账抵消）
-- ============================================================
START TRANSACTION;
UPDATE users SET balance = balance - 100 WHERE id = 1;
UPDATE users SET balance = balance + 100 WHERE id = 2;
COMMIT;                        -- ★ 落盘生效
SELECT id, username, balance FROM users WHERE id IN (1, 2);   -- 确实变了
-- 为了保持数据集干净，做一笔方向相反的转账把它抵消掉
START TRANSACTION;
UPDATE users SET balance = balance + 100 WHERE id = 1;
UPDATE users SET balance = balance - 100 WHERE id = 2;
COMMIT;
SELECT id, username, balance FROM users WHERE id IN (1, 2);   -- 回到起点

-- ============================================================
-- 场景 4：SAVEPOINT 部分回滚 —— 只撤销一部分
-- ============================================================
SELECT balance AS 扣款前 FROM users WHERE id = 1;

START TRANSACTION;
UPDATE users SET balance = balance - 50 WHERE id = 1;
SAVEPOINT s1;                    -- ★ 存档点 1
UPDATE users SET balance = balance - 50 WHERE id = 1;
SAVEPOINT s2;                    -- ★ 存档点 2
UPDATE users SET balance = balance - 50 WHERE id = 1;
SELECT balance AS 扣了三次后 FROM users WHERE id = 1;

ROLLBACK TO s1;                  -- ★ 只回滚到存档点 1，第一次的 -50 保留
SELECT balance AS 回滚到s1后 FROM users WHERE id = 1;
COMMIT;
SELECT balance AS 最终 FROM users WHERE id = 1;

UPDATE users SET balance = balance + 50 WHERE id = 1;   -- 还原
SELECT balance AS 还原后 FROM users WHERE id = 1;

-- ============================================================
-- 场景 5：把业务条件写进 SQL —— 余额不足时整笔转账不发生
-- ============================================================
SELECT balance AS 2号余额 FROM users WHERE id = 2;

START TRANSACTION;
UPDATE users SET balance = balance - 999999 WHERE id = 2
  AND balance >= 999999;          -- ★ 把条件写进 SQL，天然安全
SET @deduct = ROW_COUNT();        -- 0 行，说明余额不够
SELECT @deduct AS 扣款行数;

UPDATE users SET balance = balance + 999999 WHERE id = 1
  AND @deduct = 1;                -- 扣款没成功，收款也不许发生
SELECT ROW_COUNT() AS 收款行数;
COMMIT;
SELECT id, username, balance FROM users WHERE id IN (1, 2);
-- 分文未动：1 号没多钱，因为 2 号扣款根本没发生

-- ============================================================
-- 场景 6：autocommit 开关 —— 关掉了要记得改回来
-- ============================================================
SELECT @@autocommit AS 默认自动提交;

-- autocommit = 1：每条语句自己就是事务，ROLLBACK 撤不掉它
UPDATE users SET balance = balance + 100 WHERE id = 1;
ROLLBACK;
SELECT balance AS ROLLBACK之后 FROM users WHERE id = 1;      -- 撤不掉了
UPDATE users SET balance = balance - 100 WHERE id = 1;       -- 补救
SELECT balance AS 补救之后 FROM users WHERE id = 1;

-- autocommit = 0：语句不再自动提交，ROLLBACK 生效
SET autocommit = 0;
SELECT @@autocommit AS 关掉以后;
UPDATE users SET balance = balance + 100 WHERE id = 1;
ROLLBACK;
SELECT balance AS ROLLBACK之后2 FROM users WHERE id = 1;     -- 回滚生效
SET autocommit = 1;                                          -- ★ 改回来
SELECT @@autocommit AS 改回来;
SELECT balance AS 最终 FROM users WHERE id = 1;

-- ============================================================
-- 场景 7：★ 故意写错的语句（全文件唯一一条错误语句）
--   报错不会替你回滚事务：事务还开着，钱还扣着，必须自己 ROLLBACK
-- ★ 两种执行方式都能保证数据干净：
--   · 交互式逐条执行：客户端继续往下跑，你看到现场后执行 ROLLBACK
--   · `source` 整体执行：客户端在这里中断，连接断开，服务器替你回滚
-- ============================================================
START TRANSACTION;
UPDATE users SET balance = balance - 100 WHERE id = 1;
UPDATE users SET balance = balanc - 100 WHERE id = 2;   -- 列名拼错
-- ERROR 1054 (42S22): Unknown column 'balanc' in 'field list'
SELECT id, username, balance FROM users WHERE id IN (1, 2);
-- 报错之后事务并没有自动回滚：1 号还扣着 100
ROLLBACK;
SELECT id, username, balance FROM users WHERE id IN (1, 2);
-- 回到起点

-- 收尾自检：5000 行、余额总和 25114527.71
SELECT COUNT(*) AS 行数, SUM(balance) AS 余额总和 FROM users;
