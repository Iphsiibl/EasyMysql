> **一句话价值**：以后遇到慢 SQL，先 `EXPLAIN` 一下，五秒知道问题在哪。

**难度**：⭐⭐⭐　|　**时长**：约 35 分钟　|　**涉及表**：`orders`、`scores`、`order_items`

## 什么时候你会遇到它

`SELECT ...` 跑了 8 秒，你完全不知道它卡在哪。`EXPLAIN` 一下，两行表格告诉你它扫了 20 万行还是只用了索引。

## 本篇你会学到

- [ ] `EXPLAIN` 输出的 12 列各自是什么意思
- [ ] **`type` 列的 8 个值，从好到坏**（`const` → `ref` → `range` → `index` → `ALL`）
- [ ] `rows` 是怎么估算出来的
- [ ] `Extra` 列里最该警惕的三个词：`Using filesort`、`Using temporary`、`Using index`
- [ ] `EXPLAIN FORMAT=JSON` 和 `EXPLAIN ANALYZE`（真跑一遍看实际耗时）

## 正文大纲

1. **EXPLAIN 怎么用**：`EXPLAIN 前面加在 SELECT 前面就行`
2. **逐列拆解**：用 `orders` 的三条查询，把 12 列填满
3. **`type` 优先级排序表**（本篇最该截图保存的一张表）
   | type | 含义 | 好坏 |
   |---|---|---|
   | const | 主键/唯一索引等值 | 最好 |
   | ref | 非唯一索引等值 | 好 |
   | range | 索引范围 | 一般 |
   | index | 扫索引全表 | 慢 |
   | ALL | 全表扫描 | 最差 |
4. **`Using filesort` 是什么**：不是磁盘排序，是「无法利用索引顺序」的意思
5. **`EXPLAIN ANALYZE` 实战**（MySQL 8.0.18+）：真实耗时 + actual rows，和预估对比
6. **慢查询日志**：把 `long_query_time` 调小，抓一条真凶

## 动手练

- [ ] 找出一条 `type = ALL` 的 SQL 并优化到 `type = ref`
- [ ] 制造一条 `Using filesort` 的 SQL，思考怎么改（答案在第 17 篇）

## 参考输出

`lab/queries/15-demo-explain.sql`

## 下一篇

[16 · 慢查询优化实战：一条 SQL 从 18 毫秒到 0.05 毫秒](16-optimize-slow-query.md)
