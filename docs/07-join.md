# 07 · JOIN：把学生表和成绩表拼起来

> **一句话价值**：理解 `INNER / LEFT / RIGHT JOIN` 的差别，并彻底消灭「一对多 JOIN 出重复行」这个经典 bug。

**难度**：⭐⭐　|　**时长**：约 35 分钟　|　**涉及表**：`students`、`scores`、`courses`、`orders`、`order_items`

## 什么时候你最需要它

学生表有 200 行，成绩表有 2000 行。写完 JOIN 后你发现：**某些学生出现了 10 次**，还不认识的那个学生**一条记录都没有**。

## 本篇你会学到

- [ ] JOIN 的本质：按某个「共同字段」把两行拼成一行
- [ ] `INNER JOIN`（只留两边都有）vs `LEFT JOIN`（左边全留）
- [ ] **一句话判断法**：你要的是「有成绩的学生」还是「所有学生」
- [ ] JOIN 出重复行的原因和两种解法
- [ ] 多表三连 JOIN

## 正文大纲

1. **生活中的 JOIN**：学生名单和成绩单，按学号对齐
2. **INNER JOIN 起步**：
   ```sql
   SELECT s.name, c.name AS 课程, sc.score
   FROM students s
   JOIN scores  sc ON sc.student_id = s.id
   JOIN courses  c ON c.id = sc.course_id
   LIMIT 10;
   ```
3. **LEFT JOIN 找出「没参加任何考试」的人**（本篇必做实验）：
   ```sql
   SELECT s.id, s.name
   FROM students s
   LEFT JOIN scores sc ON sc.student_id = s.id
   WHERE sc.id IS NULL;        -- 注意：过滤条件要写在 ON 后面才不影响 LEFT 语义
   ```
4. **ON 和 WHERE 的区别**（LEFT JOIN 的头号坑）：先过滤再拼 vs 先拼再过滤
5. **重复行问题**：一个订单有多条明细，JOIN 后金额被重复累加
   ```sql
   -- 错的：金额翻倍
   SELECT o.id, SUM(i.price * i.quantity) FROM orders o
   JOIN order_items i ON i.order_id = o.id GROUP BY o.id;
   -- 对的：先去重再 JOIN
   SELECT o.id, o.amount FROM orders o ... ;
   ```
6. **JOIN 的执行顺序**：驱动表是什么

## 动手练

- [ ] 列出所有学生（包括没参加考试的人）及其平均分，没考的显示 NULL
- [ ] 统计每个订单的明细行数，找出明细超过 3 条的订单

## 参考输出

`lab/queries/07-demo-join.sql`

## 下一篇

[08 · 子查询与 UNION：让 SQL 嵌套起来](08-subquery-union.md)
