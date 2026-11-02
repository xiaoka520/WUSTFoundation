# 登录与会话接入

更新：2026-11-02。本文对应 `WUSTLoginClient`；上级目录 `Docs/login-design.md` 是早期研究草案，接口及协议以当前实现和本文为准。

## 最短接入

```swift
let client = try WUSTLoginClient(
    username: account,
    deviceID: savedDeviceID,
    credentialStore: appCredentialStore
)
let result = try await client.ensureSession()
```

一个 client 对应一个账号。client 自己维护临时 URLSession 和独立的 Cookie 容器；库不要求 App 手动串联 aTrust、CSRF、环境上报和教务换票。不要在每次业务调用时重新创建 client。

`deviceID` 由 App 生成并稳定保存；不需要采集硬件信息。Demo 使用随机标识。

结果：

| WUSTLoginResult | App 的动作 |
|---|---|
| `.authenticated(cookie:)` | 教务会话已检查，可读取业务数据；不要记录 Cookie |
| `.loginRequired` | 没有可用 TGT，展示登录界面 |
| `.verificationRequired(_, methods:)` | 展示服务器支持的验证方式；当前高层接口支持短信 |
| `.additionalAuthenticationRequired(nextService:)` | aTrust 仍有后续步骤；不要显示登录成功 |

`ensureSession()` 优先检查当前教务 Cookie；只有 `.cookieMissing`、`.invalidSession` 才进入 TGT 恢复。它不会自动输入密码或发送短信。TGT 明确过期后，删除本账号保存的 TGT，返回 `.loginRequired`。断网、TLS、服务端错误和无法识别的检查页正文仍作为错误抛出，不删除 TGT，不触发密码重试。

同一账号有效的业务 Cookie 可以继续使用，即使 TGT 已过期；直到业务会话需要恢复才会发现 TGT 失效。库没有宣称或写死学校的 TGT/Cookie 寿命，也没有后台保活定时器。

## 首次登录和短信继续

```swift
let result = try await client.login(password: password)
// 若收到 verificationRequired，且 methods 包含 .sms：
try await client.sendSMSCode() // 用户明确点击发送后才调用
let resumed = try await client.submitSMSCode(code, password: password)
```

每一步都要处理返回状态。短信校验通过后，包会获取新图形验证码并继续统一认证，这是已实跑通过的服务端流程。若服务端再次要求验证，返回新挑战，不自动循环发送短信。已成功提交的旧挑战会被消费；若后续 OCR/网络失败，可重新调用 `login(password:)`，不要重交旧短信挑战。

密码由 App 在交互期间持有，client 不将密码存入属性或持久化存储。显式 `login(password:)` 会开始一次全新登录，清理该账号此前保存的凭据与当前会话。

默认使用现有 Vision 识别器。只对 `CaptchaRecognitionError` 更换图形验证码，默认最多 3 次；不自动重试密码、短信、HTTP 或网络错误。可注入 `captchaSolver` 替换识别器，或用低层 API 自己构建验证码界面。微信界面及学校今后新增的 aTrust 验证方式不在当前实现中。

## 业务调用

```swift
let info = try await client.fetchStudentInfo()
```

该方法内部调用 `ensureSession()`，使用同一个 URLSession 访问学生信息，并核对学号等于 client 账号；不一致时清理本地登录并抛错，不返回他人的数据。需要 UI 介入时先处理 `ensureSession()` 的详细结果，直接读取而未登录会抛 `.notAuthenticated`。

## 存储由 App 实现

实现 `UnionCredentialStore` 的三个异步方法：

- `loadCredential(for:)`：读取指定账号的 TGT，缺失返回 nil。
- `saveCredential(_:for:)`：保存该账号成功取得的 TGT。
- `clearCredential(for:)`：幂等删除本账号的 TGT。

协议要求 Sendable，推荐用 actor 实现，按账号隔离。存储失败应抛错，不能默默忽略。库在统一认证签发 TGT 后保存，因此后续网络失败时仍可恢复。

App 决定 Keychain 访问组、访问性、迁移和备份策略。不要将 TGT 放进日志或 UserDefaults。`Sources/WUSTDemo/DemoCredentialStore.swift` 给出 Keychain 示例；Demo 在用户实际运行时才读写自己的 Keychain 项目，使用 ThisDeviceOnly 策略，不保存密码和短信验证码。

没有 store 时，client 仅使用内存。也可以在初始化时传入 App 自行重建的 `UnionCredential(tgt:)`。该初始化方法只封装字符串，不验证服务器有效性。

## 并发、退出和切换账号

- 并发 `ensureSession()` 共享同一个恢复任务，避免重复换票。
- 登录、短信提交、发送短信与恢复互斥；冲突抛 `.operationInProgress`，App 应禁用重复按钮。
- 单个等待者取消不会取消所有调用者共享的恢复任务。`logout()` 会取消并销毁当前会话中的请求。
- `try await client.logout()` 清理内存、挑战、本账号存储和 Cookie 容器，并等待在途凭据写入结束后再删除，防止凭据被旧任务写回。
- `logout()` 是本地退出，不表示服务端 TGT 被撤销，也不退出浏览器、其他 client 或其他设备。当前没有未经验证的“全设备退出”实现。
- 退出发生存储错误时会抛错；内存和当前会话仍已清理，但 App 必须处理存储删除失败。
- 切换账号：等待旧 client 的 logout 完成，停止持有旧 client，再用新账号创建新实例。使用者不要绕过 client 修改其账号。
- 同账号多个 client 的存储需要 App 协调；推荐一个账号一个共享 client，避免多个实例同时覆盖或清除同一条存储。

## 保留的手动接口

App 仍可自行管理 URLSession，调用：

- `UnionAuthService.fetchServiceTicket(credential:service:using:)`
- `ATrustAuthService.login(credential:deviceID:using:)`
- `ATrustAuthService.completeLogin(ticket:service:deviceID:using:)`
- `UndergraduateAuthService.currentSessionCookie(using:)`
- `UndergraduateAuthService.login(credential:using:)`

一个低层流程必须贯穿使用同一个 URLSession。高层 client 的会话独立，不能把另一浏览器或另一个 session 的成功状态直接当成当前状态。

旧的直接账号密码换票入口保留为兼容接口，标记 deprecated；新的接入使用 WUSTLoginClient 或能返回 UnionLoginResult 的统一认证接口。

## 验证边界与运行

此前用户实跑已证明：短信验证 → TGT → aTrust ST/回调/环境上报/authCheck → 教务 ST/Cookie → 学生信息读取，以及全新 URLSession 使用 TGT 恢复。新增 coordinator、存储协议和并发处理经过本地合成协议测试。Keychain 适配器已编译，但真实 Keychain 访问及跨启动恢复仍需用户运行新版 Demo 验证；本轮没有用真实账号登录。

```sh
swift run WUSTDemo
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Demo 首次登录后会保存 TGT。退出程序再运行，输入相同账号并选择默认恢复，即可验证跨启动。只有选“清除本地登录”才删除 Demo 保存的凭据。输出直接写入标准输出；在 Xcode 用 View → Debug Area → Activate Console 打开真正的控制台，而非仅显示变量面板。

本轮 macOS 构建、21 项本地测试和 iOS Simulator（arm64、x86_64）库构建通过；这不等于 iPhone 真机认证已经验证。

所有自动认证测试使用合成账号、TGT、ST、环境票据及验证码，通过 URLProtocol 拦截；不连接学校、不发真实短信、不读取本地真实学籍 HTML、不读写真实 Keychain。保留关键异常分支的回归，不用重复真实登录来验证每个辅助方法。
