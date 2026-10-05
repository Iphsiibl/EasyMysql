# 08 · 子查询与 UNION：让 SQL 嵌套起来

> **一句话价值**：掌握「用查询的结果当条件」，并学会把多个结果竖着摞起来。

**难度**：⭐⭐⭐　|　**时长**：约 30 分钟　|　**涉及表**：`users`、`orders`、`students`、`scores`

## 什么时候你会遇到它

需求是「查有订单的用户」。表里没有 `has_order` 这个字段，但你需要把「订单表里出现过的 user_id」当成筛选条件。

## 本篇你会学到

- [ ] 标量子查询（结果是一个值）
- [ ] `IN` / `EXISTS` / `NOT EXISTS` 子查询
- [ ] `EXISTS` 为什么在大数据量下往往更快
- [ ] 派生表（`FROM (子查询)`）
- [ ] `UNION`（去重）与 `UNION ALL`（不去重）
- [ ] 经典「**最高薪不低于自己部门平均薪**」写法

## 正文大纲

1. **标量子查询**：
   ```sql
   SELECT name, score FROM scores
   WHERE score > (SELECT AVG(score) FROM scores);
   ```
2. **IN 子查询**：
   ```sql
   SELECT id, username FROM users
   WHERE id IN (SELECT DISTINCT user_id FROM orders);
   ```
3. **EXISTS 的写法与优势**：
   ```sql
   SELECT u.id, u.username FROM users u
   WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
   ```
4. **派生表**（子查询当表用）：
   ```sql
   SELECT t.uid, t.cnt FROM (
     SELECT user_id AS uid, COUNT(*) AS cnt FROM orders GROUP BY user_id
   ) AS t
   WHERE t.cnt > 100;
   ```
5. **UNION vs UNION ALL**：
   ```sql
   SELECT city, COUNT(*) FROM students GROUP BY city
   UNION ALL
   SELECT city, COUNT(*) FROM users   GROUP BY city;
   ```
6. **综合实战**：找出订单数超过该用户所在城市平均订单数的用户

## 动手练

- [ ] 找出「有订单但最近 90 天没有下单」的用户
- [ ] 用两种写法（JOIN 版 / 子查询版）实现同一需求，对比可读性

## 参考输出

`lab/queries/08-demo-subquery.sql`

## 下一篇

[09 · 函数速查：日期、字符串与 NULL 的处理](09-functions.md)
