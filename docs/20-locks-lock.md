# 20 · 锁与死锁：并发下的秩序

> **一句话价值**：知道什么时候会锁表、为什么会死锁，以及两把万能钥匙。

**难度**：⭐⭐⭐⭐　|　**时长**：约 40 分钟　|　**涉及表**：`users`、`orders`、`scores`

## 什么时候你会遇到它

你的程序偶尔卡住不动，日志里全是 `Lock wait timeout exceeded`；或者你收到一条告警：`Deadlock found when trying to get lock`。

## 本篇你会学到

- [ ] 读锁 / 写锁，以及「写锁为什么互斥」
- [ ] 表锁 vs 行锁（**`UPDATE` 没加 `WHERE` 会锁全表**）
- [ ] 行锁的三种：记录锁、间隙锁、Next-Key Lock
- [ ] 死锁的四个必要条件
- [ ] **两把万能钥匙**：统一加锁顺序、缩短事务
- [ ] 怎么看锁：`SHOW ENGINE INNODB STATUS` / `performance_schema.data_locks`

## 正文大纲

1. **锁是什么**：两个人抢同一把椅子
2. **演示表锁**（两个窗口）：
   ```sql
   -- 窗口 1
   START TRANSACTION; SELECT * FROM users WHERE id = 1 FOR UPDATE;
   -- 窗口 2：查询会一直等待
   ```
3. **演示行锁**：`WHERE id = 1` 锁一行 vs `WHERE gender = '男'` 锁一大片
4. **间隙锁和幻读**：RR 下 `WHERE id BETWEEN 1 AND 10 FOR UPDATE` 会锁住空隙
5. **手动造一个死锁**（本篇高潮）：
   ```sql
   -- 窗口 1：先锁 1 再锁 2
   -- 窗口 2：先锁 2 再锁 1
   ```
6. **`SHOW ENGINE INNODB STATUS\G`** 读懂死锁报告
7. **预防死锁的三条铁律**
8. **锁等待超时怎么调**：`innodb_lock_wait_timeout`

## 动手练

- [ ] 手动造出一次死锁，把报告里的「事务 1 / 事务 2」两段贴到笔记里
- [ ] 找出你项目里 `UPDATE` 忘了加 `WHERE` 的地方

## 参考输出

`lab/queries/20-demo-locks.sql`

## 下一篇

[21 · 备份与恢复：你的作业还能救回来吗](21-backup-restore.md)
