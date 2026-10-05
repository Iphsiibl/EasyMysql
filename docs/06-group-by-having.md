# 06 · GROUP BY 与 HAVING：按班级统计平均分

> **一句话价值**：学会「分组统计」，并彻底搞清 `WHERE` 和 `HAVING` 到底差在哪。

**难度**：⭐⭐　|　**时长**：约 30 分钟　|　**涉及表**：`students`、`scores`、`courses`

## 什么时候你会遇到它

作业要求「统计每个班的平均分、及格人数、挂科率」。你试了 `SELECT class_name, AVG(score) FROM students, scores ...` 报错了，或者算出来的行数不对。

## 本篇你会学到

- [ ] `GROUP BY` 的含义：把行「折叠」成组
- [ ] `SELECT` 里的非聚合列必须出现在 `GROUP BY` 中（ONLY_FULL_GROUP_BY）
- [ ] `HAVING` 过滤的是**组**，`WHERE` 过滤的是**行**
- [ ] 执行顺序：`FROM → WHERE → GROUP BY → HAVING → SELECT → ORDER BY → LIMIT`
- [ ] 多字段分组

## 正文大纲

1. **从「一列数字」到「一张报表」**：
   ```sql
   SELECT class_name, COUNT(*) AS 人数
   FROM students
   GROUP BY class_name;
   ```
2. **JOIN 之后再分组**（本篇的主菜）：
   ```sql
   SELECT s.class_name, ROUND(AVG(sc.score), 2) AS 平均分
   FROM students s
   JOIN scores sc ON sc.student_id = s.id
   GROUP BY s.class_name
   ORDER BY 平均分 DESC;
   ```
3. **执行顺序图**（本篇最重要的一张图，建议自己画一遍）
4. **WHERE vs HAVING 对比实验**：
   ```sql
   -- 只统计及格的分数
   SELECT class_name, AVG(score) FROM students s JOIN scores sc ON sc.student_id=s.id
   WHERE sc.score >= 60 GROUP BY class_name;
   -- 先算出每组平均分，再筛掉平均分低的组
   SELECT class_name, AVG(score) FROM students s JOIN scores sc ON sc.student_id=s.id
   GROUP BY class_name HAVING AVG(score) >= 60;
   ```
5. **多字段分组** + `ROLLUP` 汇总行

## 动手练

- [ ] 统计每门课的报名人数、平均分、最高分，并只留平均分 ≥ 60 的课
- [ ] 统计每个学生的不及格科目数，只看有不及格的

## 参考输出

`lab/queries/06-demo-group-by.sql`

## 下一篇

[07 · JOIN：把两张表拼起来](07-join.md)
