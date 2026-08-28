# Sub2API macOS 菜单栏监控：API 与认证调研

> 调研日期：2026-08-28<br>
> 上游项目：[Wei-Shaw/sub2api](https://github.com/Wei-Shaw/sub2api)<br>
> 源码基准：[main@`e866ff6`](https://github.com/Wei-Shaw/sub2api/tree/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8)<br>
> 当前正式版本：[v0.1.183](https://github.com/Wei-Shaw/sub2api/releases/tag/v0.1.183)（2026-08-25）

## 1. 研究范围与结论

本文面向一个原生 macOS 菜单栏客户端，回答四个问题：客户端应接受什么凭证、应调用哪些 Sub2API 接口、应该显示哪些监控指标，以及后台刷新如何兼顾实时性、安全性和服务器负载。

调研以固定 commit `e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8` 为依据。该 commit 比 v0.1.183 超前 64 个提交；认证、dashboard snapshot、ops snapshot、Channel Monitor V2 和 `/v1/usage` 的相关契约已对比确认未在两者之间变化。Sub2API 没有为这组内部面板 API 发布独立、版本化的客户端 SDK，因此实现仍应采用能力探测，不能只依赖版本号。

核心结论：

1. **v1 默认认证应是普通 API Key。** 用户粘贴 `sk-...`，客户端用 `Authorization: Bearer <key>` 调用 `GET /v1/usage`。它只暴露该 key 自身的额度、余额、速率窗口和用量，权限明显小于后台账号或管理员密钥。
2. **“账号登录”实际是邮箱 + 密码，不是任意用户名。** 登录后使用短期 access JWT 和轮转 refresh token。若服务端开启验证码或 TOTP，客户端必须完成对应交互；尤其 CAPTCHA 开启时，不能只做两个文本框便宣称账号登录完整可用。
3. **“面板 Token”是 JWT access token，不是普通 API Key。** 用户直接粘贴 JWT 时可以访问与其用户/角色相符的 `/api/v1/...` 面板接口，但只有 access token 就无法调用 refresh；它过期后必须重新粘贴。两种 Bearer 凭证不能仅凭 header 名称混为一种模式。
4. **Admin API Key 只应作为未来的显式高级模式。** 它是全局 `admin-...` 密钥，经统一 admin middleware 获得广泛管理面权限，没有细粒度 scope 或客户端可见的自动过期机制。当前 v1 没有必要支持它；管理员可通过邮箱登录或管理员 JWT 使用只读监控。
5. **管理员摘要优先使用 snapshot-v2。** `/api/v1/admin/dashboard/snapshot-v2` 和 `/api/v1/admin/ops/dashboard/snapshot-v2` 都有 30 秒服务端缓存、`ETag` 和 `304` 支持，适合 30-60 秒轮询。
6. **Channel Monitor 必须兼容互斥的 V1/V2 模式。** V2 的刷新周期由服务器限定为 60 或 300 秒；客户端应服从响应中的 `config.refresh_interval_seconds`，并显示 coverage/aggregation lag，而不是把聚合延迟误报成服务故障。

## 2. 建议的产品认证模式

| 设置项 | 用户输入 | 请求认证 | 可见范围 | 建议定位 |
| --- | --- | --- | --- | --- |
| API Key | 普通 `sk-...` | `Authorization: Bearer <key>` | 单个 key 的额度、余额、速率限制、今日/累计/趋势/模型用量 | 默认、推荐 |
| 邮箱登录 | 邮箱、密码；可能还有验证码/6 位 TOTP | 登录换取 access + refresh；后续 Bearer access JWT | 当前用户资料、余额、用户级用量、用户可见 Channel Monitor；管理员角色还可看 admin/Ops | 完整账户模式 |
| 面板 Token | 单个 JWT access token | `Authorization: Bearer <access_token>` | 与签发用户和角色一致的面板范围 | 便捷模式；过期后重贴 |
| Admin API Key（上游能力） | `admin-...` | `x-api-key: <admin-key>` | 管理仪表盘、Ops、告警、账号池、并发、完整 Channel Monitor | 暂不纳入 v1；未来高级模式 |

设置界面建议使用三个模式：**邮箱登录 / 面板 Token / API Key（最低权限）**。邮箱登录或面板 Token 认证后，如果 `/auth/me` 返回 `user.role == "admin"`，客户端即可加载管理员只读监控，不需要单独的管理员账号表单。Admin API Key 可保留在研究范围，但不建议进入当前 v1 UI。

每个服务器 profile 最少保存：

- 显示名称。
- Server URL，例如 `https://sub2api.example.com`；规范化时去掉尾部 `/`，保留部署所需的 path prefix，拒绝 URL 中的 query、fragment 和内嵌账号密码。
- 认证模式。
- Keychain 凭证引用；配置模型中不保存明文 secret。
- 能力探测结果、服务器版本与 Channel Monitor 模式。
- 刷新间隔、通知阈值和最近一次成功时间。

连接测试不要只显示“成功/失败”，至少返回：服务器可达、版本、凭证有效、识别到的权限层级、支持的监控模块。

## 3. 通用 HTTP 契约

### 3.1 基础探测

| 请求 | 认证 | 作用 | 响应形态 |
| --- | --- | --- | --- |
| `GET /health` | 无 | 只验证 HTTP 服务可达 | 直接 JSON：`{"status":"ok"}` |
| `GET /api/v1/settings/public` | 无 | 获取 `version`、captcha/TOTP 开关、`channel_monitor_*` 能力和服务器时区 | 标准 envelope |

`/health` 的路由和响应见[源码](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/server/routes/common.go#L9-L14)。公开设置无需认证，路由见[源码](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/server/routes/auth.go#L241-L248)，关键能力字段见[`PublicSettings`](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/handler/dto/settings.go#L352-L430)。

### 3.2 两种响应包装

`/api/v1/...` 面板接口通常返回：

```json
{
  "code": 0,
  "message": "success",
  "data": {}
}
```

该 envelope 的定义见[响应 helper](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/pkg/response/response.go#L14-L38)。客户端应先判断 HTTP status，再判断 `code == 0`，业务数据从 `data` 解码。

`GET /v1/usage` 属于 gateway 路由，成功时返回**直接 JSON**，没有 `code/message/data` 外层。它的部分统计采用 best-effort 构造，查询失败时可省略 `usage`、`daily_usage` 或 `model_stats`，客户端不能把字段缺失等同于零。

### 3.3 凭证传输

- JWT：`Authorization: Bearer <access-token>`。JWT middleware 的格式和校验见[源码](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/server/middleware/jwt_auth.go#L39-L68)。
- 普通 API Key：首选 `Authorization: Bearer <sk-key>`；gateway 也接受 `x-api-key`，但官方 key usage 页面使用 Bearer。服务端明确拒绝 `?key=` 和 `?api_key=`，见[API key middleware](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/server/middleware/api_key_auth.go#L49-L95)及[官方前端调用](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/frontend/src/views/KeyUsageView.vue#L857-L870)。
- Admin API Key：`x-api-key: <admin-key>`；管理员 JWT 仍使用 Bearer。两条分支见[admin middleware](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/server/middleware/admin_auth.go#L24-L79)。

任何 token 都不得放入 URL、query、analytics、日志、崩溃报告或通知正文。

## 4. 普通 API Key 模式：v1 首选

### 4.1 请求

```http
GET /v1/usage?days=30&start_date=2026-07-30&end_date=2026-08-28&timezone=Asia%2FShanghai HTTP/1.1
Host: sub2api.example.com
Authorization: Bearer sk-REDACTED
Accept: application/json
```

- `days` 控制 `daily_usage`，默认 30，允许 1-90。
- `timezone` 用于每日边界，应传 macOS 当前 IANA 时区。
- `start_date` / `end_date` 控制 `model_stats` 范围，格式为 `YYYY-MM-DD`；默认近 30 天。
- 即使 key 已达到额度或已过期，服务端仍跳过该 endpoint 的计费门禁，以便查询自身状态；disabled key、用户停用、分组不可用或 IP ACL 不匹配仍会拒绝。相关分支见[认证 middleware](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/server/middleware/api_key_auth.go#L117-L172)。

路由注册见[gateway routes](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/server/routes/gateway.go#L184-L211)，完整 handler 入口见[`Usage`](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/handler/gateway_handler.go#L1522-L1572)。

### 4.2 两类响应

当 key 配置总额度或任一种速率窗口时，响应为 `quota_limited`：

```json
{
  "mode": "quota_limited",
  "status": "active",
  "isValid": true,
  "quota": {
    "limit": 50,
    "used": 12.34,
    "remaining": 37.66,
    "unit": "USD"
  },
  "rate_limits": [
    {
      "window": "5h",
      "limit": 10,
      "used": 3.2,
      "remaining": 6.8,
      "window_start": "2026-08-28T08:00:00Z",
      "reset_at": "2026-08-28T13:00:00Z"
    }
  ],
  "expires_at": "2026-09-30T00:00:00Z",
  "days_until_expiry": 32,
  "usage": {},
  "daily_usage": [],
  "model_stats": []
}
```

字段构造见[`usageQuotaLimited`](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/handler/gateway_handler.go#L1641-L1732)。

没有 key 级额度/速率限制时为 `unrestricted`：

- 钱包用户：`planName`, `remaining`, `balance`, `unit`。
- 订阅用户：`planName`, `remaining`, `subscription.daily_usage_usd`, `weekly_usage_usd`, `monthly_usage_usd`，对应日/周/月 limit、周窗口起点和过期时间。
- 两类都可能带 `usage`、`daily_usage`、`model_stats`。

响应分支见[`usageUnrestricted`](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/handler/gateway_handler.go#L1734-L1800)。`usage.today` 和 `usage.total` 包含 requests、input/output/cache tokens、total tokens、cost、actual cost；同层还有 `average_duration_ms`、`rpm`、`tpm`，见[构造逻辑](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/handler/gateway_handler.go#L1593-L1626)。

### 4.3 菜单栏展示建议

API Key 模式的首屏只需：

- 主数字：剩余额度；无法计算时显示余额或“无限制”，不要伪造百分比。
- 今日：实际消费、请求数、token 数。
- 限制：最接近耗尽的 quota/rate window 及 reset 倒计时。
- 小趋势：`daily_usage` 最近 7/30 天。
- 模型：`model_stats` 中消费最高的 3 个模型。
- 底部状态：key status、过期日、最近成功刷新时间。

默认后台每 60 秒刷新一次即可。`/v1/usage` 会聚合多组统计，不应按秒轮询。

## 5. 账户模式

### 5.1 登录与生命周期

```http
POST /api/v1/auth/login HTTP/1.1
Content-Type: application/json

{
  "email": "user@example.com",
  "password": "REDACTED",
  "turnstile_token": "optional",
  "tencent_captcha_ticket": "optional",
  "tencent_captcha_randstr": "optional"
}
```

请求 DTO 强制 `email` 和 `password`，见[`LoginRequest`](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/handler/auth_handler.go#L76-L99)。登录会先验证服务器启用的 captcha；随后可能返回：

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "requires_2fa": true,
    "temp_token": "REDACTED",
    "user_email_masked": "u***@example.com"
  }
}
```

此时继续 `POST /api/v1/auth/login/2fa`，body 为 `temp_token` 和 6 位 `totp_code`。否则登录直接返回 `access_token`、`refresh_token`、`expires_in`、`token_type: "Bearer"` 和 `user`。分支见[登录 handler](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/handler/auth_handler.go#L237-L300)，路由与入口限流见[auth routes](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/server/routes/auth.go#L28-L56)。

刷新：

```http
POST /api/v1/auth/refresh HTTP/1.1
Content-Type: application/json

{"refresh_token":"REDACTED"}
```

每次成功都会返回新的 access token **和新的 refresh token**；旧 refresh token 被立即删除。客户端必须用单飞锁避免并发刷新，并将二者原子替换，否则两个并发 401 很容易导致第二次拿旧 refresh token 失败。轮转语义见[`RefreshTokenPair`](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/service/auth_service.go#L1777-L1861)，handler 响应见[源码](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/handler/auth_handler.go#L670-L710)。

服务端可启用 IP/User-Agent session binding；任一变化可能撤销 JWT 或整个 refresh token family，见[JWT 校验](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/server/middleware/jwt_auth.go#L84-L104)和[refresh 校验](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/service/auth_service.go#L1830-L1849)。因此账户模式必须允许用户重新认证，不能把 refresh token 当永久 token。

### 5.2 用户监控接口

| Endpoint | 建议用途 | 主要数据 |
| --- | --- | --- |
| `GET /api/v1/auth/me` | 登录确认和账户卡片 | email/username/role、balance、frozen balance、concurrency、status |
| `GET /api/v1/usage/dashboard/stats` | 60 秒摘要轮询 | key 数、累计/今日 requests/tokens/cost/actual cost、平均耗时、近 5 分钟 RPM/TPM、平台拆分 |
| `GET /api/v1/usage/dashboard/snapshot-v2` | 打开 popover 后加载趋势 | 可选 trend/models/groups；**不包含 summary stats** |
| `GET /api/v1/channel-monitors` | V1 渠道状态 | 主模型状态/延迟、7 日可用率、timeline、额外模型、可选 quota |
| `GET /api/v1/channel-monitor-v2/snapshot` | V2 渠道健康摘要 | config、coverage、metrics、health、trend |

`/auth/me` 路由见[源码](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/server/routes/auth.go#L250-L260)，用户 DTO 见[源码](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/handler/dto/types.go#L12-L39)。用户统计模型见[`UserDashboardStats`](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/pkg/usagestats/usage_log_types.go#L221-L267)，路由和 heavy rate limit 见[user routes](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/server/routes/user.go#L98-L113)。snapshot-v2 的 include flags 与响应见[handler](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/handler/usage_handler.go#L506-L564)。

建议后台只轮询 `/dashboard/stats`；趋势和模型仅在 popover 展开或用户手动刷新时取，避免重复重查询。

### 5.3 面板 Token（直接粘贴 JWT）

面板 Token 模式接收的是登录流程签发的 **access JWT**。连接时用它请求 `GET /api/v1/auth/me`：成功即可同时验证 token、读取用户身份并判定普通用户/管理员权限。后续用户与管理员面板请求都使用：

```http
Authorization: Bearer eyJ...REDACTED
```

它与邮箱登录的区别只在凭证生命周期，不在 endpoint 权限：

| 属性 | 邮箱登录 | 面板 Token |
| --- | --- | --- |
| 初始输入 | email/password，可能 CAPTCHA/TOTP | 单个 access JWT |
| 保存内容 | access + refresh token | 只有 access token |
| 过期处理 | 用 refresh token 轮转一次后重试 | 无法 refresh，标记 `auth_invalid` 并要求重贴 |
| 权限 | 由 JWT 中用户角色及服务端最新用户状态决定 | 相同 |
| 适用场景 | 长期监控 | 临时接入、避免在客户端输入密码 |

JWT 自带 `exp`。客户端可在本地**仅解码、不信任**该时间用于提前提示；真正的有效性和角色始终以服务器 `/auth/me` 响应为准。Sub2API 默认 access token 有效期为 24 小时，但部署可改为分钟级或其它小时值，见[默认配置](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/config/config.go#L2258-L2263)和[签发逻辑](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/service/auth_service.go#L1408-L1459)。因此面板 Token 不是适合长期无人维护的永久 token。

不要把普通 `sk-...` API Key 自动回退成面板 JWT，也不要只根据字符串是否以 `eyJ` 开头决定权限。三个设置模式各自调用确定的验证 endpoint，错误应原样归入对应模式。

## 6. 管理员监控

### 6.1 Admin API Key 风险边界

Admin API Key 格式为 `admin-` 加 64 位十六进制随机数，生成后写入全局 settings；完整值只在生成/重新生成响应中返回一次，之后只能读取脱敏状态。来源见[生成逻辑](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/service/setting_features.go#L569-L608)和[handler](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/handler/admin/setting_handler_runtime.go#L13-L50)。

`/api/v1/admin` 整组先经过 admin auth；该 key 没有每-endpoint scope，验证成功后会绑定首个管理员身份，见[路由挂载](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/server/routes/admin.go#L13-L38)和[key 校验](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/server/middleware/admin_auth.go#L120-L153)。部分敏感写操作另有 step-up 限制，但这不改变该 key 对监控/管理读取权限过大的事实。

客户端侧约束：

- UI 明示“全局管理员凭证”，不要把它笼统命名为 Token。
- 该模式的网络层只开放预先列出的 GET endpoints；不要做通用任意路径请求器。
- 支持用户手动替换/删除 Keychain 中的 key；服务器端轮换需由用户在管理后台执行。
- 可优先推荐管理员账户 JWT，因为它具备可撤销会话与过期生命周期，但仍须处理 captcha、TOTP 和 session binding。

### 6.2 管理总览

推荐后台请求：

```http
GET /api/v1/admin/dashboard/snapshot-v2?include_stats=true&include_trend=false&include_model_stats=false&include_group_stats=false HTTP/1.1
Authorization: Bearer eyJ...ADMIN-JWT-REDACTED
If-None-Match: "previous-etag"
```

若未来支持 Admin API Key，上述认证行改为 `x-api-key: admin-REDACTED`；响应契约相同。

`data.stats` 包含：

- 用户总数、今日新增、活跃用户。
- API key 总数、active key 数。
- 上游账号总数、正常/错误/限流/过载账号数。
- 累计与今日 requests、input/output/cache/total tokens、标准成本、实际成本和账号成本。
- 平均耗时、近 5 分钟 RPM/TPM。
- `uptime`、`stats_updated_at`、`stats_stale`。

模型定义见[`DashboardStats`](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/pkg/usagestats/usage_log_types.go#L28-L80)。该 snapshot 默认也取趋势和模型，因此菜单栏摘要务必显式把 include flags 关掉。它有 30 秒缓存、`ETag`、`If-None-Match`/304，见[handler](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/handler/admin/dashboard_snapshot_v2_handler.go#L18-L147)。

不要使用 `GET /api/v1/admin/dashboard/realtime`：当前 handler 明确返回全零 mock，见[源码](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/handler/admin/dashboard_handler.go#L190-L199)。

### 6.3 Ops 健康

推荐请求：

```http
GET /api/v1/admin/ops/dashboard/snapshot-v2?time_range=1h HTTP/1.1
Authorization: Bearer eyJ...ADMIN-JWT-REDACTED
If-None-Match: "previous-etag"
```

返回 `data.generated_at` 及三块数据：

- `overview`：0-100 `health_score`、成功/失败/业务限流数、SLA、error rate、upstream error rate、429/529、QPS/TPS current/peak/avg、duration/TTFT percentiles，以及 CPU、内存、DB、Redis、后台 job heartbeat 等系统快照。
- `throughput_trend`：窗口内吞吐趋势。
- `error_trend`：窗口内错误趋势。

核心模型见[`OpsDashboardOverview`](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/service/ops_dashboard_models.go#L17-L70)。endpoint 要求 Ops monitoring 已启用；否则返回 feature error。它同样有 30 秒缓存和 ETag，见[handler](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/handler/admin/ops_snapshot_v2_handler.go#L16-L145)。

按需扩展的只读 endpoints：

| Endpoint | 用途 | 何时请求 |
| --- | --- | --- |
| `GET /api/v1/admin/ops/alert-events?status=firing&limit=20` | 当前 firing 告警 | 摘要刷新或告警面板展开 |
| `GET /api/v1/admin/ops/account-availability` | 按平台/分组/账号的可用、限流、过载、错误 | 账号异常数 > 0 时展开 |
| `GET /api/v1/admin/ops/concurrency` | 平台/分组/账号并发与排队 | 并发面板展开 |
| `GET /api/v1/admin/ops/realtime-traffic?window=1min` | 近实时 QPS/TPS | popover 打开时，每 5-10 秒 |

路由清单见[Ops routes](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/server/routes/admin.go#L191-L278)。

### 6.4 WebSocket 可选项

`GET /api/v1/admin/ops/ws/qps` 推送：

```json
{
  "type": "qps_update",
  "timestamp": "2026-08-28T12:00:00Z",
  "data": {"qps": 2.1, "tps": 1540.3, "request_count": 126}
}
```

- 管理员 JWT 的浏览器兼容方案是 subprotocol `['sub2api-admin', 'jwt.<token>']`；原生 macOS WebSocket handshake 可使用普通 `Authorization: Bearer ...`。未来若启用 Admin API Key，也可用 `x-api-key`。
- 服务端每 2 秒推送，底层统计最多每 5 秒刷新，统计窗口为 1 分钟，见[常量和 payload](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/handler/admin/ops_ws_handler.go#L46-L59)及[构造逻辑](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/handler/admin/ops_ws_handler.go#L253-L279)。
- 推荐只在 popover 展开并选择实时视图时连接；后台驻留继续使用 snapshot。这样可以避免永久连接、重连抖动和不必要的服务器压力。

## 7. Channel Monitor V1/V2

### 7.1 V1 主动探测视图

`GET /api/v1/channel-monitors` 为用户只读接口，主要字段为：channel name/provider/group、主模型 status、latency/ping latency、7 日 availability、timeline、额外模型状态，以及服务端允许时的最近 quota。字段见[user handler](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/handler/channel_monitor_user_handler.go#L54-L95)。

部署不是 V1 mode 或 feature 关闭时，list 可能成功返回空 items，而不是 404；该行为见[handler](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/handler/channel_monitor_user_handler.go#L159-L175)。所以客户端应结合 public settings 的 `channel_monitor_enabled/mode` 判断“未启用”，不要把空数组显示成“所有渠道都健康”。

### 7.2 V2 被动聚合视图

用户和管理员分别调用：

- `GET /api/v1/channel-monitor-v2/snapshot`
- `GET /api/v1/admin/channel-monitor-v2/snapshot`

支持 `range=90m|24h|7d|30d`，以及重复的 `platform`、`group_id`、`model` query，例如 `platform=openai&platform=anthropic`。完整前端参数序列化和类型见[官方 API client](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/frontend/src/api/channelMonitorV2.ts#L211-L263)。

snapshot 包含：

- `config`：enabled、refresh interval、平台配置、health thresholds。
- `coverage`：requested/coverage 时间、`data_through`、`computed_at`、`aggregation_lag_seconds`、`coverage_complete`，首次回填时还有 bootstrap 进度。
- `metrics`：成功/错误/总请求数、tokens、RPM/TPM、error/success/cache rate、TTFT 和 duration percentiles。
- `health`：overall/error/TTFT/cache 状态及可选 0-100 score。
- `trend`：各 bucket 的 metrics + health。

数据契约见[service models](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/service/channel_monitor_v2.go#L39-L212)。普通用户响应会清除绝对 volume，服务端设置还可隐藏 RPM/TPM；管理员保留完整值，见[脱敏逻辑](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/service/channel_monitor_v2.go#L589-L642)。

V2 只允许 60 或 300 秒刷新间隔，默认 300 秒，见[配置校验](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/service/channel_monitor_v2.go#L730-L736)。用户路由和管理员 mode guard 分别见[user routes](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/server/routes/user.go#L138-L156)与[admin routes](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/server/routes/admin.go#L822-L879)。

客户端展示规则：

- `coverage_complete == false`：显示“历史数据回填中”，并展示 bootstrap progress。
- `aggregation_lag_seconds` 超过约 2 个服务端 refresh interval：标记“数据延迟”，不立即标记 server down。
- `health.overall == unknown`：显示样本不足，而不是健康或故障。
- 用户模式绝对计数为 0 时，先检查是否是服务端脱敏，不要把它解释为零流量。

## 8. 菜单栏信息架构

建议始终把“服务是否可达”和“业务是否健康”拆开。

菜单栏图标状态优先级：

1. 灰：尚未配置/暂停。
2. 红色带锁：认证失效。
3. 红：服务器不可达，或明确 critical health。
4. 黄：数据 stale、聚合延迟、部分账户异常、接近额度阈值。
5. 绿：最近刷新成功且业务健康。

popover 顶部保持稳定：服务器名称、整体状态、主指标、最近刷新时间、手动刷新按钮。下方内容按权限递进：

| 模式 | 主指标 | 次要内容 |
| --- | --- | --- |
| API Key | 剩余额度/最近 rate window | 今日消费、tokens、请求、7/30 日趋势、模型排行 |
| 账户 | balance + 今日实际消费 | RPM/TPM、用户渠道健康、平台拆分 |
| 管理员 | health score + QPS/TPS | error/SLA、异常账号、firing alerts、系统资源、Channel V2 |

通知建议只在**状态跨阈值**时发出，避免每次轮询重复通知：额度低于用户设置比例、key 临近过期、认证失效、server 连续多次不可达、health 首次进入 critical、出现新的 firing alert。恢复通知也只发一次。

## 9. 刷新状态机

```text
启动 / 唤醒 / 网络恢复
        |
        v
 GET /health ----失败----> unreachable + 1m/2m/5m backoff
        |
        v
 GET public settings ----> 更新 version / capabilities / monitor mode
        |
        v
 按认证模式获取 summary ----200/304----> 保存快照与 ETag，重置 backoff
        |
        +----401 邮箱登录 JWT----> 单飞 refresh 一次 -> 原子换 token -> 重试原请求一次
        |                    |
        |                    +----失败----> auth_invalid，等待用户重新登录
        |
        +----401 面板 Token----> auth_invalid，要求重新粘贴（没有 refresh token）
        |
        +----401 API Key----> auth_invalid，要求更新 key
        |
        +----429----> 严格采用 Retry-After
        |
        +----5xx/网络----> 保留旧快照并标 stale，1m -> 2m -> 5m 退避
```

推荐 cadence：

| 数据 | 后台 | popover 展开 |
| --- | --- | --- |
| API Key `/v1/usage` | 60 秒 | 手动刷新；不低于 30 秒 |
| 用户 `/dashboard/stats` | 60 秒 | 30-60 秒 |
| 管理员 dashboard snapshot | 60 秒 + ETag | 30 秒 + ETag |
| Ops snapshot | 60 秒 + ETag | 30 秒 + ETag |
| Channel V2 | 服从 60/300 秒 | 服从 server config |
| realtime traffic | 不请求 | 5-10 秒，或按需 WebSocket |

应用睡眠、系统网络断开时暂停 timer；唤醒或网络恢复后立即刷新一次。刷新任务应合并同 profile 的重复触发，设置合理 timeout，并允许用户切换 profile 时取消旧请求。

面板 API 的默认限流为全局每用户 240 RPM、heavy endpoint 60 RPM，管理员默认豁免但服务端可改；见[默认设置](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/service/setting_panel_rate_limit.go#L13-L53)。429 会给 `Retry-After`，见[middleware](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/server/middleware/panel_rate_limit.go#L153-L162)。

## 10. 错误与陈旧状态

不要把所有失败统一显示成“服务器故障”。建议内部状态至少区分：

| 状态 | 判断 | UI |
| --- | --- | --- |
| `unreachable` | DNS/TLS/connect/timeout 或 `/health` 失败 | 服务器不可达；显示最后成功时间 |
| `auth_invalid` | 401，且邮箱登录 refresh 失败，或面板 Token/API Key 被拒绝 | 凭证失效；按模式引导重新登录、重贴 Token 或更新 key |
| `forbidden` | 403、IP ACL、角色不满足 | 无权限或访问策略阻止 |
| `unsupported` | endpoint 404 且 capability probe 不支持 | 当前版本不支持，执行 fallback |
| `feature_disabled` | public settings 关闭或明确 mode/feature error | 功能未启用，不算故障 |
| `stale` | 有旧快照但连续刷新失败，或 response 自报 stale/lag | 显示旧值并标注时间，不清零 |
| `degraded` | health warning、部分账号错误、接近额度 | 黄色状态 |
| `critical` | health critical、额度耗尽或业务不可用 | 红色状态 |

对 `304 Not Modified`，应复用缓存 payload，并把本次 HTTP 成功记为“观察成功”；数据的 `generated_at/computed_at` 不应被伪改成当前时间。

## 11. 版本兼容与能力探测

### 11.1 v0.1.172 安全事件与支持下限

需要准确区分“漏洞披露版本”和“受影响版本”：

- **v0.1.172 已包含修复，本身不是该账号接管漏洞的未修复版本。** 该 release 披露：更早版本的 OAuth 登录补全流程允许攻击者仅凭受害者邮箱，把自己的第三方身份绑定到受害者账号并随后登录。修复 commit 是 [`02e50cc2`](https://github.com/Wei-Shaw/sub2api/commit/02e50cc22d038dabf3c6af92dbb92d1e0321f8d5)，首次包含在 [v0.1.172](https://github.com/Wei-Shaw/sub2api/releases/tag/v0.1.172)。
- 修复要求非终态 pending OAuth session 不得执行 identity adoption/binding；当前固定源码保留了威胁说明和 guard，见[源码](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/handler/auth_oauth_pending_flow.go#L2001-L2015)。
- 即使本 macOS 客户端只使用邮箱密码、面板 JWT 或 API Key，不主动走 OAuth，连接到 `< v0.1.172` 的实例仍意味着该实例上的账户可能从其它入口被接管。因此不应静默支持这类服务器。

**产品建议最低支持版本为 v0.1.183。** v0.1.172 只是上述安全修复线，不应被当成客户端支持基线；之后的 releases 才加入 Channel Monitor V2，并持续修复前端 token refresh、XSS 依赖、Channel V2 计数归属、计费和调度问题。v0.1.183 是调研时最新正式版，且本文关键契约已在该 tag 与固定 main commit 之间核验。

连接策略建议：

- `< v0.1.172`：显示阻断级安全警告“服务器版本存在已知账号接管风险”，不建立长期账户/JWT profile。
- `v0.1.172 ... v0.1.182`：显示“不受支持，请升级到 v0.1.183+”；若产品保留兼容入口，也只能 best-effort，不能承诺监控完整性。
- `>= v0.1.183`：进入正常 capability probing。版本仍不是能力判断的替代品。

### 11.2 能力时间线

基于 git tag 历史：

| 最低 release | 已包含的相关能力 |
| --- | --- |
| [v0.1.136](https://github.com/Wei-Shaw/sub2api/releases/tag/v0.1.136) | Admin API Key、refresh token、dashboard snapshot-v2、`/v1/usage` |
| [v0.1.173](https://github.com/Wei-Shaw/sub2api/releases/tag/v0.1.173) | Channel Monitor V2 |
| [v0.1.183](https://github.com/Wei-Shaw/sub2api/releases/tag/v0.1.183) | 调研时最新正式版、建议最低支持版本 |

### 11.3 Probe 顺序

在版本达到支持下限后，版本只用于诊断显示，不应用作唯一功能开关。建议连接后的 probe 顺序：

1. `GET /health`。
2. `GET /api/v1/settings/public`，记录 `version`、`server_timezone`、captcha/TOTP 和 Channel Monitor flags。
3. 验证用户选择的凭证：API Key 直接试 `/v1/usage`；邮箱登录完成后试 `/auth/me`；面板 Token 直接试 `/auth/me`。后二者若角色为 admin，再试最小 admin snapshot。
4. 管理员先试 `/admin/dashboard/snapshot-v2`；404 回退 `/admin/dashboard/stats`。
5. 普通账户摘要使用 `/usage/dashboard/stats`；趋势先试 `/usage/dashboard/snapshot-v2`，404 时回退 `/dashboard/trend` + `/dashboard/models`。
6. `channel_monitor_mode == v2` 时试 V2 snapshot；404 或明确 mode mismatch 时再试 V1。mode 为 V1 或关闭时不要无意义探测 V2。
7. Ops snapshot 失败时保留普通 admin dashboard；明确 disabled 时隐藏 Ops 区块，不连 WebSocket。

解析应遵循 tolerant-reader 原则：忽略未知字段，对 optional/null/缺失做区分，不因上游增加字段而整包失败。

## 12. 安全清单

- 密码、access JWT、rotated refresh token、普通 API key 和 Admin API Key 全部存 macOS Keychain；禁止 UserDefaults、plist、SQLite 明文和 state restoration。
- 账户首次登录成功后可丢弃密码，只保留 access/refresh token；需要重新认证时再向用户索取密码。若产品要提供“记住密码”，必须作为独立 opt-in Keychain 项。
- Keychain item 按规范化 server origin + profile ID 隔离，删除 profile 时同步删除 secret。
- 生产服务器只允许 HTTPS；不要提供“忽略证书错误”。本地开发 HTTP 若要支持，应限 loopback 并显式标注不安全。
- URLSession/网络日志统一 redact `Authorization`、`x-api-key`、login/refresh body、WebSocket protocol token。
- 管理员模式只发白名单 GET；不在客户端提供生成、轮换、删除 admin key 的写操作。
- 401 时只有“邮箱登录”且持有 refresh token 的 profile 才 refresh，最多一次；面板 Token、API key 和未来的 admin key 都不自动尝试账号登录。
- 429 尊重 `Retry-After`，5xx 与网络错误指数退避并加少量 jitter，防止多个客户端同步重试。
- 不在通知内容展示余额以外的敏感账号、错误详情或 key 片段；锁屏通知尤其如此。
- 不允许 token 出现在 query string。WebSocket 优先 header；使用 JWT subprotocol 时也不得打印握手 header。
- 上游采用 [LGPL-3.0-or-later](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/LICENSE)。独立 REST 客户端可以自行选择许可证，但若复制或链接上游代码，应单独核对 LGPL 义务；本文不构成法律意见。

## 13. v1 实施范围建议

首个可用版本建议控制在：

1. 多 server profile 基础模型，但 UI 先支持一个 active profile。
2. 邮箱登录、面板 Token、低权限 API Key 三种认证；邮箱登录必须同时完成 CAPTCHA/TOTP/refresh，面板 Token 过期后明确要求重贴。
3. `/health` + public settings capability probe。
4. `/v1/usage` 的 quota/unrestricted 两种解析。
5. admin dashboard + ops snapshot，带 ETag。
6. Channel Monitor V1/V2 自动适配。
7. Keychain、状态分层、退避、阈值通知。

Admin API Key、WebSocket、告警详情、账号级 drill-down、复杂趋势筛选可以放在后续版本。这样 v1 已能覆盖“余额/额度监控”和“Sub2API 实例运维监控”两个核心场景，同时避免一开始承担全量管理控制台的权限与复杂度。

## 14. 主要源码索引

- 认证请求/响应与 2FA：[auth_handler.go](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/handler/auth_handler.go#L76-L99)、[登录分支](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/handler/auth_handler.go#L237-L300)、[refresh](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/handler/auth_handler.go#L670-L710)。
- 普通 API key 认证：[api_key_auth.go](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/server/middleware/api_key_auth.go#L49-L172)。
- Admin 认证：[admin_auth.go](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/server/middleware/admin_auth.go#L24-L79)。
- Key usage：[gateway_handler.go](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/handler/gateway_handler.go#L1522-L1800)。
- 用户 dashboard：[usage_handler.go](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/handler/usage_handler.go#L438-L564)。
- 管理 dashboard snapshot：[dashboard_snapshot_v2_handler.go](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/handler/admin/dashboard_snapshot_v2_handler.go#L18-L147)。
- Ops snapshot：[ops_snapshot_v2_handler.go](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/handler/admin/ops_snapshot_v2_handler.go#L16-L145)。
- Channel Monitor V2：[channel_monitor_v2.go](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/backend/internal/service/channel_monitor_v2.go#L39-L212)。
- 前端 API 类型：[admin dashboard](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/frontend/src/api/admin/dashboard.ts#L129-L152)、[Ops](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/frontend/src/api/admin/ops.ts#L28-L68)、[Channel V2](https://github.com/Wei-Shaw/sub2api/blob/e866ff6ec431816e8b9d4b81dc7b00122ca3f7f8/frontend/src/api/channelMonitorV2.ts#L1-L271)。
