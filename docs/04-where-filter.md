# 04 · WHERE 过滤：只留我想要的数据

> **一句话价值**：掌握 `= > < LIKE IN BETWEEN AND OR NOT` 这一整套筛选条件。

**难度**：⭐　|　**时长**：约 25 分钟　|　**涉及表**：`students`、`scores`

## 什么时候你会遇到它

表有 200 万行，你只想看「北京、2005 年之后出生、姓王的」这一小撮人。没有 WHERE，你只能 Ctrl+C。

## 本篇你会学到

- [ ] 六种比较运算符
- [ ] `AND` / `OR` / `NOT` 以及**括号为什么不能省**
- [ ] `LIKE` 模糊查询，`%` 和 `_` 的区别
- [ ] `IN` 解决「IN 括号问题」
- [ ] `BETWEEN a AND b` 的两个坑（闭区间、写反顺序）
- [ ] `IS NULL` 和 `= NULL` 为什么不一样

## 正文大纲

1. **最常见的三个条件**：`=`、`>`、`<`
2. **AND 和 OR 的坑**：举一个 `gender='男' AND class_name='软工211班' OR city='北京'` 的例子，让读者算错一次
3. **LIKE 模糊查询**：
   ```sql
   SELECT name FROM students WHERE name LIKE '王%';
   SELECT name FROM students WHERE name LIKE '%伟';
   SELECT name FROM students WHERE name LIKE '赵_伟';
   ```
4. **IN 与 BETWEEN**：
   ```sql
   SELECT name, city FROM students WHERE city IN ('北京', '上海', '深圳');
   SELECT name FROM students WHERE birth_date BETWEEN '2005-09-01' AND '2006-09-01';
   ```
5. **NULL 的正确写法**：
   ```sql
   SELECT * FROM order_items WHERE remark IS NULL;   -- 正确
   SELECT * FROM order_items WHERE remark = NULL;    -- 永远查出 0 行
   ```
6. **实战**：写一句 SQL 找出「北京或上海、出生日期在 2006 年之前、名字里带伟」的男生

## 动手练

在 `lab/queries/04-demo-where.sql` 里有 6 道带答案的题，直接跑。

## 参考输出

`lab/queries/04-demo-where.sql`

## 下一篇

[05 · 排序、分页与聚合](05-order-limit-aggregate.md)
