-- 18-demo-transaction.sql · 第 18 篇配套实验

SET NAMES utf8mb4;

-- ⚠ 事务相关的语句请在同一个客户端会话里按顺序执行，
--   因为事务是「连接级别」的。命令行执行本文件时会保持同一会话，没问题。

USE easy_mysql;

-- 先看看 1 号和 2 号用户的余额
SELECT id, username, balance FROM users WHERE id IN (1, 2);

-- ============================================================
-- 场景 1：转账失败，钱白扣了（没有事务的恐怖）
-- ============================================================
UPDATE users SET balance = balance - 100 WHERE id = 1;
-- 模拟程序在这里崩了、网络断了
UPDATE users SET balance = balance + 100 WHERE id = 2;
SELECT id, username, balance FROM users WHERE id IN (1, 2);
-- 忘了改回来？手动还原：
UPDATE users SET balance = balance + 100 WHERE id = 1;
UPDATE users SET balance = balance - 100 WHERE id = 2;

-- ============================================================
-- 场景 2：加上事务，中途放弃 → 数据完好无损
-- ============================================================
START TRANSACTION;
UPDATE users SET balance = balance - 100 WHERE id = 1;
UPDATE users SET balance = balance + 100 WHERE id = 2;
SELECT id, username, balance FROM users WHERE id IN (1, 2);
-- 此刻查一下 1 号余额，确认变了
ROLLBACK;                      -- ★ 假装程序崩了，回滚
SELECT id, username, balance FROM users WHERE id IN (1, 2);
-- 余额和一开始一模一样

-- ============================================================
-- 场景 3：转账成功 → COMMIT
-- ============================================================
START TRANSACTION;
UPDATE users SET balance = balance - 100 WHERE id = 1;
UPDATE users SET balance = balance + 100 WHERE id = 2;
COMMIT;                        -- ★ 落盘生效
SELECT id, username, balance FROM users WHERE id IN (1, 2);
-- 余额确实变了。为了保持数据集干净，还原一下：
START TRANSACTION;
UPDATE users SET balance = balance + 100 WHERE id = 1;
UPDATE users SET balance = balance - 100 WHERE id = 2;
COMMIT;

-- ============================================================
-- 场景 4：★ 故意犯错的语句会自动回滚
-- ============================================================
START TRANSACTION;
UPDATE users SET balance = balance - 100 WHERE id = 1;
UPDATE users SET balance = balanc - 100 WHERE id = 2;   -- 列名拼错
-- ERROR 1054 (42S22): Unknown column 'balanc'
SELECT balance FROM users WHERE id = 1;
-- 余额没变！因为那条错误语句导致整个事务被回滚了
SELECT @@autocommit AS 自动提交;   -- 应该是 1

-- ============================================================
-- 场景 5：SAVEPOINT 部分回滚
-- ============================================================
SELECT balance AS 起点 FROM users WHERE id = 1;

START TRANSACTION;
UPDATE users SET balance = balance - 50 WHERE id = 1;
SAVEPOINT s1;
UPDATE users SET balance = balance - 50 WHERE id = 1;
SAVEPOINT s2;
UPDATE users SET balance = balance - 50 WHERE id = 1;
SELECT balance AS 扣了三次后 FROM users WHERE id = 1;

ROLLBACK TO s1;                 -- ★ 只回滚到第一个存档点
SELECT balance AS 回滚到s1 FROM users WHERE id = 1;
COMMIT;
SELECT balance AS 最终 FROM users WHERE id = 1;

-- 还原
START TRANSACTION;
UPDATE users SET balance = balance + 50 WHERE id = 1;
COMMIT;

-- ============================================================
-- 场景 6：★ 最重要 —— 事务必须是「全有或全无」
-- 正确写法：先检查，条件不满足就主动回滚
-- ============================================================
SELECT balance AS 2号余额 FROM users WHERE id = 2;

START TRANSACTION;
-- 业务判断：余额够吗？
UPDATE users SET balance = balance - 999999 WHERE id = 2
  AND balance >= 999999;                 -- ★ 把条件写进 SQL，天然安全
SELECT ROW_COUNT() AS 实际更新行数;        -- 0 行，说明条件不成立

UPDATE users SET balance = balance + 999999 WHERE id = 1;
COMMIT;
SELECT id, username, balance FROM users WHERE id IN (1, 2);
-- 1 号没多钱，因为 2 号扣款根本没发生

-- ============================================================
-- 场景 7：autocommit 与长事务的代价
-- ============================================================
SELECT @@autocommit AS 默认自动提交, @@innodb_flush_log_at_trx_commit AS 刷盘策略;

SET autocommit = 0;                       -- 改成手动提交
SELECT @@autocommit;
START TRANSACTION;                        -- 其实不写这行也行
UPDATE users SET age = age WHERE id = 1;
COMMIT;                                   -- ★ 一定要记得提交或回滚
SET autocommit = 1;                       -- ★ 改回来，否则后面的操作都进不了数据
SELECT @@autocommit;

-- ⚠ 忘了 COMMIT 又关着 autocommit = 数据看不见、锁一直不放
--   这就是生产事故「事务卡死」的典型原因
