# 09 · 函数速查：日期、字符串与 NULL 的处理

> **一句话价值**：查出一份「遇到就能用」的常用函数清单，并知道每类函数该配 `WHERE` 还是 `GROUP BY`。

**难度**：⭐⭐　|　**时长**：约 25 分钟　|　**涉及表**：`users`、`orders`、`students`

## 什么时候你会遇到它

你写 `WHERE YEAR(created_at) = 2024`，代码 review 的人皱起眉头。老板说「按月统计销售额」，你查了一晚上发现「月」这个字段根本不存在。

## 本篇你会学到

- [ ] 字符串：`CONCAT` `SUBSTRING` `LEFT/RIGHT` `TRIM` `REPLACE` `LPAD/RPAD`
- [ ] 日期：`NOW` `CURDATE` `DATE_FORMAT` `DATEDIFF` `YEAR/MONTH/DAY` `LAST_DAY`
- [ ] 条件：`IF` `CASE WHEN` `IFNULL` `COALESCE`
- [ ] 窗口：**为什么 `WHERE YEAR(x)=2024` 要改写成范围查询**
- [ ] 常见类型转换的坑

## 正文大纲

1. **字符串处理**：
   ```sql
   SELECT CONCAT(name, '(', city, ')') AS 标签 FROM students LIMIT 10;
   SELECT name, LEFT(name,1) AS 姓, CHAR_LENGTH(name) AS 名字长度 FROM students LIMIT 10;
   ```
2. **日期处理**：
   ```sql
   SELECT DATE_FORMAT(created_at, '%Y-%m') AS 月份, COUNT(*)
   FROM orders GROUP BY 月份;
   ```
3. **区间查询的正确写法**（重点，反模式对照）：
   ```sql
   -- 反模式：索引失效，全表扫描
   WHERE YEAR(created_at) = 2024
   -- 正确：范围条件，索引可用
   WHERE created_at >= '2024-01-01' AND created_at < '2025-01-01'
   ```
4. **NULL 三兄弟**：`IFNULL` / `COALESCE` / `NULLIF` 的区别
5. **`CASE WHEN` 做分类**（行转列雏形）：
   ```sql
   SELECT s.name,
          SUM(CASE WHEN sc.score >= 90 THEN 1 ELSE 0 END) AS 优秀,
          SUM(CASE WHEN sc.score >= 60 THEN 1 ELSE 0 END) AS 及格
   FROM students s JOIN scores sc ON sc.student_id = s.id
   GROUP BY s.id, s.name LIMIT 10;
   ```
6. **速查表**：整理成本文末尾的表格

## 动手练

- [ ] 把订单按下单月份统计销售额（用 `DATE_FORMAT` + `GROUP BY`）
- [ ] 列出每个城市的学生人数，按人数从多到少

## 参考输出

`lab/queries/09-demo-functions.sql`

## 下一篇

[10 · 数据类型怎么选：别用 VARCHAR 存一切](10-data-types.md)
