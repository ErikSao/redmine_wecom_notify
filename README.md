# Redmine WeCom Notify

Redmine 企业微信群机器人通知插件。新建问题、问题变更和超期工单会推送到企业微信群，支持按跟踪类型分别配置通知字段和触发字段。

## ✨ 功能

- **新建问题通知**：按跟踪类型推送配置好的字段，指派人不为空时自动 @。
- **问题变更通知**：状态、主题、指派人、自定义字段发生变化时推送，一次保存只发一条，消息中显示「旧值 → 新值」。
- **按跟踪类型配置**：不同跟踪类型可以配置不同的新建字段、变更显示字段和变更触发字段，增删字段不需要改代码。
- **超期工单提醒**：定时扫描未关闭且计划完成时间已过期或为空的问题，汇总推送并 @ 作者和指派人。
- **企业微信 @ 成员**：支持 Redmine 登录名/姓名到企业微信 userid 的映射，未映射时退化为 `@登录名` 纯文本。
- **消息分片**：自动按企业微信 markdown 的 4096 字节上限分片发送，避免超长失败。
- **代理支持**：自动读取 `http_proxy` / `https_proxy` 环境变量。

## 📦 安装

**环境要求**

- Redmine 6.0 及以上（在 Redmine 6.1.4 上验证）
- Ruby 3.1 及以上（在 Ruby 4.0.1 上验证）
- 企业微信群机器人 Webhook（不需要 corpid / secret / agentid）

**安装步骤**

1. 把插件放到 Redmine 的插件目录：

```bash
cd ${REDMINE_ROOT}/plugins
sudo -u redmine git clone https://gitee.com/eriksao/redmine_wecom_notify.git
sudo chown -R redmine:redmine redmine_wecom_notify
```

也可以下载 ZIP 解压到 `${REDMINE_ROOT}/plugins/`，目录名必须是 `redmine_wecom_notify`。

2. 重启 Redmine：

```bash
sudo /opt/nginx/sbin/nginx -t
sudo /opt/nginx/sbin/nginx -s stop
sleep 2
sudo /opt/nginx/sbin/nginx
```

插件没有数据表，不需要执行 `redmine:plugins:migrate`；没有静态资源，不需要重新预编译。

## ⚙️ 基本配置

安装后进入「管理 → 插件 → Redmine WeCom Notify → 配置」。

### 插件配置

| 配置项 | 说明 |
| --- | --- |
| 企业微信群机器人 Webhook | 群机器人地址，形如 `https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=xxx` |
| 用户映射 | Redmine 登录名/姓名到企业微信 userid 的对应关系 |
| 新建问题通知字段 | 通用兜底字段，一行一个 |
| 问题变更通知字段 | 通用兜底的变更显示字段 |
| 按跟踪类型的新建字段 | 按跟踪类型覆盖新建消息字段 |
| 按跟踪类型的变更显示字段 | 按跟踪类型覆盖变更消息字段 |
| 按跟踪类型的变更触发字段 | 哪些字段变化才发送变更消息 |

消息里的「查看详情」链接使用 Redmine 的「管理 → 配置 → 常规 → 协议 + 主机名称」。主机名称需要带端口，例如 `192.168.224.49:3001`，否则生成的链接无法从其他电脑打开。

### 字段标识

系统字段写属性名，自定义字段直接写名称。项目、编号会固定出现在消息里，不需要配置。

| 字段 | 标识 |
| --- | --- |
| 作者 | `author_id` |
| 跟踪 | `tracker_id` |
| 主题 | `subject` |
| 状态 | `status_id` |
| 优先级 | `priority_id` |
| 指派人 | `assigned_to_id` |
| 开始日期 | `start_date` |
| 计划完成时间 | `due_date` |
| 类别 | `category_id` |
| 目标版本 | `fixed_version_id` |
| 描述 | `description` |
| 完成度 | `done_ratio` |
| 预期时间 | `estimated_hours` |

自定义字段示例：`是否推广`、`测试员`、`期望测试完成时间`、`变更协同审视单号`。

### 按跟踪类型配置

每行一条，格式为 `跟踪名称: 字段1, 字段2`，`*` 表示未匹配跟踪的默认行。

```text
技术改进: author_id, tracker_id, subject, status_id, priority_id, assigned_to_id, due_date
订单设计: author_id, subject, due_date, 变更协同审视单号
*: author_id, subject
```

