-- =============================================================================
-- 01-schema.sql  建表脚本
-- 首次启动容器时自动执行（docker-entrypoint-initdb.d 只在数据目录为空时跑）
-- 重新执行请看 lab/README.md 的「重置数据库」一节
--
-- ★ 第 2 行的 SET NAMES utf8mb4 千万不能删！
--   官方镜像的 entrypoint 调 mysql 客户端时没带 --default-character-set，
--   客户端会退回 latin1，于是脚本里的中文被当成 latin1 再转成 utf8mb4，
--   存进去是双重编码的乱码（'男' 会变成 3 个字符，ENUM('男','女') 也会变坏）。
--   这一行相当于告诉客户端「文件里的字节是 utf8mb4」。
-- =============================================================================

SET NAMES utf8mb4;

USE easy_mysql;

-- 删除顺序 = 外键依赖的逆序
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders_slow;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS users;
DROP TABLE IF EXISTS scores;
DROP TABLE IF EXISTS courses;
DROP TABLE IF EXISTS students;
DROP TABLE IF EXISTS bad_design_demo;

-- =============================================================================
-- 第一部分：学校数据集（第 03~07 篇用）
-- 场景贴近在校学生：查成绩、查选课、算平均分
-- =============================================================================

CREATE TABLE students (
  id         INT UNSIGNED    NOT NULL AUTO_INCREMENT COMMENT '主键',
  name       VARCHAR(30)     NOT NULL                COMMENT '姓名',
  gender     ENUM('男','女') NOT NULL DEFAULT '男'    COMMENT '性别',
  class_name VARCHAR(30)     NOT NULL                COMMENT '班级',
  birth_date DATE            NOT NULL                COMMENT '出生日期',
  city       VARCHAR(30)     NOT NULL DEFAULT '未知'  COMMENT '城市',
  created_at DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_students_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='学生表';

CREATE TABLE courses (
  id      INT UNSIGNED NOT NULL AUTO_INCREMENT,
  name    VARCHAR(50)  NOT NULL             COMMENT '课程名',
  credit  DECIMAL(3,1) NOT NULL DEFAULT 2.0 COMMENT '学分',
  teacher VARCHAR(30)  NOT NULL             COMMENT '任课老师',
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='课程表';

CREATE TABLE scores (
  id         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  student_id INT UNSIGNED NOT NULL            COMMENT '学生 id',
  course_id  INT UNSIGNED NOT NULL            COMMENT '课程 id',
  score      DECIMAL(5,2) NOT NULL            COMMENT '分数 0~100',
  exam_date  DATE NOT NULL                    COMMENT '考试日期',
  PRIMARY KEY (id),
  -- 复合唯一：同一学生同一门课只能有一条成绩
  UNIQUE KEY uk_scores_student_course (student_id, course_id),
  KEY idx_scores_course (course_id),
  CONSTRAINT fk_scores_student FOREIGN KEY (student_id) REFERENCES students (id),
  CONSTRAINT fk_scores_course  FOREIGN KEY (course_id)  REFERENCES courses (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='成绩表';

-- =============================================================================
-- 第二部分：电商数据集（第 11~15 篇索引/事务/锁用）
-- 数据量大、有意保留一张没索引的对照表，方便做前后对比实验
-- =============================================================================

CREATE TABLE users (
  id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  username   VARCHAR(30)     NOT NULL              COMMENT '用户名',
  email      VARCHAR(60)     NOT NULL              COMMENT '邮箱',
  city       VARCHAR(20)     NOT NULL              COMMENT '城市',
  age        TINYINT UNSIGNED NOT NULL DEFAULT 0   COMMENT '年龄',
  status     TINYINT         NOT NULL DEFAULT 1    COMMENT '1 正常 0 禁用',
  balance    DECIMAL(12,2)   NOT NULL DEFAULT 0.00 COMMENT '余额',
  created_at DATETIME        NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_users_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='用户表';

-- 重点表：有索引。20 万行
CREATE TABLE orders (
  id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id    BIGINT UNSIGNED NOT NULL              COMMENT '下单用户',
  product_id INT UNSIGNED    NOT NULL              COMMENT '商品',
  quantity   INT UNSIGNED    NOT NULL DEFAULT 1,
  amount     DECIMAL(10,2)   NOT NULL              COMMENT '订单金额',
  status     ENUM('created','paid','shipped','cancelled') NOT NULL DEFAULT 'created',
  created_at DATETIME        NOT NULL,
  updated_at DATETIME        NOT NULL,
  PRIMARY KEY (id),
  KEY idx_orders_user (user_id),
  KEY idx_orders_status_created (status, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='订单表（有索引）';

-- 对照表：字段和 orders 一模一样，唯一区别是没有任何索引
-- 第 11、13 篇用它做「加索引前 vs 加索引后」的耗时对比
CREATE TABLE orders_slow (
  id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id    BIGINT UNSIGNED NOT NULL,
  product_id INT UNSIGNED    NOT NULL,
  quantity   INT UNSIGNED    NOT NULL DEFAULT 1,
  amount     DECIMAL(10,2)   NOT NULL,
  status     ENUM('created','paid','shipped','cancelled') NOT NULL DEFAULT 'created',
  created_at DATETIME        NOT NULL,
  updated_at DATETIME        NOT NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='订单表（无索引对照组）';

-- 订单明细：60 万行
-- 故意不建物理外键，真实生产中大表外键会带来写入开销和锁竞争
CREATE TABLE order_items (
  id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  order_id     BIGINT UNSIGNED NOT NULL              COMMENT '所属订单',
  product_name VARCHAR(60)     NOT NULL              COMMENT '商品名',
  price        DECIMAL(10,2)   NOT NULL,
  quantity     INT UNSIGNED    NOT NULL DEFAULT 1,
  PRIMARY KEY (id),
  KEY idx_items_order (order_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='订单明细表';

-- =============================================================================
-- 第三部分：反面教材（第 08 篇「数据类型怎么选」用）
-- 故意写得很差的一组字段，第 08 篇会逐个拆解并给出正确写法
-- =============================================================================

CREATE TABLE bad_design_demo (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_name   VARCHAR(200) NOT NULL  COMMENT '✗ 名字用超长字符串，浪费空间',
  birthday    VARCHAR(50)  NOT NULL  COMMENT '✗ 日期用字符串存，无法比较大小',
  phone       DOUBLE       NOT NULL  COMMENT '✗ 手机号用数值存，会丢前导 0 和精度',
  price       VARCHAR(50)  NOT NULL  COMMENT '✗ 金额用字符串存，排序和求和都错',
  is_man      VARCHAR(10)  NOT NULL  COMMENT '✗ 布尔值用字符串存',
  create_time VARCHAR(50)  NOT NULL  COMMENT '✗ 时间用字符串存',
  extra       JSON         NULL      COMMENT '✗ 把各种字段全塞进 JSON',
  remark      TEXT         NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='反面教材（教学用，别照抄）';
