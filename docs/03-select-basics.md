# 03 · SELECT 入门：查出你想要的那几行

> **一句话价值**：用 SELECT 把表里的数据「取」出来，并只取你要的列。

**难度**：⭐　|　**时长**：约 20 分钟　|　**涉及表**：`students`

## 什么时候你会遇到它

你 `SELECT * FROM students;` 输出了 200 行 7 列，眼睛都花了：「我只想看北京的学生叫什么名字」，却不知道怎么只查两列。

## 本篇你会学到

- [ ] `SELECT 列名 FROM 表名` 的基本结构
- [ ] `*` 的代价，以及「能不用就不用」的原因
- [ ] `AS` 给列起别名
- [ ] `LIMIT` 只看前几行
- [ ] `ORDER BY` 让结果排好队

## 正文大纲

1. **SQL 的通用骨架**（记住这一句就够了）：
   ```sql
   SELECT 要哪些列 FROM 哪张表 [WHERE 条件] [ORDER BY 排序列] [LIMIT 条数];
   ```
2. **查全部**：`SELECT * FROM students LIMIT 10;`
3. **只查两列**：`SELECT name, city FROM students LIMIT 10;`
4. **改个名字看**：`SELECT name AS 姓名, city AS 城市 FROM students LIMIT 5;`
5. **排个队**：`SELECT name, birth_date FROM students ORDER BY birth_date DESC LIMIT 5;`
6. **运行 lab/queries/03-demo-select.sql**，对照自己的输出

## 动手练

- [ ] 查出身高……哦不，查询出生日期最早（最小）的 3 位学生
- [ ] 查出所有 6 个不同班级的名字

> 提示：`SELECT DISTINCT class_name FROM students;`

## 参考输出

见 `lab/queries/03-demo-select.sql` 顶部注释。

## 下一篇

[04 · WHERE 过滤：只留我想要的数据](04-where-filter.md)
