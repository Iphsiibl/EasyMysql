# 12 · 建表军规：一份可以直接抄的模板

> **一句话价值**：拿到一个建表需求，知道该问哪几个问题、该按什么顺序写 DDL。

**难度**：⭐⭐　|　**时长**：约 25 分钟　|　**涉及表**：全部

## 什么时候你会遇到它

产品说「加个功能，记录用户的收货地址」。你 `CREATE TABLE addresses (...)` 完事上线，三个月后发现用户要能存 20 个地址、地址要能设默认 —— 表要推倒重来。

## 本篇你会学到

- [ ] 建表前必须问清的 7 个问题
- [ ] 命名的 6 条约定（`user` 还是 `users`、是否用复数、是否带表前缀）
- [ ] 常用字段：创建时间、更新时间、逻辑删除 `is_deleted`
- [ ] 三范式在真实业务里怎么落地
- [ ] 「什么字段该冗余」与冗余的同步成本
- [ ] **可直接复制的建表模板**

## 正文大纲

1. **先问 7 个问题**（业务名、数据量、增长、查询方式、是否唯一、是否必填、是否要留历史）
2. **命名约定**：`snake_case`、不用保留字、不用缩写
3. **三个必备字段**：
   ```sql
   created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
   updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
   is_deleted TINYINT(1) NOT NULL DEFAULT 0 COMMENT '0 正常 1 删除'
   ```
4. **范式 vs 反范式**：用户订单表里为什么可以冗余用户名
5. **逻辑删除的代价**（唯一索引要带上 `is_deleted`）
6. **建表模板**：贴一份 30 行、带全部注释的规范 DDL
7. **改表的正确姿势**：`ALTER TABLE` 的锁表风险、`pt-online-schema-change`

## 动手练

- [ ] 按模板设计「商品评价表」，写出完整 DDL
- [ ] 说出你的表在数据量到 1 亿行时，哪个设计要先改

## 参考输出

模板见本文第 6 节。

## 下一篇

[13 · 索引是什么：给数据库做目录](13-index-what.md)
