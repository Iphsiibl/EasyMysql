# 22 · 权限与安全：别用 root 写代码

> **一句话价值**：建三个各管一段的账号，让「代码写错 SQL」的最坏结果从「表没了」变成一句 `ERROR 1142`。

**难度**：⭐⭐　|　**时长**：约 30 分钟　|　**涉及表**：`users`、`orders`

## 什么时候你会遇到它

课程项目的配置文件里写着 `user: root / password: easy123`，你把它推上了 GitHub。代码一开源，这两个字串就跟着开源了 —— 数据库开着公网端口的话，四十分钟之内就会有人替你「检查」一遍 `users` 表。

权限这件事的麻烦在于：**你给出去的每一分权限，都会在未来的某次 bug 里兑现。**

## 本篇你会学到

- [ ] 运维、报表、应用三个账号**各自该给哪些权限**
- [ ] 用真客户端验证权限：`ERROR 1142` 和 `ERROR 1044` 分别在说什么
- [ ] `USER()` 与 `CURRENT_USER()` 差的那个 `@host`，`ERROR 1045` 就藏在缝里
- [ ] `REVOKE` 收权、`ALTER USER` 改密、`DROP USER` 删号的完整流程
- [ ] SQL 注入的拼接与预编译对打，白名单管住拼不进参数的地方
- [ ] 连接配置放哪：一张对比表

---

## 1. 最小权限原则：三个账号各管一段

最小权限原则（principle of least privilege）：**只给刚好够用的权限，多一分都不给。**落到本库的 8 张表上：

| 账号 | 干什么 | 该给的权限 | 绝不该给 |
|---|---|---|---|
| 运维 `ops_demo` | 建表、改结构、备份恢复 | `ALL PRIVILEGES ON easy_mysql.*` | 写进任何应用代码 |
| 报表 `ro_demo` | 查数、出报表、连 BI | `SELECT`（配 `SHOW VIEW`） | `INSERT` / `UPDATE` / `DELETE` |
| 应用 `app_demo` | 业务读写订单 | `orders` 的 `SELECT, INSERT, UPDATE, DELETE` + `users` 的 `SELECT` | `DROP` / `ALTER`；`users` 的写权 |

判断口诀：**这条 SQL 真的会出现在你的代码里吗？不会出现在代码里的权限，一律不授权。**应用要查用户名核对身份，那就只给读 `users`；应用要改订单状态，改权限只给到 `orders` 这一张表。

## 2. 建账号：CREATE USER + GRANT

三条命令，三条 `SHOW GRANTS` 回执（本机 PowerShell 里逐条跑过）：

```powershell
docker exec easy-mysql mysql -uroot -peasy123 -t -e "CREATE USER IF NOT EXISTS 'ro_demo'@'%' IDENTIFIED BY 'Ro#Demo2026'; GRANT SELECT, SHOW VIEW ON easy_mysql.* TO 'ro_demo'@'%'; SHOW GRANTS FOR 'ro_demo'@'%';"
docker exec easy-mysql mysql -uroot -peasy123 -t -e "CREATE USER IF NOT EXISTS 'app_demo'@'%' IDENTIFIED BY 'App#Demo2026'; GRANT SELECT, INSERT, UPDATE, DELETE ON easy_mysql.orders TO 'app_demo'@'%'; GRANT SELECT ON easy_mysql.users TO 'app_demo'@'%'; SHOW GRANTS FOR 'app_demo'@'%';"
docker exec easy-mysql mysql -uroot -peasy123 -t -e "CREATE USER IF NOT EXISTS 'ops_demo'@'%' IDENTIFIED BY 'Ops#Demo2026'; GRANT ALL PRIVILEGES ON easy_mysql.* TO 'ops_demo'@'%'; SHOW GRANTS FOR 'ops_demo'@'%';"
```

```text
+------------------------------------------------------------+
| Grants for ro_demo@%                                       |
+------------------------------------------------------------+
| GRANT USAGE ON *.* TO `ro_demo`@`%`                        |
| GRANT SELECT, SHOW VIEW ON `easy_mysql`.* TO `ro_demo`@`%` |
+------------------------------------------------------------+
+---------------------------------------------------------------------------------+
| Grants for app_demo@%                                                           |
+---------------------------------------------------------------------------------+
| GRANT USAGE ON *.* TO `app_demo`@`%`                                            |
| GRANT SELECT, INSERT, UPDATE, DELETE ON `easy_mysql`.`orders` TO `app_demo`@`%` |
| GRANT SELECT ON `easy_mysql`.`users` TO `app_demo`@`%`                          |
+---------------------------------------------------------------------------------+
+----------------------------------------------------------+
| Grants for ops_demo@%                                    |
+----------------------------------------------------------+
| GRANT USAGE ON *.* TO `ops_demo`@`%`                     |
| GRANT ALL PRIVILEGES ON `easy_mysql`.* TO `ops_demo`@`%` |
+----------------------------------------------------------+
```

