-- 22-demo-privileges.sql · 第 22 篇配套实验

SET NAMES utf8mb4;

-- ⚠ 会创建和删除用户，请在自己的练习环境执行

USE easy_mysql;

-- ============================================================
-- 1. 看看现在有哪些用户
-- ============================================================
SELECT user, host, plugin FROM mysql.user;
-- 当前连接用户
SELECT USER() AS 当前用户, CURRENT_USER() AS 认证用户, @@port AS 端口;

-- ============================================================
-- 2. 最小权限：建三个角色账号
-- ============================================================
-- 运维账号：权限最大，但仍不该在代码里用
CREATE USER IF NOT EXISTS 'ops_demo'@'%' IDENTIFIED BY 'Ops#Demo2026';
GRANT ALL PRIVILEGES ON easy_mysql.* TO 'ops_demo'@'%';

-- 只读账号：报表、BI、数据分析用这个
CREATE USER IF NOT EXISTS 'ro_demo'@'%' IDENTIFIED BY 'Ro#Demo2026';
GRANT SELECT, SHOW VIEW ON easy_mysql.* TO 'ro_demo'@'%';

-- 应用账号：只给业务真正用到的读写权限，不给 DROP / ALTER
CREATE USER IF NOT EXISTS 'app_demo'@'%' IDENTIFIED BY 'App#Demo2026';
GRANT SELECT, INSERT, UPDATE, DELETE ON easy_mysql.orders   TO 'app_demo'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON easy_mysql.order_items TO 'app_demo'@'%';
GRANT SELECT ON easy_mysql.users TO 'app_demo'@'%';   -- 只读！不该让应用改用户表

-- 生效并查看
FLUSH PRIVILEGES;
SHOW GRANTS FOR 'app_demo'@'%';

-- ============================================================
-- 3. ★ 验证权限真的生效（换个客户端连进去试）
-- ============================================================
-- 权限不是靠 SHOW GRANTS "看着对"就算数的，要用真账号连一次。
-- 在另一个 PowerShell 窗口执行（正文里原样跑过）：
--
--   docker exec easy-mysql mysql -uro_demo -p"Ro#Demo2026" -t easy_mysql -e "SELECT COUNT(*) FROM users;"
--   docker exec easy-mysql mysql -uro_demo -p"Ro#Demo2026" -t easy_mysql -e "DELETE FROM users WHERE id = 1;"
--   docker exec easy-mysql mysql -uro_demo -p"Ro#Demo2026" -t easy_mysql -e "USE mysql;"
--
-- 期望：第一条返回 5000，第二条
--   ERROR 1142 (42000) at line 1: DELETE command denied to user 'ro_demo'@'localhost' for table 'users'
-- 第三条
--   ERROR 1044 (42000) at line 1: Access denied for user 'ro_demo'@'%' to database 'mysql'
--
-- ★ 关键点：ro_demo 连 DROP 都不行。
--   就算你代码里拼错了 SQL，最坏结果也只是「权限不足」，
--   而不是「整张表没了」。这就是最小权限原则的价值。

-- ============================================================
-- 4. 收紧和收回权限
-- ============================================================
REVOKE DELETE ON easy_mysql.orders FROM 'app_demo'@'%';
SHOW GRANTS FOR 'app_demo'@'%';

-- 只允许特定网段访问，而不是任意主机
CREATE USER IF NOT EXISTS 'ro_demo'@'192.168.1.%' IDENTIFIED BY 'Ro#Demo2026';
SHOW GRANTS FOR 'ro_demo'@'192.168.1.%';
-- '%' 表示任意主机，生产环境务必限制

-- 内网只读账号：只认 192.168.1 网段（正文第 4 节跑过）
CREATE USER IF NOT EXISTS 'lan_ro'@'192.168.1.%' IDENTIFIED BY 'Lan#Demo2026';
SHOW GRANTS FOR 'lan_ro'@'192.168.1.%';
-- 从别的网段连过去，密码全对也进不来：
--   docker exec easy-mysql mysql -ulan_ro -p"Lan#Demo2026" -h 127.0.0.1 -t easy_mysql -e "SELECT 1;"
--   ERROR 1045 (28000): Access denied for user 'lan_ro'@'127.0.0.1' (using password: YES)

