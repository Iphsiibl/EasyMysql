# EasyMysql

> 面向**零基础和在校学生**的 MySQL 实战教程。每一篇都配一套能直接跑起来的数据，
> 每一条结论都有真实输出撑着，**没有一个字是你需要凭空相信的**。

[![MySQL](https://img.shields.io/badge/MySQL-8.0-4479A1?logo=mysql&logoColor=white)](https://www.mysql.com/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

> **📌 项目状态**：实验环境已跑通（8 张表 / 80 万行 / 全部 SQL 验证通过），
> **23 篇正文的选题表、大纲和配套实验文件已就位，正文正在逐篇撰写中**。
> 进度见 [NOTES.md](NOTES.md)。欢迎认领你需要的篇目。

---

## 这个仓库和别的 MySQL 教程有什么不一样

市面上不缺 MySQL 教程，缺的是**能验证的**教程。本仓库只做三件事：

| | 常见教程 | EasyMysql |
|---|---|---|
| 示例 SQL | `SELECT * FROM user WHERE id = 1`，表从哪来？ | 自带 80 万行造好的数据，直接跑 |
| 结论依据 | 「加了索引会变快」（快多少？） | 20 万行实测：扫 199430 行 vs 29 行 |
| 错误示范 | 只给对的 | 专门造一张 `bad_design_demo` 让你亲眼看错在哪 |

一句话：**别人的教程让你"看懂"，这个仓库让你"看穿"**。

## 适合谁 / 不适合谁

✅ 适合
- 上了数据库课但实验报告只能抄同学的
- 正在学 Java / Python / Go，需要懂数据库的
- 面试被问「索引是什么」答不上来

❌ 不适合
- 已经是 DBA，要看 8.0 内核源码
- 想找生产级高可用架构方案（主从、分库分表，另有专门的书）

## 先花 3 分钟跑起来

推荐用 Docker，一条命令就有数据库、造好的数据和图形界面：

```powershell
cd lab
docker compose up -d
```

浏览器打开 **<http://localhost:8080>**，用下面这组账号登录：

```
系统：MySQL     服务器：easy-mysql     用户名：root     密码：easy123
```

看到 `students` 表里有 200 行，你就准备好了。**装不上的话看 [lab/README.md](lab/README.md)，里面还有免安装版和在线沙盒两种方案。**

## 学习路线

六个阶段，每阶段都能独立学完。按顺序读效果最好，跳着读也行。

👉 新手先看 **[00 · 写在前面：怎么用这个教程](docs/00-写在前面.md)**（8 分钟，能少走很多弯路）

| 阶段 | 文章 | 你会拿到什么 |
|---|---|---|
| ① 认识 MySQL | [01](docs/01-what-is-mysql.md) · [02](docs/02-db-table-row-column.md) · [03](docs/03-select-basics.md) | 装好数据库，明白「库/表/行/列」，会写 SELECT |
| ② 查询基本功 | [04](docs/04-where-filter.md) · [05](docs/05-order-limit-aggregate.md) · [06](docs/06-group-by-having.md) · [07](docs/07-join.md) · [08](docs/08-subquery-union.md) · [09](docs/09-functions.md) | 写出教务系统级的统计查询，JOIN 不再出重复行 |
| ③ 设计一张好表 | [10](docs/10-data-types.md) · [11](docs/11-keys-constraints.md) · [12](docs/12-table-design-rules.md) | 建表不踩坑，拿到需求能直接写 DDL |
| ④ 索引与性能 | [13](docs/13-index-what.md) · [14](docs/14-when-to-index.md) · [15](docs/15-explain.md) · [16](docs/16-optimize-slow-query.md) · [17](docs/17-composite-index.md) | 拿到一条慢 SQL，五秒定位问题 |
| ⑤ 事务与并发 | [18](docs/18-transaction.md) · [19](docs/19-isolation-level.md) · [20](docs/20-locks-lock.md) | 搞懂转账为什么不能只扣钱，能手动复现死锁 |
| ⑥ 真实工程 | [21](docs/21-backup-restore.md) · [22](docs/22-permission-security.md) · [23](docs/23-error-lookup.md) | 备份能救命，权限不乱给，报错自己查 |

**附录**：[A1 常用 SQL 速查表](docs/A1-sql-cheatsheet.md) · [A2 练习题 30 道](docs/A2-exercises.md) · [A3 术语中英对照](docs/A3-glossary.md)

> 完整选题表和写作进度见 **[NOTES.md](NOTES.md)**，选题、难点、状态都在里面。

## 配套数据长什么样

教程里所有表都已经建好、数据已经灌好（80 万行，一次性生成，约 20 秒）：

| 表 | 行数 | 干什么用 |
|---|---:|---|
| `students` | 200 | 阶段 ② 查成绩，阶段 ③ 建表设计 |
| `courses` | 20 | 课程表 |
| `scores` | 2,000 | 学生 × 课程 = 成绩，练 JOIN 和 GROUP BY |
| `users` | 5,000 | 阶段 ④ 的用户表 |
| `orders` | 200,000 | **有索引**，练 EXPLAIN 和优化 |
| `orders_slow` | 200,000 | **无索引**，`orders` 的对照组，字段完全一样 |
| `order_items` | 600,000 | 练一对多 JOIN、深分页 |
| `bad_design_demo` | 20 | 故意写错的反面教材，阶段 ③ 逐个拆 |

`orders` 和 `orders_slow` 这对「双胞胎表」是这个仓库的核心设计：**结构一样、数据一样，唯一区别是一个有索引一个没有**，所以任何性能对比都是干净的，不需要你相信作者的话。

## 已经验证过的实验数据

这些数字是在 MySQL 8.0.46 上真实跑出来的。**耗时因机器而异，但「扫描行数」是稳定的，那个才值得记。**

```sql
SET profiling = 1;
SELECT COUNT(*) FROM orders_slow WHERE user_id = 42;   -- 0.024s，扫 199430 行
SELECT COUNT(*) FROM orders      WHERE user_id = 42;   -- 0.0003s，扫     29 行
SHOW PROFILES;
```

| | `orders_slow`（无索引） | `orders`（有索引） |
|---|---|---|
| `type` | `ALL`（全表扫描） | `ref`（走索引） |
| `key` | `NULL` | `idx_orders_user` |
| **rows（扫描行数）** | **199430** | **29** |
| 耗时（本机实测） | ~0.024 s | ~0.0003 s |

扫描行数差了 6874 倍。完整实验在 [第 13 篇](docs/13-index-what.md)。

## 配套实验文件怎么用

`lab/queries/` 里是每一篇对应的可执行 SQL，文件名就是文章编号：

```powershell
# 方式一：命令行走一遍（推荐，输出最干净）
docker cp lab/queries/13-demo-index.sql easy-mysql:/tmp/
docker exec easy-mysql mysql -uroot -peasy123 -t -e "source /tmp/13-demo-index.sql"

# 方式二：图形界面，把文件拖进 Adminer 的查询窗口
```

> ⚠️ **Windows PowerShell 用户注意**：不要用 `Get-Content | docker exec` 这种管道传 SQL 文件，
> PowerShell 会把 UTF-8 中文转成 GBK，SQL 里的中文标识符会全部报错。用上面两种方式之一。

想一次性检查所有实验文件是否还能跑通：

```powershell
powershell -ExecutionPolicy Bypass -File lab/verify-queries.ps1
# 期望输出「错误总数: 3」——这 3 条是故意写错的语句，用来演示数据库如何拦截脏数据
```

## 目录结构

```
EasyMysql/
├── README.md              # 你在这里
├── NOTES.md               # 完整选题表 + 写作进度 + 踩坑记录
├── docs/                  # 23 篇正文 + 3 个附录，一篇一个 md
│   ├── 00-写在前面.md      # 新手先读这篇
│   └── _TEMPLATE.md       # 写作模板（想贡献新文章看这里）
├── lab/                   # ★ 可运行的实验环境
│   ├── docker-compose.yml # 一键起 MySQL 8.0 + Adminer
│   ├── init/              # 建表 + 造 80 万行数据
│   ├── queries/           # 每篇一个配套实验文件（18 个）
│   ├── reset.ps1          # 30 秒重置环境 + 校验行数
│   ├── verify-queries.ps1 # 批量检查所有实验文件
│   └── README.md          # 环境安装 / 重置 / 备份 / 排查
├── .github/               # Issue 模板
└── LICENSE                # MIT
```

> 改坏了别慌：`powershell -ExecutionPolicy Bypass -File lab/reset.ps1` 30 秒回到出厂设置。

## 参与贡献

这个仓库最有价值的东西是**实验数据**，而不是文字。所以：

- 发现了错误 → 提 [Issue](https://github.com/你的用户名/EasyMysql/issues)，**请附上你跑出来的输出**
- 想加一篇文章 → 看 [docs/_TEMPLATE.md](docs/_TEMPLATE.md)，照着模板写，并配上 `lab/queries/` 里的实验文件
- 提 PR 前请自己跑一遍 `lab/verify-queries.ps1`

## 写作原则（也是这个仓库的验收标准）

1. 所有 SQL 都能复制粘贴直接跑，**不写伪代码**
2. 每篇结论都必须有**真实输出**撑着
3. 每篇开头先说「**什么时候你会遇到它**」，把知识锚到痛点
4. 单篇不超过 2000 字，超过就拆上下篇
5. 造错数据比讲对知识更有说服力

## License

[MIT](LICENSE) · 内容仅供学习，示例数据为脚本生成，不含任何真实个人信息
