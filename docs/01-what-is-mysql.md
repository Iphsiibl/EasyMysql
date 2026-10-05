# 01 · MySQL 是什么：从零把它跑起来

> **一句话价值**：在自己电脑上装好 MySQL，并连上它敲出第一条 SQL。

**难度**：⭐　|　**时长**：约 20 分钟　|　**涉及表**：无

## 什么时候你会遇到它

你写了第一个网页作业，页面能跑，但一点「保存」就报错；或者你用别人现成的数据库脚本，`import` 的时候满屏红色英文。这一切都从「你没碰过数据库」开始。

## 本篇你会学到

- [ ] 数据库和 MySQL 到底什么关系（用「Excel 文件」类比）
- [ ] 三种装法：Docker（推荐）、Windows 免安装版、在线沙盒
- [ ] 用客户端连上数据库，并确认连对了

## 正文大纲

1. **先建立直觉**：数据库 ≠ Excel 文件。为什么要用服务器程序？
2. **Docker 一行命令搞定**（本仓库 lab/ 已配好，照抄即可）
   ```powershell
   cd lab
   docker compose up -d
   docker exec -it easy-mysql mysql -uroot -peasy123 -t
   ```
3. **不装 Docker 的两条路**：Windows 免安装版解压即用 / 浏览器在线沙盒
4. **连接参数的含义**：host、port、user、password 四个值分别指什么
5. **验证成功**：敲 `SELECT VERSION();` 看版本号

## 动手练

- [ ] 用三种方式各连一次数据库，说出它们各自的优缺点
- [ ] 把 `docker compose down` 和 `down -v` 都执行一次，观察数据库数据还在不在，解释区别

## 参考输出

见 `lab/README.md`，安装成功后会看到 MySQL 8.0.x 的版本横幅。

## 下一篇

[02 · 数据库、表、行、列：先搞懂这四个词](02-db-table-row-column.md)
