# 02 · 数据库、表、行、列：先搞懂这四个词

> **一句话价值**：能向别人解释清楚「我的数据存在哪」，并自己创建第一张表。

**难度**：⭐　|　**时长**：约 15 分钟　|　**涉及表**：`students`

## 什么时候你会遇到它

别人问你「你的用户表现在多少条数据」，你支支吾吾。或者你执行 `USE school` 报 `Unknown database 'school'`，却不知道 `school` 是什么。

## 本篇你会学到

- [ ] 数据库 / 表 / 行 / 列 的层级关系
- [ ] 什么是**主键**，为什么每张表都必须有
- [ ] `CREATE DATABASE` / `USE` / `SHOW TABLES` / `DESC` 四个命令
- [ ] 亲眼看看 `students` 表长什么样

## 正文大纲

1. **四层关系图**：服务器 → 数据库 → 表 → 行
2. **建库建表**：
   ```sql
   CREATE DATABASE IF NOT EXISTS my_school DEFAULT CHARSET utf8mb4;
   USE my_school;
   CREATE TABLE t_student (
     id   INT UNSIGNED NOT NULL AUTO_INCREMENT,
     name VARCHAR(30)  NOT NULL,
     PRIMARY KEY (id)
   );
   ```
3. **看懂表结构**：`DESC students;` / `SHOW CREATE TABLE students;`
4. **动手改**：给自建的表加一列、改列名、删掉重来
5. **踩坑提醒**：`utf8` 和 `utf8mb4` 的区别（emoji 存不进去）

## 动手练

- [ ] 说出为什么 `SHOW TABLES;` 要先 `USE` 某个库
- [ ] 把 `t_student` 删掉重建，这期间你会发现什么？

## 参考输出

```text
mysql> DESC students;
+--------------+-------------+------+-----+---------+----------------+
| Field        | Type        | Null | Key | Default | Extra          |
+--------------+-------------+------+-----+---------+----------------+
| id           | int unsigned | NO  | PRI | NULL    | auto_increment |
| name         | varchar(30)  | NO  |     | NULL    |                |
...
```

## 下一篇

[03 · SELECT 入门：查出你想要的那几行](03-select-basics.md)
