-- 12-demo-design.sql · 第 12 篇配套实验（建表模板 + 逻辑删除的坑）
--
-- 本文件 0 条错误：建模板表 → 验证三个必备字段 → 演示逻辑删除的唯一索引坑 → 全部 DROP 干净。

SET NAMES utf8mb4;

USE easy_mysql;

-- ===== 1. 可直接抄的建表模板（和正文第 6 节一字不差）=====
CREATE TABLE products (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT                COMMENT '主键',
  sku         VARCHAR(32)     NOT NULL                               COMMENT '商品编码，全局唯一',
  name        VARCHAR(64)     NOT NULL                               COMMENT '商品名',
  category_id INT UNSIGNED    NOT NULL                               COMMENT '分类 id（逻辑外键，不建物理外键）',
  price       DECIMAL(10,2)   NOT NULL DEFAULT 0.00                  COMMENT '单价，金额一律 DECIMAL',
  stock       INT UNSIGNED    NOT NULL DEFAULT 0                     COMMENT '库存',
  status      TINYINT         NOT NULL DEFAULT 1                     COMMENT '1 上架 0 下架',
  created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP     COMMENT '创建时间，不用手填',
  updated_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP
                                ON UPDATE CURRENT_TIMESTAMP          COMMENT '更新时间，改行自动跳',
  is_deleted  TINYINT         NOT NULL DEFAULT 0                     COMMENT '0 正常 1 逻辑删除',
  PRIMARY KEY (id),
  UNIQUE KEY uk_sku (sku),
  UNIQUE KEY uk_name_is_deleted (name, is_deleted),
  KEY idx_status_created (status, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='商品表（建表模板）';
SHOW CREATE TABLE products\G

-- ===== 2. 三个必备字段：默认值生效 + 更新时间自动跳 =====
INSERT INTO products (sku, name, category_id, price, stock)
VALUES ('KB-001', '机械键盘', 3, 299.00, 50);
SELECT id, sku, name, price, stock, created_at, updated_at, is_deleted FROM products;
DO SLEEP(1);
UPDATE products SET price = 279.00 WHERE id = 1;
SELECT id, sku, name, price, stock, created_at, updated_at, is_deleted FROM products;
-- created_at 没动，updated_at 自己往前跳了一秒

-- ===== 3. 逻辑删除的坑：唯一索引不带 is_deleted =====
CREATE TABLE demo_member_bad (
  id         INT NOT NULL AUTO_INCREMENT,
  email      VARCHAR(60) NOT NULL,
  is_deleted TINYINT NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  UNIQUE KEY uk_email (email)                     -- ✗ 少了 is_deleted
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='反面：唯一索引没带 is_deleted';
CREATE TABLE demo_member_good (
  id         INT NOT NULL AUTO_INCREMENT,
  email      VARCHAR(60) NOT NULL,
  is_deleted TINYINT NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  UNIQUE KEY uk_email_is_deleted (email, is_deleted)   -- ✓ 带上 is_deleted
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='正面：唯一索引带 is_deleted';
INSERT INTO demo_member_bad  (email) VALUES ('amy@example.com');
INSERT INTO demo_member_good (email) VALUES ('amy@example.com');

-- 逻辑删除不是真删，是打标记
UPDATE demo_member_bad  SET is_deleted = 1 WHERE email = 'amy@example.com';
UPDATE demo_member_good SET is_deleted = 1 WHERE email = 'amy@example.com';

-- 同一个邮箱回头再注册一次（用 IGNORE 是为了让文件不中断：
--   不加 IGNORE 会直接报 ERROR 1062，报错原文在正文里）
INSERT IGNORE INTO demo_member_bad (email) VALUES ('amy@example.com');
SHOW WARNINGS;   -- 1062 Duplicate entry ... 被旧的唯一索引挡掉了
INSERT IGNORE INTO demo_member_good (email) VALUES ('amy@example.com');
SHOW WARNINGS;   -- 没被挡

SELECT '没带 is_deleted（被挡）' AS 版本, email, is_deleted FROM demo_member_bad
UNION ALL
SELECT '带 is_deleted（正常）', email, is_deleted FROM demo_member_good;

-- ===== 4. 收尾：模板表和演示表全部删干净 =====
DROP TABLE products, demo_member_bad, demo_member_good;
SHOW TABLES;