逐行读三件事：

- 第一行的 `USAGE ON *.*` 是每个账号自带的底子，意思是「能连上、别的全局权限一概没有」，不是你授的。
- 授权粒度从粗到细：`ops_demo` 是**整库** `easy_mysql.*`，`app_demo` 精确到**表** `easy_mysql`.`orders`。能用表级就别给库级。
- `app_demo` 对 `users` 只有 `SELECT`：应用要拿用户名核对身份，但**改用户表的口子一个都没开**。

## 3. 验证：换一个客户端连进去，故意删一行

`SHOW GRANTS` 看着对不算数，得拿真账号连一次。下面三条命令就是三个「心怀不轨的调用方」：

```powershell
docker exec easy-mysql mysql -uro_demo -p"Ro#Demo2026" -t easy_mysql -e "SELECT COUNT(*) FROM users;"
```

```text
+----------+
| COUNT(*) |
+----------+
|     5000 |
+----------+
```

```powershell
docker exec easy-mysql mysql -uro_demo -p"Ro#Demo2026" -t easy_mysql -e "DELETE FROM users WHERE id = 1;"
docker exec easy-mysql mysql -uro_demo -p"Ro#Demo2026" -t easy_mysql -e "USE mysql;"
```

```text
ERROR 1142 (42000) at line 1: DELETE command denied to user 'ro_demo'@'localhost' for table 'users'
ERROR 1044 (42000) at line 1: Access denied for user 'ro_demo'@'%' to database 'mysql'
```

（`mysql: [Warning] Using a password ...` 这行是 stderr 的密码警告，下同，不再贴。）

两条报错分工很明确：

| 报错 | 服务器在说什么 | 你错在哪 |
|---|---|---|
| `ERROR 1142` | 库在、表在，你没有 `DELETE` 这项权限 | 想动不该动的表 |
| `ERROR 1044` | 你连 `mysql` 这个库都进不去 | 手伸得太长，摸系统库 |

`UPDATE`、`CREATE TABLE` 同样打回 `1142`（本篇写作时都跑过）。**这就是第 1 节那张表的全部意义**：代码里的 SQL 拼错了、被注入了，最坏结果是一句报错，而不是 `users` 表少了一半。

## 4. 你在连的是谁：`@host` 和 `%` 的坑

同一个账号，`USER()` 报的是「我从哪台机器连过来」，`CURRENT_USER()` 报的是「服务器翻出哪条账号记录认的我」。带上 `-h 127.0.0.1` 走 TCP 连一次：

```powershell
docker exec easy-mysql mysql -uro_demo -p"Ro#Demo2026" -h 127.0.0.1 -t easy_mysql -e "SELECT USER() AS client_user, CURRENT_USER() AS matched_account, @@port AS port;"
```

```text
+-------------------+-----------------+------+
| client_user       | matched_account | port |
+-------------------+-----------------+------+
| ro_demo@127.0.0.1 | ro_demo@%       | 3306 |
+-------------------+-----------------+------+
```

`client_user` 那列是你连过来时的落点（容器里客户端连自己的 3306 端口），`matched_account` 那列才是账号表里真正生效的那行 `ro_demo@%`。**`ERROR 1045` 的报错文案用的是前者**：

```powershell
docker exec easy-mysql mysql -uro_demo -p"wrongpass" -h 127.0.0.1 -t easy_mysql -e "SELECT 1;"
```

```text
ERROR 1045 (28000): Access denied for user 'ro_demo'@'127.0.0.1' (using password: YES)
```

所以见到 `1045` 别只盯着密码：**报错里的 `@host` 是你的落点，账号表里存的是另一回事**，host 对不上一样是这条。

**`%` 就是「任意主机」**，建账号时漏写 host，服务器默认给你 `%`：

```powershell
docker exec easy-mysql mysql -uroot -peasy123 -t -e "CREATE USER IF NOT EXISTS 'nohost' IDENTIFIED BY 'X#Demo2026'; SELECT user, host FROM mysql.user WHERE user = 'nohost'; DROP USER IF EXISTS 'nohost';"
```

```text
+--------+------+
| user   | host |
+--------+------+
| nohost | %    |
+--------+------+
```

内网只读账号该写成网段：