-- ============================================================
-- 5. 改密码 / 删用户
-- ============================================================
ALTER USER 'ro_demo'@'%' IDENTIFIED BY 'NewRo#Demo2026';
DROP USER IF EXISTS 'ro_demo'@'%';
DROP USER IF EXISTS 'ro_demo'@'192.168.1.%';
DROP USER IF EXISTS 'app_demo'@'%';
DROP USER IF EXISTS 'ops_demo'@'%';
DROP USER IF EXISTS 'lan_ro'@'192.168.1.%';
FLUSH PRIVILEGES;
SELECT user, host FROM mysql.user;

-- ============================================================
-- 6. ★ SQL 注入演示与防御
-- ============================================================
-- ❌ 危险写法：字符串拼接
--    假设 Java 代码是 "SELECT * FROM users WHERE username = '" + input + "'"
--    攻击者输入：' OR '1'='1
--    拼出来的 SQL 变成：
--      SELECT * FROM users WHERE username = '' OR '1'='1'
--    整个用户表都被返回了
--
-- ✅ 唯一正解：预编译参数化（PreparedStatement）
--    Java:  PreparedStatement ps = conn.prepareStatement(
--             "SELECT * FROM users WHERE username = ?");
--           ps.setString(1, input);
--    Python: cursor.execute("SELECT * FROM users WHERE username = %s", (input,))
--    Node:   connection.execute('SELECT * FROM users WHERE username = ?', [input])
--
--    预编译不是把 SQL 变「安全」，而是让数据和指令彻底分离：
--    无论 input 是什么，都只会被当成一个「值」，不会被当成 SQL 语法。
--
-- 模拟一下拼接的效果（看清楚就好，别真拿去连生产库）
SELECT id, username FROM users LIMIT 3;
-- 相当于 WHERE username = '' OR '1'='1'，结果就是全表
SELECT COUNT(*) AS 拼接出来的结果 FROM users WHERE username = '' OR '1'='1';

-- ✅ 预编译参数化：同样的输入，换 PREPARE 再跑一遍
PREPARE login FROM 'SELECT COUNT(*) FROM users WHERE username = ?';
SET @input = ''' OR ''1'' = ''1''';
EXECUTE login USING @input;              -- 攻击载荷被当成普通字符串，0 行
SET @input = 'user_00001';
EXECUTE login USING @input;              -- 正常用户名，1 行
DEALLOCATE PREPARE login;

-- ✅ 白名单：ORDER BY / LIMIT 这种没法用 ? 的地方，只认名单里的值
SET @sort = 'age';
SELECT IF(@sort IN ('id','age','balance'), CONCAT('允许：按 ', @sort, ' 排序'), '拒绝：不在白名单里') AS 检查;
SET @sort = 'id; DROP TABLE users';
SELECT IF(@sort IN ('id','age','balance'), CONCAT('允许：按 ', @sort, ' 排序'), '拒绝：不在白名单里') AS 检查;

-- ============================================================
-- 7. 其他安全清单
-- ============================================================
-- 改 root 密码（本仓库是练习环境，真实环境务必改）
--   ALTER USER 'root'@'%' IDENTIFIED BY 'StrongPassword!';
--
-- 删除所有匿名用户
--   SELECT user, host FROM mysql.user WHERE user = '';
--   DELETE FROM mysql.user WHERE user = '';
--   FLUSH PRIVILEGES;
--
-- 删掉 test 库
--   DROP DATABASE IF EXISTS test;
--
-- 查当前允许的连接数
SELECT @@max_connections AS 最大连接数, @@wait_timeout AS 空闲超时秒;

-- 连接配置该放哪：
--   ✗ 硬编码在代码里
--   ✗ 提交 .yml / .env 到 GitHub
--   ✓ 环境变量 / 配置中心 / 本地 .env + .gitignore
SELECT @@version_comment AS 版本说明, VERSION() AS 版本;
