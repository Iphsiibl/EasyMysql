# 附录 A1 · 常用 SQL 速查表

> **一句话价值**：一页纸看完所有常用的 MySQL 语句，忘了就翻这里。

## 建议的用法

**不要通读**。当字典用。遇到「我要写一个 XX」的时候来这里找模板。

## 数据库与表结构

```sql
SHOW DATABASES;                       -- 看所有库
USE easy_mysql;                       -- 选库
SHOW TABLES;                          -- 看当前库的表
SHOW CREATE TABLE orders;             -- 看完整建表语句（含索引注释）
DESC orders;                          -- 看字段结构
SHOW INDEX FROM orders;               -- 看索引
SHOW PROCESSLIST;                     -- 看当前连接和正在跑的语句
SHOW ENGINES;                         -- 看引擎（InnoDB / MyISAM）
```

## 增删改

```sql
INSERT INTO t (a, b) VALUES (1, 'x');
INSERT INTO t (a, b) VALUES (1,'x'), (2,'y');        -- 批量插入
INSERT IGNORE INTO t (a) VALUES (1);                 -- 忽略重复
REPLACE INTO t (id, a) VALUES (1, 'x');             -- 有则替换
UPDATE t SET a = 'x' WHERE id = 1;                   -- ★ 永远带 WHERE
DELETE FROM t WHERE id = 1;                          -- ★ 永远带 WHERE
TRUNCATE TABLE t;                                    -- 清空并重置自增
```

## 查询

```sql
SELECT * FROM t WHERE id = 1;
SELECT * FROM t WHERE a IN (1,2,3);
SELECT * FROM t WHERE a BETWEEN 1 AND 10;
SELECT * FROM t WHERE name LIKE '%张%';
SELECT * FROM t WHERE a IS NULL;
SELECT DISTINCT a FROM t;
SELECT a, COUNT(*) FROM t GROUP BY a HAVING COUNT(*) > 10;
SELECT * FROM t ORDER BY a DESC, b ASC LIMIT 10;
SELECT * FROM t LIMIT 10 OFFSET 20;                  -- 分页（深分页有坑）
```

## JOIN

```sql
SELECT * FROM a JOIN b ON a.id = b.a_id;             -- INNER
SELECT * FROM a LEFT JOIN b ON a.id = b.a_id;        -- 左边全保留
SELECT * FROM a RIGHT JOIN b ON a.id = b.a_id;       -- 右边全保留
SELECT * FROM a LEFT JOIN b ON a.id = b.a_id WHERE b.id IS NULL;  -- 找孤儿
```

## 索引与性能

```sql
CREATE INDEX idx_a ON t (a);
CREATE UNIQUE INDEX idx_a ON t (a);
ALTER TABLE t ADD INDEX idx_ab (a, b);
ALTER TABLE t DROP INDEX idx_a;
ALTER TABLE t ADD COLUMN c INT AFTER a;              -- 加字段（改名用 CHANGE，改类型用 MODIFY）
EXPLAIN SELECT ...;                                  -- 看执行计划
EXPLAIN ANALYZE SELECT ...;                          -- 真跑并计时（8.0.18+）
SHOW PROFILES;                                       -- 看本会话语句耗时
```

## 事务

```sql
START TRANSACTION;
SAVEPOINT s1;
ROLLBACK TO s1;
COMMIT;
ROLLBACK;
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
SELECT @@autocommit, @@innodb_lock_wait_timeout;      -- 查看变量（读到的是会话值）
```

## 用户与权限

```sql
CREATE USER 'dev'@'%' IDENTIFIED BY 'pwd';
GRANT SELECT, INSERT ON easy_mysql.* TO 'dev'@'%';
SHOW GRANTS FOR 'dev'@'%';
REVOKE INSERT ON easy_mysql.* FROM 'dev'@'%';
DROP USER 'dev'@'%';
FLUSH PRIVILEGES;                      -- 只有直接改过 grant 表才需要，GRANT 之后不用
```

## 备份（命令行）

```bash
mysqldump -uroot -p --single-transaction --databases easy_mysql > b.sql
mysqldump -uroot -p --no-data easy_mysql > schema.sql
mysql -uroot -p < b.sql

# 本仓库跑在 Docker 里，等价写法：
docker exec easy-mysql mysqldump -uroot -peasy123 --single-transaction --databases easy_mysql > b.sql
docker exec easy-mysql mysql -uroot -peasy123 < b.sql
```

> ⚠️ 上面是 bash 写法。PowerShell **没有 `<` 输入重定向**，而且 `>` 会把文件存成 UTF-16，
> 照抄备份出来的 `b.sql` 恢复时中文全坏。PowerShell 里用 Adminer 导入，或 `docker cp` + `source`（见第 21 篇）。

## 返回

[附录 A2 · 练习题与答案](A2-exercises.md)