```powershell
docker exec easy-mysql mysql -uroot -peasy123 -t -e "CREATE USER 'lan_ro'@'192.168.1.%' IDENTIFIED BY 'Lan#Demo2026'; SHOW GRANTS FOR 'lan_ro'@'192.168.1.%';"
docker exec easy-mysql mysql -ulan_ro -p"Lan#Demo2026" -h 127.0.0.1 -t easy_mysql -e "SELECT 1;"
```

```text
+----------------------------------------------+
| Grants for lan_ro@192.168.1.%                |
+----------------------------------------------+
| GRANT USAGE ON *.* TO `lan_ro`@`192.168.1.%` |
+----------------------------------------------+
ERROR 1045 (28000): Access denied for user 'lan_ro'@'127.0.0.1' (using password: YES)
```

账号只认 `192.168.1.x` 网段，我从 `127.0.0.1` 连，**密码全对也进不来** —— host 不在名单里，服务器根本不查密码。局域网之外的机器连尝试的机会都没有。

## 5. 写入、收回、改密、删号

先让应用账号干一次活，再把权限收回来。注意这条命令带了 `--default-character-set=utf8mb4`，中文列名才不会被客户端按 latin1 读坏：

```powershell
docker exec easy-mysql mysql -uapp_demo -p"App#Demo2026" -t --default-character-set=utf8mb4 easy_mysql -e "INSERT INTO orders (user_id, product_id, quantity, amount, status, created_at, updated_at) VALUES (1, 1001, 1, 9.99, 'created', NOW(), NOW()); SELECT COUNT(*) AS 写入之后 FROM orders;"
```

```text
+--------------+
| 写入之后     |
+--------------+
|       200001 |
+--------------+
```

```powershell
docker exec easy-mysql mysql -uroot -peasy123 -t -e "REVOKE UPDATE ON easy_mysql.orders FROM 'app_demo'@'%'; SHOW GRANTS FOR 'app_demo'@'%';"
docker exec easy-mysql mysql -uapp_demo -p"App#Demo2026" -t easy_mysql -e "UPDATE orders SET amount = 9.99 WHERE id = (SELECT id FROM (SELECT MAX(id) AS id FROM orders) x);"
```

```text
+-------------------------------------------------------------------------+
| Grants for app_demo@%                                                   |
+-------------------------------------------------------------------------+
| GRANT USAGE ON *.* TO `app_demo`@`%`                                    |
| GRANT SELECT, INSERT, DELETE ON `easy_mysql`.`orders` TO `app_demo`@`%` |
| GRANT SELECT ON `easy_mysql`.`users` TO `app_demo`@`%`                  |
+-------------------------------------------------------------------------+
ERROR 1142 (42000) at line 1: UPDATE command denied to user 'app_demo'@'localhost' for table 'orders'
```

`REVOKE` 之后授权表里那一行肉眼可见地少了 `UPDATE`，再试就是 `1142`。权限是**活的**：出问题先收权，比事后追查省事。

改密码和删号各一条链路，注意旧密码立刻失效：

```powershell
docker exec easy-mysql mysql -uroot -peasy123 -e "ALTER USER 'ro_demo'@'%' IDENTIFIED BY 'NewRo#Demo2026';"
docker exec easy-mysql mysql -uro_demo -p"Ro#Demo2026" -t easy_mysql -e "SELECT 1;"
docker exec easy-mysql mysql -uro_demo -p"NewRo#Demo2026" -t easy_mysql -e "SELECT 1 AS new_password_works;"
```

```text
ERROR 1045 (28000): Access denied for user 'ro_demo'@'localhost' (using password: YES)
+--------------------+
| new_password_works |
+--------------------+
|                  1 |
+--------------------+
```

测试订单和五个演示账号一起收尾，跑完账号表回到基线：

```powershell
docker exec easy-mysql mysql -uroot -peasy123 -t -e "DELETE FROM easy_mysql.orders WHERE user_id = 1 AND product_id = 1001 AND amount = 9.99; DROP USER IF EXISTS 'ro_demo'@'%'; DROP USER IF EXISTS 'ro_demo'@'192.168.1.%'; DROP USER IF EXISTS 'app_demo'@'%'; DROP USER IF EXISTS 'ops_demo'@'%'; DROP USER IF EXISTS 'lan_ro'@'192.168.1.%'; SELECT user, host FROM mysql.user; SELECT COUNT(*) AS orders_cnt FROM easy_mysql.orders;"
```

