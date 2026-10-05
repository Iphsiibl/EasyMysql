> **一句话价值**：遇到报错不用慌，翻到这里找到错误码、原因和解决方案。

**难度**：⭐　|　**时长**：约 20 分钟　|　**涉及表**：全部

## 什么时候你会遇到它

`ERROR 1064 (42000) at line 1`。你复制这句话去搜，搜到的全是英文技术博客。

## 正文大纲

1. **按错误码查**：`1000~1999` 连接类 / `2000~2999` 认证类 / `3000` 客户端 / `4000~4999` 库表结构 / `5000~5999` 约束与数据 / `10000+` 其他
2. **按报错关键词查**：`Unknown column` / `Table doesn't exist` / `You have an error in your SQL syntax` / `Lock wait timeout exceeded` / `Deadlock found` / `Data too long for column` / `Incorrect string value`
3. **怎么读一条 MySQL 报错**（三段式拆解：错误码 / SQLSTATE / 信息）
4. **看更多信息的三个入口**：`SHOW WARNINGS`、`SHOW ENGINE INNODB STATUS`、服务端日志

## 速查表（本篇主要交付物）

| 错误 | 常见原因 | 怎么修 |
|---|---|---|
| `ERROR 2003 (HY000)` | MySQL 服务没启动 | 起服务 / 检查端口 |
| `ERROR 1045 (28000)` | 密码错或用户不存在 | 检查账号密码 |
| `ERROR 1049 (42000)` | 库名不存在 | `SHOW DATABASES;` |
| `ERROR 1054 (42S22)` | 列名写错 | `DESC 表名;` 对照 |
| `ERROR 1062 (23000)` | 违反唯一约束 | 改数据或改约束 |
| `ERROR 1146 (42S02)` | 表不存在 | `SHOW TABLES;` |
| `ERROR 1064 (42000)` | 语法错误 | 看 `SHOW WARNINGS;` |
| `ERROR 1366 (22007)` | 字符串编码问题 | 检查字符集 |
| `ERROR 1264 (22003)` | 数值超出字段范围 | 改字段类型 |
| `ERROR 1406 (22001)` | 字段太长 | 加大 VARCHAR 或改 TEXT |
| `ERROR 1213` | 死锁 | 重试 + 统一加锁顺序 |
| `ERROR 1205` | 锁等待超时 | 看慢事务 |

## 动手练

- [ ] 故意触发上表里 5 种报错，把原话抄进你的错误笔记
- [ ] 每次报错先别搜，先读懂错误码

## 参考输出

本文表格即速查表

## 下一篇

[附录 A1 · 常用 SQL 速查表](A1-sql-cheatsheet.md)
