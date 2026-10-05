# 21 · 备份与恢复：先假设数据库会消失

> **一句话价值**：会用 `mysqldump` 备份和恢复，并知道「逻辑备份」和「物理备份」的区别。

**难度**：⭐⭐　|　**时长**：约 30 分钟　|　**涉及表**：全部

## 什么时候你会遇到它

`DROP DATABASE school;` 手一抖，你花了一整个学期录入的数据没了。**备份这件事，只有在出事那天你才会发现它重不重要。**

## 本篇你会学到

- [ ] 逻辑备份 vs 物理备份 vs binlog
- [ ] `mysqldump` 常用参数（`--single-transaction`、`--databases`、`--routines`）
- [ ] 完整备份 + 增量备份的组合
- [ ] 恢复演练：**没验证过的备份等于没有备份**
- [ ] 定时备份脚本

## 正文大纲

1. **三种备份方式对照表**
2. **全量备份一条命令**：
   ```bash
   docker exec easy-mysql mysqldump -uroot -peasy123 \
     --single-transaction --databases easy_mysql > backup.sql
   ```
3. **恢复**：`mysql -uroot -p < backup.sql`
4. **只备份结构 / 只备份数据**：`--no-data` / `--no-create-info`
5. **用 binlog 做「回到误删前」**：`--start-datetime` 参数演示
6. **写一个每天凌晨 3 点的备份脚本**（Windows + Linux 各一份）
7. **恢复演练流程**：备份 → 删库 → 恢复 → 校验行数

## 动手练

- [ ] 完整走一遍「备份 → 删库 → 恢复」
- [ ] 把 `users` 表的备份单独恢复到一个新库 `easy_mysql_restore` 里

## 参考输出

`lab/README.md` 的「备份与恢复」一节

## 下一篇

[22 · 权限与安全：别用 root 写代码](22-permission-security.md)