```text
+------------------+-----------+
| user             | host      |
+------------------+-----------+
| root             | %         |
| mysql.infoschema | localhost |
| mysql.session    | localhost |
| mysql.sys        | localhost |
| root             | localhost |
+------------------+-----------+
+------------+
| orders_cnt |
+------------+
|     200000 |
+------------+
```

## 6. SQL 注入：拼接出来的 5000 行

假设登录代码是 `SELECT * FROM users WHERE username = '" + input + "'"`，攻击者输入 `' OR '1'='1`，拼出来的条件变成恒真。用真实数据把「拼接」的效果摆出来（这里用 root 跑，注入跟权限无关）：

```powershell
docker exec easy-mysql mysql -uroot -peasy123 -t --default-character-set=utf8mb4 easy_mysql -e "SELECT COUNT(*) AS 拼接出来的结果 FROM users WHERE username = '' OR '1'='1';"
```

```text
+-----------------------+
| 拼接出来的结果        |
+-----------------------+
|                  5000 |
+-----------------------+
```

一个用户没输对，却把 5000 行全交了出去。换预编译（prepared statement，MySQL 里用 `PREPARE`）把同一件坏事再做一遍：

```powershell
docker exec easy-mysql mysql -uroot -peasy123 -t easy_mysql -e "PREPARE login FROM 'SELECT COUNT(*) FROM users WHERE username = ?'; SET @input = ''' OR ''1'' = ''1'''; EXECUTE login USING @input; SET @input = 'user_00001'; EXECUTE login USING @input; DEALLOCATE PREPARE login;"
```

```text
+----------+
| COUNT(*) |
+----------+
|        0 |
+----------+
+----------+
| COUNT(*) |
+----------+
|        1 |
+----------+
```

同样的字符串，走 `?` 之后服务器只把它当成**一个值**去比对：注入载荷查不到人（0 行），正常用户名查到 1 行。**数据和指令被彻底分开，这就是预编译是唯一正解的原因**（Java 的 `PreparedStatement`、Python 的 `cursor.execute(sql, args)`、Node 的 `?` 占位符，干的都是这件事）。

但 `ORDER BY` 后面没法放 `?`，这类地方用白名单：名单里的值直接放行，名单外的一律不要：

```powershell
docker exec easy-mysql mysql -uroot -peasy123 -t --default-character-set=utf8mb4 easy_mysql -e "SET @sort = 'age'; SELECT IF(@sort IN ('id','age','balance'), CONCAT('允许：按 ', @sort, ' 排序'), '拒绝：不在白名单里') AS 检查; SET @sort = 'id; DROP TABLE users'; SELECT IF(@sort IN ('id','age','balance'), CONCAT('允许：按 ', @sort, ' 排序'), '拒绝：不在白名单里') AS 检查;"
```

```text
+-------------------------+
| 检查                    |
+-------------------------+
| 允许：按 age 排序       |
+-------------------------+
+-----------------------------+
| 检查                        |
+-----------------------------+
| 拒绝：不在白名单里          |
+-----------------------------+
```

三道防线合起来看：**参数化**堵住拼接，**白名单**管住拼不进参数的位置，第 3 节的**最小权限**兜底 —— 万一前两道都漏了，`ro_demo` 最多也只是删不动表。

## 7. 连接配置放哪

| 放法 | 结果 |
|---|---|
| 硬编码写在代码里 | ✗ 代码开源、截图、日志泄露，密码跟着走 |
| 提交 `.yml` / `.env` 进 Git | ✗ 历史提交里永远留着一份，删文件也抹不掉 |
| 本地 `.env` + `.gitignore` | ✓ 个人项目够用：文件不进版本库，样例给 `.env.example` |
| 环境变量 / 启动参数 | ✓ 容器部署的默认解：`docker run -e DB_PASS=...`，密码不落盘 |
| 配置中心 / 密钥管理服务 | ✓ 多人多服务时用：能轮转、能审计谁读过 |

本仓库是教学环境，密码写在 `lab/docker-compose.yml` 里是**故意的**；你的项目只要连上真实数据，就照上面带 ✓ 的两行走。

## 三个必须记住的结论

1. **权限按「代码里真的会出现的 SQL」给**：报表只读、应用到表、运维才碰库，能用表级绝不给库级
2. **`SHOW GRANTS` 只是菜单，`ERROR 1142` 才是验证**：建完账号换客户端连一次，故意做一件坏事
3. **注入的正解是预编译，白名单管 `ORDER BY`，最小权限兜底**；连接配置永远不进 Git

## 常见错误

### ❌ 错误做法 1：`GRANT` 漏写 `.*`

在 `easy_mysql` 库下执行（先 `USE easy_mysql;`）—— 前两条是正确授权，第三条故意写错：

