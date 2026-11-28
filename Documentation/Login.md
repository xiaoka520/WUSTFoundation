# 登录与会话接入

更新：2026-11-28。学校登录入口统一使用 `/authserver/login`。旧 `/lyuapServer` 登录、RSA 密码编码、TGT 存取与换票、旧短信二次验证及 aTrust 自动认证链路已移除。算术验证码的 `VisionCaptchaSolver` 保留为独立图片识别工具，不参与新版登录。

## 创建 client

```swift
let client = try WUSTLoginClient(username: studentID)
```

每个账号保留一个 client。`username` 用于核对学生信息中的学号。初始化只建立独立的临时 URLSession，不发送请求。App 可以通过 `sessionConfiguration:` 提供超时或 URLProtocol 配置；包使用隔离的内存 Cookie 容器，不继承其他 client 的登录。

已删除旧初始化参数 `deviceID`、`credential`、`credentialStore`、`maxCaptchaAttempts` 和 `captchaSolver`。`UnionCredentialStore`、`currentCredential()`、旧 `login(password:)`、`sendSMSCode()`、`submitSMSCode(_:password:)` 也已删除，调用方需要迁移到以下新版入口。

## 新版密码登录

```swift
let result = try await client.loginWithAuthServer(
    password: password,
    maxSliderAttempts: 3
)
```

该入口读取实际表单的动态令牌与密码加密参数，在同一临时会话完成滑块验证并提交密码。`maxSliderAttempts` 允许 1～5，统计实际服务端校验次数；定位不可靠的图片立即换图，不消耗校验次数，每轮另有十张的连续弃图上限。

滑块通过不代表登录完成。包还会检查教务会话、读取学生信息并匹配初始化时的学号，通过后才替换当前 client 会话。失败不会覆盖之前的有效教务会话。

密码由调用方提供，库不保存密码，不自动重试账号密码登录。App 自行决定密码输入与安全存储策略。

## 独立手动滑块组件

`ManualSliderCaptchaView` 是 SwiftUI 包装的 WKWebView 组件，显示学校网页原生滑块验证区域和取消、重新加载按钮。可用于 iOS 15+、macOS 15+、visionOS 1+ 的下游 App；由 App 自行选择 sheet、popover 或窗口，建议宽 340～400 点，最小宽 300 点。

通过同一个 `WUSTLoginClient` 创建 `ManualSliderCaptchaSession`。组件使用包内生成的独立 HTML 宿主，直接从学校的 `toSliderCaptcha.htl` 加载原始滑块片段及其样式、JavaScript，仅补充 jQuery 和官方加密脚本依赖。WKWebView 不加载完整登录页或 `login.js`，也没有账号输入框、密码输入框和登录表单。拖动、图片加载、失败刷新及校验请求均由官方组件处理；已移除自绘的 SwiftUI 拖动条和原生手势采样。密码不会传入 WKWebView，网页也不允许自动提交登录表单。

WKWebView 使用独立的临时网站数据存储，从本次登录会话同步 Cookie。私有桥接仅接受指定 HTTPS 验证组件主文档、当前页面标识的消息，并确认实际校验响应业务码为 `1` 后才接回状态。回传时同步验证后的 Cookie；原生 URLSession 预先获取的登录表单和 execution 始终保留在库内，组件不会再次请求登录页来替换它们。只有完成状态同步后才调用 `onVerified`。这仍需要联网访问学校验证码服务，不是离线验证组件。

以下示例由 App 持有账号 client 和密码输入，不把密码传入验证码界面：

```swift
import SwiftUI
import WUSTFoundation

@MainActor
struct ManualLoginButton: View {
    let client: WUSTLoginClient
    @Binding var password: String
    @State private var verification: ManualSliderCaptchaSession?
    @State private var working = false
    @State private var continuing = false
    @State private var message = ""

    var body: some View {
        VStack {
            Button("手动滑块登录") {
                guard !working else { return }
                working = true
                Task {
                    do { verification = try await client.prepareManualAuthServerLogin() }
                    catch { message = "无法开始验证"; working = false }
                }
            }.disabled(working || password.isEmpty)
            Text(message)
        }
        .sheet(item: $verification, onDismiss: {
            // 组件会在成功前离开界面时取消其会话；这里恢复 App 的按钮状态。
            if !continuing {
                working = false
            }
        }) { session in
            ManualSliderCaptchaView(session: session, onVerified: {
                continuing = true
                verification = nil
                Task {
                    defer { continuing = false; working = false }
                    do {
                        let result = try await client.loginWithManualAuthServer(
                            password: password, verification: session
                        )
                        if case .authenticated = result { message = "登录完成" }
                    } catch let error as AuthServerCredentialError {
                        message = error.localizedDescription
                    } catch { message = "登录未完成，请重试或使用官方网页登录" }
                }
            }, onCancel: { verification = nil })
        }
    }
}
```

