# 附录 A2 · 练习题与答案

> **一句话价值**：30 道由浅入深的题，做完能确认自己真的会了。

**建议**：先自己写，写不出来再看答案。答案用 `<details>` 折叠。

## 基础（01~06）

1. 查出所有姓「王」的学生，显示姓名和城市
2. 查出年龄…（本表无 age）查出所有城市的女生数量，按数量倒序
3. 查出成绩在 90 分以上的记录，显示学生名、课程名、分数
4. 统计每个城市的男生人数
5. 找出平均分最高的班级
6. 查出每门课的及格率，只看及格率 100% 的课
7. 找出选课数超过 10 人的课程
8. 列出所有学生和他们的平均分（没考的显示 0）

## 进阶（07~10）

9. 列出所有学生（包括没参加考试的）及其考试科目数
10. 找出没有任何课程及格的学生
11. 统计每个城市的用户数，只保留用户数 > 100 的城市
12. 找出下单次数最多的前 5 个用户
13. 找出金额最大的 3 笔订单及其明细行数
14. 用一个子查询改写第 4 题
15. 列出每个月的订单量和销售额
16. 把 `orders` 按状态分组，统计每组金额均值和最大值

## 性能（13~17）

17. `EXPLAIN` 分析 `SELECT * FROM orders_slow WHERE user_id = 42`，指出问题
18. 在 `orders_slow` 上建索引，让第 17 题的 `type` 变成 `ref`
19. 找出 `orders` 表中区分度最低的两个字段，说明为什么不该单独建索引
20. 写一条必然产生 `Using filesort` 的 SQL
21. 设计一个联合索引，支持「按状态查某时间段订单」
22. 一条 SQL 查询 2024 年 7 月和 8 月的订单数（提示：条件 OR 或 `IN`）

## 事务（18~20）

23. 完成一次转账，测试 `ROLLBACK`
24. 说出「转账 SQL 写在事务里，但第二条 UPDATE 失败」时会发生什么
25. 说出 RR 和 RC 在「重复执行同一条查询」上的区别
26. 解释为什么「先查库存再更新」需要加锁

## 综合

27. 找出「下单金额排第 3 的用户」和「下单次数排第 5 的用户」，用一次查询输出
28. 用 `JOIN` 查出每个城市的「学生数、用户数」，并算出比值
29. 找出有订单但 2024 年没有下单的用户
30. 设计一张「商品库存变动流水表」，写出 DDL

---

<details>
<summary>参考答案 1~8</summary>

```sql
-- 1
SELECT name, city FROM students WHERE name LIKE '王%';
-- 2
SELECT city, COUNT(*) FROM students WHERE gender='女' GROUP BY city ORDER BY 2 DESC;
-- 3
SELECT s.name, c.name, sc.score
FROM scores sc JOIN students s ON s.id=sc.student_id JOIN courses c ON c.id=sc.course_id
WHERE sc.score >= 90;
-- 4
SELECT city, COUNT(*) FROM students WHERE gender='男' GROUP BY city;
-- 5
SELECT s.class_name, AVG(sc.score) a FROM students s JOIN scores sc ON sc.student_id=s.id
GROUP BY s.class_name ORDER BY a DESC LIMIT 1;
-- 6
SELECT c.name, SUM(sc.score>=60)/COUNT(*) rate FROM scores sc JOIN courses c ON c.id=sc.course_id
GROUP BY c.id HAVING rate = 1;
-- 7
SELECT c.name, COUNT(*) n FROM scores sc JOIN courses c ON c.id=sc.course_id
GROUP BY c.id HAVING n > 10;
-- 8
SELECT s.name, IFNULL(AVG(sc.score),0) FROM students s LEFT JOIN scores sc ON sc.student_id=s.id
GROUP BY s.id, s.name;
```

</details>

<details>
<summary>参考答案 9~16</summary>

```sql
-- 9
SELECT s.name, COUNT(sc.id) FROM students s LEFT JOIN scores sc ON sc.student_id=s.id GROUP BY s.id;
-- 10
SELECT s.name FROM students s JOIN scores sc ON sc.student_id=s.id
GROUP BY s.id HAVING SUM(sc.score<60)=COUNT(*);
-- 11
SELECT city, COUNT(*) n FROM users GROUP BY city HAVING n>100;
-- 12
SELECT user_id, COUNT(*) n FROM orders GROUP BY user_id ORDER BY n DESC LIMIT 5;
-- 13
SELECT o.id, o.amount, COUNT(i.id) c FROM orders o JOIN order_items i ON i.order_id=o.id
GROUP BY o.id ORDER BY o.amount DESC LIMIT 3;
-- 16
SELECT status, AVG(amount), MAX(amount) FROM orders GROUP BY status;
```

</details>

<details>
<summary>参考答案 17~22（关键几条）</summary>

```sql
-- 18
ALTER TABLE orders_slow ADD INDEX idx_user (user_id);
-- 20
SELECT * FROM orders ORDER BY amount DESC;   -- amount 无索引 → Using filesort
-- 21
ALTER TABLE orders ADD INDEX idx_status_created (status, created_at);  -- 已存在
-- 22
SELECT COUNT(*) FROM orders
WHERE (created_at >= '2024-07-01' AND created_at < '2024-09-01');
```

</details>

---

## 返回

[附录 A3 · 术语中英对照表](A3-glossary.md)
