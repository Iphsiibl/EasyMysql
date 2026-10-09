# 附录 A3 · 术语中英对照表

> **一句话价值**：读英文文档 / 报错时能对上号。

## 基础概念

| 中文 | 英文 | 备注 |
|---|---|---|
| 数据库 | database / schema | MySQL 里两者等价 |
| 表 | table | |
| 行 | row / record | |
| 列 | column / field | |
| 主键 | primary key | |
| 外键 | foreign key | |
| 索引 | index | |
| 聚簇索引 | clustered index | 叶子节点挂整行，就是主键索引 |
| 二级索引 | secondary index | 非主键索引，查完常要回表 |
| 约束 | constraint | |
| 唯一约束 | unique constraint | |
| 子查询 | subquery | |
| 派生表 | derived table | `FROM (子查询)` |
| 驱动表 | driving table | JOIN 时先扫的那张 |
| 自动提交 | autocommit | 默认开启，每条语句单独成事务 |
| 视图 | view | |
| 存储过程 | stored procedure | |
| 触发器 | trigger | |
| 游标 | cursor | 存储过程里逐行处理用 |
| 事务 | transaction | |
| 提交 | commit | |
| 回滚 | rollback | |
| 保存点 | savepoint | |
| 锁 | lock | |
| 死锁 | deadlock | |
| 隔离级别 | isolation level | |
| 备份 | backup / dump | |
| 恢复 | restore | |
| 权限 | privilege / grant | |
| 慢查询 | slow query | |

## 数据类型

| 中文 | 英文 |
|---|---|
| 整数 | integer / INT |
| 小数 | decimal |
| 浮点 | float / double |
| 字符串 | char / varchar |
| 长文本 | text |
| 日期 | date |
| 日期时间 | datetime |
| 时间戳 | timestamp |
| 枚举 | enum |
| JSON | json |
| 二进制 | blob / binary |

## 性能相关

| 中文 | 英文 | 说明 |
|---|---|---|
| 执行计划 | execution plan | `EXPLAIN` 的输出 |
| 全表扫描 | full table scan | type = ALL |
| 回表 | clustered index lookup | 拿主键回整行，MySQL 里习惯叫「回表」 |
| 覆盖索引 | covering index | Extra: Using index |
| 排序 | sort | Extra: Using filesort |
| 临时表 | temporary table | Extra: Using temporary |
| 估算行数 | estimated rows | EXPLAIN 的 rows 列 |
| 实际行数 | actual rows | EXPLAIN ANALYZE 的 actual rows |
| 基数 | cardinality | 索引的区分度 |
| 缓冲池 | buffer pool | InnoDB 缓存数据的地方 |
| 最左前缀 | leftmost prefix | 联合索引规则 |
| 索引下推 | index condition pushdown | ICP |
| 慢查询日志 | slow query log | |
| 区分度 | selectivity | 不同值占比，越接近 1 越值得建索引 |
| 延迟关联 | deferred join | 先用索引取主键，再回表取整行 |

## 并发与事务

| 中文 | 英文 | 说明 |
|---|---|---|
| 脏读 | dirty read | 读到别人还没提交的数据 |
| 不可重复读 | non-repeatable read | 同一事务里两次读，结果不一样 |
| 幻读 | phantom read | 同一条件两次查，行数变了 |
| 间隙锁 | gap lock | 锁住索引之间的「空隙」，防幻读 |
| Next-Key Lock | next-key lock | 记录锁 + 间隙锁 |
| 行锁 | row lock | 锁一行（其实锁的是索引记录） |
| 表锁 | table lock | 锁整张表 |
| 乐观锁 | optimistic locking | 提交前检查没被改过（常用版本号） |
| 悲观锁 | pessimistic locking | 先锁上再改（`FOR UPDATE`） |
| 多版本并发控制 | MVCC | 读不加锁、能看到历史版本 |

## 报错常见词

| 英文 | 含义 |
|---|---|
| `Unknown database` | 库不存在 |
| `Unknown table` | 表不存在 |
| `Unknown column` | 列不存在 |
| `You have an error in your SQL syntax` | 语法错误 |
| `Data too long for column` | 数据太长 |
| `Incorrect string value` | 编码问题 |
| `Duplicate entry` | 违反唯一约束 |
| `Cannot add foreign key constraint` | 外键建不上 |
| `Lock wait timeout exceeded` | 锁等待超时 |
| `Deadlock found` | 死锁 |
| `Access denied for user` | 权限不够（22 篇） |
| `Data truncated for column` | 数据不符合列的约束（如 ENUM 塞了别的值） |
| `Table 'xxx' doesn't exist` | 表不存在 |

---

## 返回

[附录 A1 · 常用 SQL 速查表](A1-sql-cheatsheet.md)