`onVerified` 只表示滑块校验成功，尚未提交密码。必须使用同一个 client、同一个 session 调用 `loginWithManualAuthServer`；不要在回调里调用自动登录入口。续接接口消费会话一次，使用原表单和原 Cookie 容器提交密码，然后沿用现有的教务 Cookie 与学生信息页面检查，成功才替换 client 会话。密码提交失败后需重新开始，不重复提交旧挑战或旧登录表单。

取消按钮或组件在成功前离开界面会立即关闭临时会话。下游也可主动调用 `session.cancel()` 或 `await client.cancelManualAuthServerLogin()`。退出 client、替换手动会话、开始自动密码或短信登录会作废旧手动会话；其他 client 创建的 session 不能用来续接。对共享的同一个 client，不要同时启动不同登录方式。

官方滑块内的刷新、失败处理由学校脚本负责；外层“重新加载”重新建立网页验证上下文，旧页面不能再接回结果。库采用本地 120 秒的页面交互上限，以及验证成功后的 120 秒续接上限，这些是客户端限制，不是学校公布的有效期；服务端可能更早拒绝。验证阶段失败、过期或取消不会提交密码。加载失败会提示重新加载或使用官方完整登录页。

该入口当前只接入密码登录，短信仍使用现有短信/官方网页入口。手势及可访问性支持由学校网页组件决定，下游应保留官方完整登录页。组件不把密码、图片、Cookie 或手动轨迹写入日志文件，不向外暴露校验协议的密钥，也不改写学校脚本生成的轨迹。

macOS Demo 支持登录菜单 `6` 或 `swift run WUSTDemo --manual-slider-login`。它读取密码后只弹出官方滑块区域，验证成功再续接登录；`--prompt-password` 可强制重新输入。`swift run WUSTDemo --manual-slider-preview` 只打开匿名官方滑块预览，不读取本地账号密码文件，也不提交密码。

macOS Demo 的入口运行 AppKit 事件循环，异步登录任务在循环内执行，使窗口和 WKWebView 能正常接收鼠标、触摸与关闭事件；下游 SwiftUI/AppKit App 使用自身已有的事件循环即可。

测试覆盖合成协议响应、网页脚本桥接与会话轮换；另已通过匿名 GET 核对当前官网组件入口，但尚未据此宣称真人拖动通过或真实账号登录验收通过。

### 单独处理账号或密码错误

服务器明确返回账号或密码拒绝文本时，密码登录接口抛出独立的 `AuthServerCredentialError.invalidCredentials`，不再使用通用的 `AuthServerLoginError.loginNotCompleted`。App 可单独捕获它并提示“账号或密码错误，请检查后重试”。学校若没有区分账号与密码，库也不推断一定是密码错。

只有可信登录响应中指定错误区域的明确凭据拒绝文本才会触发该类型。验证码错误、账号锁定、密码过期、额外认证、未知页面和网络错误不会被归类为密码错误；未知的登录失败仍保留 `loginNotCompleted`。库不自动重新提交密码，Demo 也单独打印凭据错误提示。错误消息不附带账号、密码或原始响应内容。

## 新版手机号短信登录

```swift
let resendAfterSeconds = try await client.sendLoginSMSCode(to: phoneOrStudentID)
let result = try await client.loginWithSMSCode(smsCode)
```

手机号或学号均作为官网的接收账号提交；学号对应哪个绑定手机由学校服务器决定。先读取短信表单并完成滑块，按官网规则加密接收账号，再向 `/authserver/dynamicCode/getDynamicCode.htl` 申请一次短信。只有业务码 `success` 才确认发送，返回的可选整数为服务器给出的重发等待秒数。App 展示等待时间并由用户发起下一次发送。

提交短信码使用同一会话、`cllt=dynamicLogin` 和实际表单参数。服务器返回登录表单时，client 保留更新后的执行令牌，App 可让用户更正短信码后再次提交。重新申请短信、开始密码登录或退出时，待提交的短信会话会清理。短信码不写入日志或持久存储。

只有教务会话和学生信息学号均验证成功，方法才返回 `.authenticated`。手机号属于其他账号时不会将其会话接入本 client。

短信登录协议已核对官网；自动化测试使用合成响应。真实短信收取及完整短信登录仍待账号运行确认，自动滑块的通过率不能由单测推断。

## 官方网页登录

App 可以保留官方 WebKit 登录入口，让用户在学校页面完成账号、短信或其他验证：

```swift
let webView = UndergraduateWebLogin.makeWebView()
webView.load(URLRequest(url: UndergraduateWebLogin.url))
// 用户进入教务页面后，由 App 的按钮或页面状态处理调用：
let result = try await UndergraduateWebLogin.complete(in: webView, using: client)
```

上述 WebKit API 在 MainActor 使用。`makeWebView()` 使用临时网站数据存储。完成入口先确认当前是教务 HTTPS 页面，再获取 Cookie、核对教务会话和学号，成功后才能调用业务查询。

## 登录结果和业务查询

`WUSTLoginResult` 现在只有两个状态：

| 状态 | 含义 |
|---|---|
| `.authenticated(cookie:)` | 当前 client 的教务会话已验证；Cookie 是敏感数据，不要打印 |
| `.loginRequired` | 缺少有效教务会话，App 需要展示新版登录入口 |