```sql
CREATE USER IF NOT EXISTS 'ro_demo'@'%' IDENTIFIED BY 'Ro#Demo2026';
GRANT SELECT ON easy_mysql.* TO 'ro_demo'@'%';
GRANT SELECT ON easy_mysql TO 'ro_demo'@'%';   -- ❌ 少了 .*
```

```text
ERROR 1146 (42S02) at line 1: Table 'easy_mysql.easy_mysql' doesn't exist
```

**为什么错**：没有 `.*` 时，MySQL 把 `easy_mysql` 当成了**当前库里的表名**，去找一张叫 `easy_mysql` 的表，自然找不到。

**正确做法**：库级权限永远写全 `easy_mysql.*`；只授一张表就写 `easy_mysql.orders`。

### ❌ 错误做法 2：`REVOKE` 收错了对象

```sql
CREATE USER IF NOT EXISTS 'app_demo'@'%' IDENTIFIED BY 'App#Demo2026';
GRANT SELECT, INSERT, UPDATE, DELETE ON easy_mysql.orders TO 'app_demo'@'%';
REVOKE UPDATE ON easy_mysql.users FROM 'app_demo'@'%';   -- ❌ 当初授的是 orders
```

```text
ERROR 1147 (42000) at line 1: There is no such grant defined for user 'app_demo' on host '%' on table 'users'
```

**为什么错**：`app_demo` 手里的 `UPDATE` 长在 `orders` 上，`users` 上根本没有这条授权可以收回。

**正确做法**：收权前先 `SHOW GRANTS FOR 'app_demo'@'%';` 抄清楚对象，再照着收。

### ❌ 错误做法 3：把 root 写进应用配置

root 的授权清单长到一行放不下（下面只截前 96 个字符）：

```powershell
docker exec easy-mysql mysql -uroot -peasy123 -B -e "SHOW GRANTS FOR 'root'@'%';" | ForEach-Object { $s = $_.ToString(); $s.Substring(0, [Math]::Min(96, $s.Length)) }
```

```text
Grants for root@%
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, RELOAD, SHUTDOWN, PROCESS, FILE, REFERENCES,
GRANT APPLICATION_PASSWORD_ADMIN,AUDIT_ABORT_EXEMPT,AUDIT_ADMIN,AUTHENTICATION_POLICY_ADMIN,BACK
```

**为什么错**：`DROP`、`FILE`、`SUPER`、`CREATE USER` 全在里面，而应用代码要的只是读写 `orders`。第一条命令的每个权限，在某次事故里都是一扇开着的门。

**正确做法**：用第 2 节的 `app_demo`，把 root 留给你自己敲命令时用。收尾删掉这两节重建的演示账号：

```powershell
docker exec easy-mysql mysql -uroot -peasy123 -e "DROP USER IF EXISTS 'ro_demo'@'%'; DROP USER IF EXISTS 'app_demo'@'%';"
```

## 动手练

- [ ] 建一个只读账号 `ro_demo`，用它查一次数据，再试一次 `DELETE` 看报错
- [ ] 检查你现有项目的配置文件，找出所有硬编码的密码

<details>
<summary>第一题的命令</summary>

```powershell
docker exec easy-mysql mysql -uroot -peasy123 -e "CREATE USER IF NOT EXISTS 'ro_demo'@'%' IDENTIFIED BY 'Ro#Demo2026'; GRANT SELECT ON easy_mysql.* TO 'ro_demo'@'%';"
docker exec easy-mysql mysql -uro_demo -p"Ro#Demo2026" -t easy_mysql -e "SELECT COUNT(*) FROM users;"
docker exec easy-mysql mysql -uro_demo -p"Ro#Demo2026" -t easy_mysql -e "DELETE FROM users WHERE id = 1;"
docker exec easy-mysql mysql -uroot -peasy123 -e "DROP USER IF EXISTS 'ro_demo'@'%';"
```

第二句返回 `5000`，第三句打出 `ERROR 1142`，第四句把账号删干净。

</details>

## 配套实验

```powershell
docker cp lab/queries/22-demo-privileges.sql easy-mysql:/tmp/
docker exec easy-mysql mysql -uroot -peasy123 -t -e "source /tmp/22-demo-privileges.sql"
```

> 实验创建的 `ro_demo` / `app_demo` / `ops_demo` / `lan_ro` 会在文件末尾全部删掉，`mysql.user` 回到原来 5 行，不会影响后面的文章。

## 下一篇

[23 · 常见报错速查表：报错不用慌，翻表查](23-error-lookup.md)
