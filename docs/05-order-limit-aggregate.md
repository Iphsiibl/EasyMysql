# 05 · 排序、分页与聚合：COUNT / SUM / AVG / MAX / MIN

> **一句话价值**：算出「一共多少人」「平均分多少」「最高分是谁」，并学会正确分页。

**难度**：⭐⭐　|　**时长**：约 25 分钟　|　**涉及表**：`students`、`scores`

## 什么时候你会遇到它

`SELECT * FROM orders LIMIT 10 OFFSET 10000;` 越来越慢；你只想知道最高分是多少，却写了 `SELECT MAX(score) FROM scores` 才发现还要查出是谁考的。

## 本篇你会学到

- [ ] 五个聚合函数：`COUNT` `SUM` `AVG` `MAX` `MIN`
- [ ] `COUNT(*)` 和 `COUNT(列名)` 的区别
- [ ] `LIMIT offset, n` 的**大坑**（越翻页越慢，以及为什么）
- [ ] **索引排序优化**：让排序走索引的写法
- [ ] 求 Top-N 的标准套路

## 正文大纲

1. **聚合函数**：先在 `scores` 上试五个函数
2. **`COUNT(*)` vs `COUNT(score)`**：
   ```sql
   SELECT COUNT(*), COUNT(score), COUNT(DISTINCT student_id) FROM scores;
   ```
3. **聚合不能配普通 WHERE**（先埋一个引子，第 06 篇解决）
4. **分页与它的大坑**：
   ```sql
   -- 慢：OFFSET 100000 时数据库要先丢掉前 10 万行
   SELECT * FROM orders ORDER BY id LIMIT 100000, 20;
   ```
5. **Top-N 的正确写法**（重点）：
   ```sql
   SELECT id, user_id, amount
   FROM orders
   WHERE id > 150000          -- 记住上次看到的最大 id
   ORDER BY id
   LIMIT 20;                  -- 延迟关联，见第 16 篇
   ```
6. **求最高分是哪位学生**：先聚合，再回表
   ```sql
   SELECT s.name, sc.score
   FROM scores sc JOIN students s ON s.id = sc.student_id
   WHERE sc.score = (SELECT MAX(score) FROM scores);
   ```

## 动手练

- [ ] 查询订单金额最高的 10 笔订单
- [ ] 查询每个用户（只看前 1000 个）的订单数，并取前 10 名

## 参考输出

`lab/queries/05-demo-aggregate.sql`

## 下一篇

[06 · GROUP BY 与 HAVING：按班级统计平均分](06-group-by-having.md)