```swift
switch try await client.ensureSession() {
case .authenticated:
    let student = try await client.fetchStudentInfo()
    let terms = try await client.fetchAcademicTerms()
case .loginRequired:
    break // App 展示登录界面
}
```

`ensureSession()` 检查现有 Cookie 和教务会话，不获取新凭据，不自动发短信，不再调用任何旧接口。会话缺失或明确失效返回 `.loginRequired`；网络错误、TLS 错误、未知响应、服务器异常向上传递，不直接清空会话。多次并发检查共享同一操作。

业务查询复用当前会话。明确的业务认证失败转换为 `WUSTLoginClientError.notAuthenticated` 并标记当前会话不可用，后续由 App 展示登录。不再进行旧 TGT 换票或自动重试整个登录流程。

已有教务会话可以通过 `withUndergraduateSession(perform:)` 执行自定义只读请求。闭包收到 Cookie 和同一 URLSession；调用方不应长期持有它们，退出或换账号后不能继续使用。Demo 的课表原始页面采集也复用此入口。

## 续期、持久化和其他站点

当前登录只接入教务 Cookie。包尚未提供新版统一认证会话的保留、静默换票、导出导入或跨启动恢复，也没有后台定时保活。Cookie 有效时可以继续查询，失效后需重新登录；不能把本地时间或 HTTP 200 当作有效凭据证明。

图书馆、门户校车和学工第二课堂的查询与解析代码保留，旧 TGT 自动建会话分支已移除。这些站点需要各自有效的会话；新版教务登录不等于其他站点也登录。默认新 client 尚不能自动建立这些跨系统会话。App 已有对应站点的 URLSession/Cookie 时，可以使用 `LibraryService` 和 `SecondClassService` 的低层只读接口。新版跨系统 SSO 接入需要另行验证。

## 退出和并发

```swift
try await client.logout()
```

退出会取消当前认证或检查操作、清理待提交的短信上下文，替换内存 Cookie 容器。已退出操作的响应不能恢复旧账号会话。本地退出不会退出 Safari、其他 client 或其他设备。

登录和发送、提交短信互斥；重复操作抛 `.operationInProgress`。App 应禁用重复点击。一次界面等待取消不会直接取消其他调用者共享的检查；退出会取消该 client 的共享操作。

## 错误处理

| 错误 | App 处理 |
|---|---|
| `AuthServerCredentialError.invalidCredentials` | 独立提示账号或密码错误，由用户修改，不自动重复提交 |
| `AuthServerLoginError.invalidInput` | 检查账号、短信码或传入参数 |
| `.invalidForm`、`.invalidResponse` | 官网结构或响应变化，保留错误类别供排查 |
| `.loginNotCompleted` | 认证页面仍要求交互，不展示登录成功 |
| `.smsCodeRejected(code)` | 学校未确认发送短信；按安全业务码提示，不自动重发 |
| `SliderCaptchaError` | 识别、校验或重试额度未完成；可提供官方网页登录 |
| `WUSTLoginClientError.notAuthenticated` | 展示登录入口 |
| `.studentIDMismatch` | 账号不一致；不得展示这份学生数据 |
| `URLError` | 网络问题，保留可用状态并由用户重试 |

不要打印任意完整错误、请求 URL、表单或 HTML，其中可能含票据、Cookie、个人信息。日志只记录错误类别、安全状态码和不含身份信息的数值。

## Demo 与验证范围

运行 `swift run WUSTDemo`：菜单 1 检查当前会话，2 官方网页登录，3 清除当前会话，4 新版自动密码登录，5 新版短信登录，6 独立手动滑块登录。`--native-login`、`--sms-login`、`--manual-slider-login` 可直接选择对应流程；`--manual-slider-preview` 无账号预览滑块组件。菜单中的全新 client 测试现在明确要求重新登录。

密码 Demo 的本地加密账密文件与 Keychain 密钥仍保留，用于反复测试新版入口；库本身不保存密码。旧 TGT 的 Keychain 适配代码已删除，既有系统钥匙串条目不由这次代码清理自动删除，也不会再读取。

短信自动滑块失败时，macOS Demo 会打开官方短信页面继续。诊断日志保存在仓库外，不包含账号密码、Cookie 值或短信码。

2026-11-26 当前原生密码入口已实测 20 次：5 次完成登录及学生信息核对；55 次实际滑块校验中通过 5 次，另有一张本地判定不可靠的图在提交前排除。这是当时版本的小批样本，不代表稳定成功率。旧版已通过的 TGT/aTrust 验收不能作为新版续期或跨系统认证的证明。

回归测试使用合成页面和 URLProtocol，不连接学校，不发送真实短信，不读取真实 Keychain。算术 OCR 工具调用示例：

```swift
let answer = try VisionCaptchaSolver().solve(imageData: imageData)
```

App 的 watchOS 数据同步与未来凭据恢复规划见 [watchOS 规划](WatchOSPlan.md)；当前 Package.swift 尚未声明 watchOS 支持。
