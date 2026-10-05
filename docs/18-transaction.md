# 18 · 事务与 ACID：一次转账为什么不能只扣钱

> **一句话价值**：用「转账」理解事务，写出第一条 `BEGIN` / `COMMIT` / `ROLLBACK`，并手动造一次故障。

**难度**：⭐⭐⭐　|　**时长**：约 35 分钟　|　**涉及表**：`users`

## 什么时候你会遇到它

你给同学转账，程序执行了 `UPDATE` 扣款，然后网络断了 —— 钱扣了，对方没收到。**没有事务，两个 UPDATE 就是一个整体吗？不是。**

## 本篇你会学到

- [ ] ACID 四个字母分别在解决什么问题
- [ ] `START TRANSACTION` / `COMMIT` / `ROLLBACK`
- [ ] **手动造一次回滚**（写到一半故意报错）
- [ ] 事务的四种嵌套与 `SAVEPOINT`
- [ ] 事务必须放在 InnoDB 上（MyISAM 不支持）
- [ ] 事务的代价：锁、binlog、不能滥用

## 正文大纲

1. **先复现事故**：两条 UPDATE，中间故意插入一句错误 SQL
2. **ACID 逐个讲**（用转账比喻，不抄定义）
3. **手动实验**（本篇核心）：
   ```sql
   START TRANSACTION;
   UPDATE users SET balance = balance - 100 WHERE id = 1;
   UPDATE users SET balance = balance + 100 WHERE id = 2;
   SELECT * FROM users WHERE id IN (1,2);
   ROLLBACK;     -- 回到原样
   ```
4. **`SAVEPOINT` 部分回滚**实验
5. **自动提交**：`autocommit=1` 是什么，为什么关掉它要记得改回来
6. **别把事务开太大**：事务里做网络请求 = 长事务 = 锁表

## 动手练

- [ ] 完成一笔转账并 `COMMIT`，再试一次 `ROLLBACK`
- [ ] 故意在两条 UPDATE 中间执行一句语法错误的 SQL，观察自动回滚

## 参考输出

`lab/queries/18-demo-transaction.sql`

## 下一篇

[19 · 隔离级别与四种并发问题](19-isolation-level.md)
