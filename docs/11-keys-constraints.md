# 11 · 主键、外键与约束：给数据装上护栏

> **一句话价值**：用 `NOT NULL`、`UNIQUE`、`DEFAULT`、`CHECK`、`FOREIGN KEY` 让数据库自己挡住脏数据。

**难度**：⭐⭐　|　**时长**：约 30 分钟　|　**涉及表**：`students`、`courses`、`scores`

## 什么时候你会遇到它

测试同学往表里插了一条 `score = 1500` 的成绩，代码没报错，报表炸了。或者 `scores` 里出现了 `student_id = 99999` —— 这个学生根本不存在。

## 本篇你会学到

- [ ] 各种约束的作用
- [ ] 主键的四种写法（`INT AUTO_INCREMENT` / `UUID` / 雪花 ID / 自然主键）
- [ ] `UNIQUE` 允许几个 `NULL`
- [ ] 外键的代价：为什么大表常常不建**物理**外键
- [ ] `ON DELETE CASCADE / SET NULL / RESTRICT` 的区别
- [ ] `CHECK` 约束（MySQL 8.0.16 之后才真正生效）

## 正文大纲

1. **没有约束的数据库长什么样**：手工往 `scores` 塞 `score=1500`
2. **五种约束逐个试**：
   ```sql
   ALTER TABLE scores
     ADD CONSTRAINT chk_score CHECK (score BETWEEN 0 AND 100);
   ```
3. **复合唯一键**：`UNIQUE KEY uk_scores_student_course (student_id, course_id)`
4. **外键实验**：
   ```sql
   INSERT INTO scores (student_id, course_id, score, exam_date)
   VALUES (99999, 1, 90, '2025-06-20');   -- 报错 1452
   ```
5. **外键的三种删除行为**，用 `orders` / `order_items` 演示
6. **讨论**：物理外键 vs 应用层约束（讲清利弊，别一刀切）
7. **默认值与 `ON UPDATE CURRENT_TIMESTAMP`**

## 动手练

- [ ] 给 `students` 加一个 `CHECK (age BETWEEN 0 AND 150)`（注意：本表无 age，先加列）
- [ ] 尝试删掉一个还有成绩的学生，看外键怎么拦住你

## 参考输出

`lab/queries/11-demo-constraints.sql`

## 下一篇

[12 · 建表军规：一份可以直接抄的模板](12-table-design-rules.md)
