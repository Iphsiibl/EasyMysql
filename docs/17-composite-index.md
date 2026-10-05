# 17 · 联合索引与最左前缀：三个字段只建一个索引

> **一句话价值**：搞懂 `(a,b,c)` 这个索引到底能用在哪些查询上，并顺手解决「优化器选错索引」。

**难度**：⭐⭐⭐⭐　|　**时长**：约 35 分钟　|　**涉及表**：`orders`

## 什么时候你会遇到它

你明明建了 `idx (status, created_at)`，查询条件两个字段都写了，`EXPLAIN` 却显示 `key_len` 只有 8（只用了第一个字段），扫了 5 万行。

## 本篇你会学到

- [ ] 联合索引的**排序规则**（先按 a 排，a 相同再按 b 排）
- [ ] 范围查询会「截断」后面的列
- [ ] 排序方向（`ASC` / `DESC`）对联合索引的影响
- [ ] 索引下推（Index Condition Pushdown）一句话版
- [ ] **优化器选错索引怎么办**：`FORCE INDEX` 与改写 SQL

## 正文大纲

1. **联合索引的本质**：把两列当成一个「组合键」排序
2. **最左前缀实验**（6 条查询 + 6 个 EXPLAIN，一张表看懂）
   ```sql
   -- 能用
   WHERE status = 'paid'
   WHERE status = 'paid' AND created_at > '2024-07-01'
   -- 用不上
   WHERE created_at > '2024-07-01'
   ```
3. **范围截断**：
   ```sql
   WHERE status = 'paid' AND created_at > 'x' AND user_id = 1
   --                          ↑ 范围之后 user_id 只能过滤，不能定位
   ```
4. **排序也能用索引**：
   ```sql
   WHERE status = 'paid' ORDER BY created_at LIMIT 10   -- Using filesort 消失
   ```
5. **优化器选错的真实案例**（本仓库数据实测）：
   ```sql
   SELECT COUNT(*) FROM orders WHERE status='paid' AND user_id=42;
   -- 优化器选了 idx_orders_status_created：18.7ms → 4.7ms
   SELECT COUNT(*) FROM orders FORCE INDEX (idx_orders_user) WHERE status='paid' AND user_id=42;
   ```
6. **别滥用 FORCE INDEX**：先改索引顺序，再考虑强制

## 动手练

- [ ] 设计一个能同时支持「按状态查时间范围」和「按用户查时间范围」的联合索引
- [ ] 对比调整索引顺序前后的 `EXPLAIN`

## 参考输出

`lab/queries/17-demo-composite-index.sql`

## 下一篇

[18 · 事务与 ACID：一次转账为什么不能只扣钱](18-transaction.md)