变更触发字段示例：

```text
技术改进: status_id, assigned_to_id, 是否推广, 设计变更, 变更协同审视单号
订单设计: status_id, due_date
*: status_id
```

取值优先级：跟踪名称 → `*` → 通用字段 → 内置默认值。

说明：

- 触发字段留空时，沿用该跟踪类型的变更显示字段。
- 触发字段发生变化但不在显示列表里时，消息会自动追加该字段。
- 跟踪名称必须和「管理 → 跟踪」里的名称完全一致，改名后需要同步修改配置。
- 某个跟踪写为空（如 `订单设计:`）表示该跟踪不带额外字段；变更触发字段为空则表示该跟踪不发送变更通知。

### 用户映射

每行一条，中英文冒号均可：

```text
zhangsan: ZhangSan
"张三": ZhangSan2
```

匹配顺序：登录名 → 显示名 → 姓+名 → 名+姓，忽略空格。没有映射时，@ 位置显示为 `@登录名` 纯文本，消息仍会正常发送。

## ⏰ 超期提醒

手动执行：

```bash
cd ${REDMINE_ROOT}
sudo -u redmine bundle exec rake redmine:wecom_notify:overdue RAILS_ENV=production
```

每天 9 点执行（加到 redmine 用户的 crontab）：

```cron
0 9 * * * cd /opt/redmine && /opt/redmine/.rbenv/shims/bundle exec rake redmine:wecom_notify:overdue RAILS_ENV=production >> /opt/redmine/log/wecom_overdue.log 2>&1
```

判定条件：状态未关闭，且计划完成时间早于今天或为空。

## 📸 截图

> 截图位置：`doc/images/example.png`，放入图片后取消下方注释。

<!-- ![企业微信通知示例](doc/images/example.png) -->

## 💬 消息示例

新建问题：

```text
**新建问题**
> 项目：ERP 平台
> 编号：#1024
> 作者：张三
> 跟踪：技术改进
> 主题：登录页验证码优化
> 状态：新建
> 计划完成时间：2026-10-30
[查看详情](http://192.168.1.10:3001/issues/1024)
```

问题变更：

```text
**问题变更**
> 项目：ERP 平台
> 编号：#1024
> 状态：新建 → 进行中
> 指派人：未指派 → @李四
> 是否推广：否
```

超期工单：

```text
**<font color="warning">超期工单问题</font>**
> 共 2 个问题超过计划完成时间
> [ERP 平台] #1024 登录页验证码优化
> 作者：@张三 指派人：@李四　计划完成：2026-10-18　已超期 2 天
```

## ⚠️ 注意事项

- 批量修改不触发变更通知。
- 通过邮件创建的问题（MailHandler）不触发通知。
- 通知在请求内同步发送，企业微信不可达时最多拖慢保存数秒。
- 群机器人限流 20 条/分钟，超期问题较多时会自动分片发送。
- hook 在事务提交前触发，极端回滚情况下消息可能已经发出。
- 跟踪类型改名后，按跟踪类型的配置会匹配不上，需要同步修改。

## 🐞 常见问题

**收不到通知**

1. 在「管理 → 插件 → 配置」确认 Webhook 地址正确。
2. 用 `curl` 直接向 Webhook 发送一条测试消息。
3. 查看 `${REDMINE_ROOT}/log/production.log` 中的 `wecom_notify` 日志。

**@ 成员不生效**

企业微信的 `<@userid>` 需要成员 userid，不是群昵称。请在用户映射里配置 `登录名: userid`；没有映射时只会显示 `@登录名` 文本，不会产生提醒。

**查看详情链接打不开**

检查「管理 → 配置 → 常规」里的协议和主机名称，主机名称必须带端口，例如 `192.168.224.49:3001`。

**定时任务不触发**

确认 crontab 加到了正确的用户下，并检查：

```bash
sudo crontab -l
systemctl status cron --no-pager
tail -n 50 ${REDMINE_ROOT}/log/wecom_overdue.log
```

## 🤝 贡献

欢迎提交 Issue 和 Pull Request。修改前请先在测试环境验证通知内容，并保持与现有配置格式兼容。

## 📄 License

GPL-2.0，详见 [LICENSE](LICENSE)。

## 作者

**ErikSao**

- GitHub：<https://github.com/ErikSao/redmine_wecom_notify>
