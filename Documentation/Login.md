# 登录与会话接入

更新：2026-11-05。本文说明当前 `WUSTLoginClient` 的调用顺序、状态含义、凭据保存和错误处理。`Docs/login-design.md` 是早期调研草案；接口与实际行为以本文件和当前 Swift 源码为准。

## 能做什么

包封装了统一身份认证、图形验证码、短信二次验证、aTrust 回调与环境上报、教务 ST 换票、教务 Cookie 会话恢复，以及学生信息读取。课表和图书馆只读查询也已接入，分别见 [课表接入](Timetable.md) 和 [图书馆接入](Library.md)；课程与教学周路径已由用户运行，图书馆代码尚未运行验证。

本文返回值示例使用虚构资料或明确的占位符。方法直接返回 Swift 类型；登录状态和学生信息当前没有 Codable 协议，不应将示例当作服务器 JSON 或声称可以直接用 JSONEncoder 编码。

完整登录流程由 `WUSTLoginClient` 编排。App 仍可使用 Union、aTrust、Undergraduate 的低层接口自行换票。低层入口需要调用方传入同一 `URLSession`，自行承担顺序和 Cookie 容器。

当前支持 iOS 15+、macOS 15+、visionOS 1+。macOS Demo 使用 Vision 识别算术验证码。watchOS 尚未加入 Package.swift 支持；该平台规划中只提供选定只读功能，首次认证由配对 iPhone 等设备完成，见 [watchOS 规划](WatchOSPlan.md)。

## 认证过程中会遇到的凭据

| 名称 | 用途 | 保存建议 |
|---|---|---|
| TGT（`UnionCredential.tgt`） | 统一认证成功后由服务器签发，可申请不同系统的 ST | 由 App 使用 Keychain 按账号保存 |
| ST | 某个目标系统的一次性服务票据 | 仅在当前请求链中短暂使用，不作为持久凭据 |
| 教务 Cookie | 教务网站的业务会话 | 保留在该 client 的 URLSession Cookie 容器内 |
| aTrust 会话数据 | 完成 aTrust 环境和认证检查 | 保留在相同 URLSession 内，不当作手机与其他设备之间自动共享的登录态 |
| 密码、短信码 | 用户交互时用于完成身份验证 | 不由 client 保存或写入日志 |

`UnionCredential(tgt:)` 只封装字符串，不验证凭据是否有效。学校是否改变 TGT 的有效时长不由包推测。TGT 失效由换票响应识别；断网、TLS 错误和不明服务器响应不会被当作凭据失效。

## 一个账号使用一个 client

```swift
let client = try WUSTLoginClient(
    username: account,
    deviceID: appSavedDeviceID,
    credentialStore: appCredentialStore
)
```

`username` 用于隔离保存的 TGT，也用于校验返回学生信息的学号。`deviceID` 由 App 生成并在本机稳定保存，不能使用空字符串；不需要采集硬件序列号。`credentialStore` 是 App 实现的凭据存储，可选；未传入时 client 只在内存里保留 TGT。

一个 client 负责一个账号，并维护自己的临时 URLSession 与 Cookie 容器。把 client 保存在 App 的账号会话对象中，跨页面和业务调用复用。不要每次展示课表或学生信息时新建 client。切换账号前先 `try await oldClient.logout()`，再为新账号创建实例。

## App 必须实现凭据存储

`UnionCredentialStore` 是异步的 `Sendable` 协议，包含三个方法：

- `loadCredential(for:)`：读取对应账号的 TGT；没有保存值时返回 `nil`。
- `saveCredential(_:for:)`：保存新签发的 TGT。
- `clearCredential(for:)`：幂等删除这个账号的 TGT，未找到也按成功处理。

建议由 `actor` 实现，并用账号作为 Keychain account key。写入失败要抛错，不能假装保存成功。包在统一认证获得 TGT 后调用 `saveCredential`，之后即使 aTrust 或教务请求遇到网络错误，App 下次仍有机会恢复。

包不替 App 选择 Keychain access group、同步属性、设备可访问时机、迁移策略或备份策略。生产 App 不要将 TGT 放入 UserDefaults、普通文件或日志。Demo 的可读 Keychain 参考实现位于 [DemoCredentialStore.swift](../Sources/WUSTDemo/DemoCredentialStore.swift)，适用于演示其保存和读取方式，不替代 App 自己的 Keychain 策略。Demo 只保存 TGT，不保存密码、短信码、ST 或 Cookie。

没有 store 时，可在 client 初始化时传入 App 从安全存储取出的 `UnionCredential(tgt:)`。如果既没有初始凭据也没有 store，client 返回 `loginRequired`；App 再显示登录界面。

## 首次登录和状态分支

需要登录时，App 收集账号和密码，然后调用：

```swift
let result = try await client.login(password: password)
```

默认流程会获取 aTrust 服务入口、获取图形验证码、用 Vision 解出算术答案、提交统一认证，并继续完成 aTrust 与教务会话。密码只作为方法参数参与本次流程，client 不保存它。默认最多更换图形验证码 3 次；只有图片识别失败会触发这个重试。

每次调用都必须根据 `WUSTLoginResult` 分支处理：

```swift
switch result {
case .authenticated:
    let info = try await client.fetchStudentInfo()
case .loginRequired:
    break
case .verificationRequired(_, let methods):
    break
case .additionalAuthenticationRequired(let nextService):
    break
}
```

含义如下：

| 结果 | 含义与 App 动作 |
|---|---|
| `.authenticated(cookie:)` | aTrust 和教务会话均已检查，可以调用 `fetchStudentInfo()` 或后续业务方法。关联 Cookie 属于敏感会话数据，不要打印。 |
| `.loginRequired` | 没有 TGT 或 TGT 已明确失效。显示账号密码输入，用户提交后再调用 `login(password:)`。 |
| `.verificationRequired(challenge, methods:)` | 当前认证还未完成。按 `methods` 显示可用方式；当前高层入口支持短信。 |
| `.additionalAuthenticationRequired(nextService:)` | aTrust 返回尚未支持的认证步骤。不得显示登录成功；交给 App 提示或终止当前流程。 |

`.authenticated` 只表示此 client 已建立并检查教务会话，不代表所有系统、其他设备或浏览器都已登录。

### 返回值示例

`ensureSession()`、`login(password:)`、`submitSMSCode(_:password:)` 都返回 `WUSTLoginResult`。下面是四种结果的内容示意，不是 Swift 构造代码，也不是可直接解码的 JSON：

```text
authenticated(cookie: "<教务 Cookie 占位>")

loginRequired

verificationRequired(
    challenge: { uid: "<本次挑战标识占位>" },
    methods: [sms, wechat]
)

additionalAuthenticationRequired(nextService: "auth/<尚未支持的步骤>")
```

第三种结果中，Swift 实际值是 `.verificationRequired(challenge, methods: [.sms, .wechat])`；`challenge.uid` 为 String，`methods` 为 `[UnionVerificationMethod]`。挑战还有包内部使用的数据，App 不需要手工构造挑战，也不要只凭 uid 自己拼出验证请求。验证方式不保证每次都有两项，应以本次返回的数组为准。

第四种结果的 `nextService` 类型为 `String?`，也可能是 nil；有结果对象不表示认证成功，必须根据枚举分支处理。

所有高层方法的返回类型与无值情况如下：

| 方法 | 成功返回值 | 示例或含义 |
|---|---|---|
| `ensureSession()` | `WUSTLoginResult` | 上述四种状态之一 |
| `login(password:)` | `WUSTLoginResult` | 可能认证成功，也可能要求验证 |
| `submitSMSCode(_:password:)` | `WUSTLoginResult` | 继续登录后的状态，不是 Bool |
| `sendSMSCode()` | `Void`，即 `()` | 正常返回表示发送请求被确认；失败抛错 |
| `currentCredential()` | `UnionCredential?` | `UnionCredential(tgt: "<TGT 占位>")` 或 nil；通过 `await` 读取 |
| `fetchStudentInfo()` | `StudentInfo` | 见下文完整字段示例 |
| `fetchAcademicTerms()` | `AcademicTermList` | 见 [课表返回示例](Timetable.md#2-让用户选择服务器提供的学期) |
| `fetchTimetable(term:maxWeek:maxSection:)` | `Timetable` | 见 [整学期返回示例](Timetable.md#3-获取整学期课表) |
| `fetchTeachingCalendar(on:)` | `TeachingCalendar` | 服务端周次校准及日期范围，见 [返回示例](TeachingCalendar.md#2-返回值示例)；正常校准和换周重新校准已由用户运行通过 |
| `fetchLibraryDashboard()` | `LibraryDashboard` | 图书馆统计、当前借阅和即将到期列表。五项统计及各卡片的明细查询见 [图书馆接入](Library.md) |
| `logout()` | `Void`，即 `()` | 本地清理完成；不返回服务端注销状态 |

`Void` 方法不返回服务器的业务码、短信内容或 `true`；错误通过 `throws` 传递。`currentCredential()` 是读取当前内存中的凭据，不触发 Keychain 加载、登录或有效性校验，因此 nil 本身不等于服务器宣布 TGT 失效。

## 短信验证

短信不是自动发送的。App 收到 `.verificationRequired(_, methods)` 后，先确认 `methods` 包含 `.sms`，展示用户可理解的提示；只有用户明确点击发送时才调用：

```swift
try await client.sendSMSCode()
```

成功返回只表示服务器确认发送请求。App 再取得短信内容，并把验证码和用户重新输入的密码传入：

```swift
let result = try await client.submitSMSCode(code, password: password)
```

client 不长期持有密码；短信校验通过后，会取得新图形验证码并继续统一认证。服务端如果仍返回二次验证，方法返回新的 `.verificationRequired`，不会自动重复发送短信。短信挑战成功提交后即被消费；若之后识图或网络失败，不要再次提交旧验证码。可以根据错误让用户重新开始登录。

当前 `UnionVerificationMethod` 提供 `.sms`、`.wechat`。WUSTLoginClient 尚未提供微信扫码流程；如返回的挑战没有 `.sms`，App 应说明当前版本无法继续，不要尝试调用短信接口。

## 复用与恢复

每次需要课表等业务数据时调用 client 的业务方法。若业务 Cookie 仍有效，复用同一个会话。若 Cookie 缺失或明确失效，包会按以下顺序尝试恢复：

1. 从 App 的 `UnionCredentialStore` 读取本账号 TGT。
2. 用 TGT 获取 aTrust ST，完成 aTrust 回调、所需环境上报和身份检查。
3. 用 TGT 获取教务 ST，重建并检查教务 Cookie。
4. 返回可用结果。

App 可主动检查当前状态：

```swift
let result = try await client.ensureSession()
```

有效 Cookie 路径不会重新申请 ST。没有保存的 TGT 或 TGT 明确失效时，结果为 `.loginRequired`；明确失效的本账号 TGT 会从 store 清除。

会话预检只对 `.cookieMissing` 和 `.invalidSession` 自动进入 TGT 恢复。课表请求另对明确的 `TimetableError.authenticationRequired` 最多恢复并重试一次。网络故障、TLS 错误、其他 HTTP 错误、解码问题、服务器故障、未知教务检查页都作为错误返回；不会删掉 TGT，也不会自动重试密码、验证码或短信。多次并发 `ensureSession()` 会共享一项恢复操作，避免同一 client 重复换票。

Cookie 有效时，即便 TGT 之后过期，现有业务会话仍可继续使用。只有需要重建业务会话、服务器再次要求登录时，App 才会看到 `.loginRequired`。包不假设 TGT 或 Cookie 的固定寿命，也不在后台定时保活。

## 读取学生信息

```swift
let info = try await client.fetchStudentInfo()
```

该入口会先调用 `ensureSession()`，然后用同一 URLSession 和教务 Cookie 读取学生信息页。解析出的学号必须等于初始化 client 时使用的账号；不一致时，包会清理当前 client 与该账号的本地凭据并抛 `WUSTLoginClientError.studentIDMismatch`，不会返回这份信息。

若 App 还未处理登录状态就直接调用业务方法，而 `ensureSession()` 返回登录或额外验证状态，`fetchStudentInfo()` 会抛 `WUSTLoginClientError.notAuthenticated`。需要展示短信或其他验证 UI 时，先直接调用 `ensureSession()`、`login(password:)` 并处理 `WUSTLoginResult`。

课表入口为 `fetchAcademicTerms()` 和 `fetchTimetable(term:maxWeek:maxSection:)`，与学生信息共用内部认证执行方法和会话版本检查。完整选择学期、筛选课程与错误处理见 [课表接入](Timetable.md)。

`fetchStudentInfo()` 和低层 `StudentInfoService.fetchStudentInfo(cookie:using:)` 都返回 `StudentInfo`，完整字段形状如下。这里的学号、身份信息均为虚构占位，实际高层调用会要求返回学号与 client 账号一致：

```swift
StudentInfo(
    name: "示例同学",
    studentID: "SAMPLE-STUDENT-001",
    college: "示例学院",
    major: "示例专业",
    className: "示例班级",
    birthday: "2000-01-01",
    sex: "示例性别",
    nationality: "示例民族",
    hometown: "示例地区",
    idNumber: "<身份证号占位>"
)
```

以上十个属性当前都是非可选的 String，生日没有转换成 Date，学号和身份证号也不转换为整数。该类型目前只有 Sendable，没有 Codable；如果 App 要保存或导出 JSON，应自行定义所需 DTO 或编码方式。高层在学号不匹配时抛错，不会返回上面形状的另一个账号数据。

## 错误处理

这些错误分别说明网络层、认证层和业务会话层的问题：

| 错误类别 | 典型情况 | 建议处理 |
|---|---|---|
| `URLError` | 断网、DNS、TLS、请求超时 | 提示网络问题；保留 TGT；由用户发起下一次操作 |
| `UnionAuthServiceError` | 登录业务码拒绝、短信发送或校验失败、TGT 换票过期 | 按错误类型更新 UI；只有已识别的 TGT 过期分支进入重新登录 |
| `ATrustAuthServiceError` | aTrust 拒绝请求、回调无效、环境上报或认证检查失败 | 保持为 aTrust 错误展示，不冒充教务登录成功 |
| `UndergraduateAuthServiceError` | 教务会话无效、站点不可用、页面编码或响应异常 | 保留原错误；仅明确 `.invalidSession` 才做会话恢复 |
| `WUSTLoginClientError` | 操作冲突、没有待验证挑战、学生信息账号不匹配 | `.operationInProgress` 禁用重复按钮；账号不匹配清理状态并提示重新登录 |
| 凭据存储错误 | Keychain 读取、保存或清除失败 | 提示安全存储操作失败；不要忽略或假设持久化成功 |

不要把任意错误的完整描述写入日志。URL、服务器回显或 HTTP body 可能带票据、Cookie、个人数据。对用户展示错误类别和安全的状态码即可；不要打印账号、TGT、ST、Cookie、短信码、验证码、完整 HTML 或完整错误 URL。

## 并发、取消、退出和切换账号

- 同一账号保留一个 WUSTLoginClient。client 内登录、发短信、提交短信和会话恢复互斥；收到 `.operationInProgress` 时，App 禁用重复操作并等待当前操作完成。
- 并发恢复请求共享同一任务。单个界面等待者取消，不会取消其他调用者共享的恢复任务。
- `try await client.logout()` 会清除内存凭据、待验证挑战、当前 Cookie 容器和 store 中该账号的 TGT，并取消 client 当前网络操作。
- 本地 logout 不会撤销学校服务端的 TGT，不会退出 Safari、其他 client、Watch 或其他设备。
- 清理 store 失败会抛错。内存状态与当前 URLSession 已清理，但 App 应告知安全存储清除失败。
- 切换账号时，先等待旧 client 的 `logout()` 返回，再释放旧 client，创建使用新账号和相应 store 的 client。
- 多个 client 若共用同一个 store account，仍需要 App 协调；推荐同一账号只有一个活跃 client。

## 手动低层接口

特殊 App 可自行创建并管理 URLSession，按需组合这些接口：

- `UnionAuthService.beginLogin(...)`：获取 `UnionLoginResult`，包括账号密码登录或短信验证挑战。
- `UnionAuthService.fetchCaptcha(using:)`、`sendSMSCode(...)`、`verifySMSCode(...)`：手动负责验证码和短信 UI。
- `UnionAuthService.fetchServiceTicket(credential:service:using:)`：使用已有 TGT 为目标服务申请 ST。
- `ATrustAuthService.login(credential:deviceID:using:)`：用已有 TGT 完成 aTrust 登录。
- `ATrustAuthService.completeLogin(ticket:service:deviceID:using:)`：提交已有 ST 并完成 aTrust 后续步骤。
- `UndergraduateAuthService.currentSessionCookie(using:)`：检查和读取现有教务 Cookie。
- `UndergraduateAuthService.login(credential:using:)`：用已有 TGT 重建教务会话。
- `StudentInfoService.fetchStudentInfo(cookie:using:)`：自己提供已建立的 Cookie 和 session。
- `TimetableService.fetchAcademicTerms(cookie:using:)`、`fetchTimetable(term:cookie:using:)`：使用已有会话查询课表；低层不自动恢复认证。
- `TeachingCalendarService.fetchTeachingCalendar(on:cookie:using:)`：按日期查询服务器周次并建立日期换算模型；低层不自动恢复认证。
- `LibraryService.fetchDashboard(credential:using:)`：使用已有 TGT 建立图书馆 Cookie 会话，并读取统计、当前借阅和即将到期；低层不自动恢复认证。

直接账号密码换服务票据的旧 `UndergraduateAuthService.login(username:password:...)` 与 `ATrustAuthService.beginLogin(...)` 已标记 deprecated。新 App 优先用 WUSTLoginClient；需自定义流程时使用返回 `UnionLoginResult` 的新低层登录接口。

底层流程须贯穿同一 URLSession，才能复用相应 Cookie 与服务端会话。不要把一个 URLSession 的 Cookie 当成另一个会话的认证证明。

低层入口的主要返回值如下；这些结构由包解析产生，表中的结构示意不是公开初始化 API：

| 入口 | 返回类型 | 内容示例或判定方式 |
|---|---|---|
| `UnionAuthService.fetchCaptcha(using:)` | `LoginCaptcha` | `uid` 为挑战标识，`content` 为图像内容字符串；不返回算术答案 |
| `UnionAuthService.beginLogin(...)` | `UnionLoginResult` | `.authenticated(UnionCredential(tgt: "<TGT 占位>"))` 或 `.verificationRequired(challenge)` |
| `UnionAuthService.fetchServiceTicket(...)` | `String` | `"ST-<一次性票据占位>"`；不是包含 ticket 字段的 JSON 对象 |
| `ATrustAuthService.exchangeCASTicket(...)` | `(Data, HTTPURLResponse)` | 原始回调响应字节和 HTTP 响应，尚不等于认证成功 |
| `ATrustAuthService.parseCASCallback(...)` | `ATrustCASCallbackResult` | `environmentTicket: String?`、`nextService: String?`，用于后续环境上报和状态检查 |
| `ATrustAuthService.login(...)`、`completeLogin(...)` | `ATrustAuthenticationResult` | 见下面状态示例，必须检查 `isAuthenticated` |
| `UndergraduateAuthService.login(credential:using:)`、`currentSessionCookie(using:)` | `String` | `"<教务 Cookie 占位>"`；值用于 Cookie 请求头 |
| `UnionCredentialStore.loadCredential(for:)` | `UnionCredential?` | 有保存值时返回凭据，没有保存值时为 nil |
| `UnionCredentialStore.saveCredential(...)`、`clearCredential(...)` | `Void` | 保存或清除成功，无响应对象；存储失败抛错 |

`ATrustAuthenticationResult` 的字段示意：

```text
成功：
  sidTicket = "<aTrust 会话票据占位>"
  nextService = ""
  isAuthenticated = true

仍有后续步骤：
  sidTicket = nil
  nextService = "auth/<后续步骤>"
  isAuthenticated = false

信息不足：
  sidTicket = nil
  nextService = nil
  isAuthenticated = false
```

`isAuthenticated` 当前要求非空 `sidTicket` 且 `nextService` 等于空字符串；仅有票据、仅有 HTTP 200 或 `nextService == nil` 都不足以认定成功。

## Demo 操作

```sh
swift run WUSTDemo
```

Xcode Package Scheme 运行时，选择真正的控制台：菜单 View → Debug Area → Activate Console。启动时选择：

1. 默认恢复：复用本地课表 Cookie 或 Keychain TGT。
2. 重新登录：清除该账号旧 TGT 后从账号密码重新认证。
3. 清除本地登录：删除 Demo 的本地 TGT 和当前 client 会话。

短信界面由 Demo 等待用户明确选择发送后才调用接口。首次成功后进入循环菜单，可选择在新的 client/URLSession 中恢复、继续复用当前业务会话、清除登录、采集原始课表（菜单 4）、查询结构化课表（菜单 5）、查询教学周日期（菜单 6）或查询图书馆只读信息（菜单 12）。切换到新的 client 后，后续菜单使用恢复后的会话。Demo 的 Keychain service 是 `WUSTFoundation.WUSTDemo.UnionCredential`；只在这份示例中使用，不与生产 App 共用访问组。

运行时示例目前是 macOS Demo，不代表在 iPhone 真机、iOS App 或 watchOS App 已完成集成测试。

## 验证状态

已由用户实际运行通过：短信验证、TGT 获取、aTrust CAS 回调与环境上报、authCheck、教务会话建立、学生信息读取并核对登录学号；也已验证在同一 Mac 上以新 URLSession 使用已有 TGT 恢复。

本地验证包括：macOS Demo 构建、iOS Simulator 库构建，以及 21 项合成协议测试。Keychain 适配器已编译；真实 Keychain 持久化和退出重启后的跨启动恢复尚需用户运行新版 Demo 验收。尚未验证 iPhone 真机、Watch 设备、TGT 跨设备复用和学校对 Watch/aTrust 环境的策略。

上述自动构建和测试是课表接入前的结果。2026-11-05 用户已运行新版 Demo，当前学期查询得到 19 条安排，第 1 周按星期筛选也得到对应结果；下一学期查询仍有表单错误。助手未运行本轮编译或自动化测试；本次日志不证明自动恢复重试、退出并发保护及其他平台均已验证。

用户之后运行通过 `20261105` 的教学周校准，并确认 `20261109` 换周重新校准通过。课表和日期的新增边界回归已写入但未运行，详见 [课表第一版验收记录](TimetableAcceptance.md)。

所有自动认证测试仅使用合成账号、TGT、ST、环境票据与验证码，通过 URLProtocol 拦截网络；不连接学校、不发送真实短信、不读取真实个人学籍页面、不读写真实 Keychain。测试样本目录 `TestData/` 已在 `.gitignore` 中，测试代码不依赖该目录。

## watchOS 后续边界

watchOS 后续只规划选定只读业务功能和已有授权恢复，账号密码、验证码与短信登录由 iPhone 等设备完成。TGT 能否由 iPhone 传到 Watch 后成功换票尚未实测；手机的 URLSession、Cookie 和 aTrust 会话不会自动共享给 Watch。

跨设备传递、手机查询后同步业务数据、能力拆分及真机验收详见 [watchOS 规划](WatchOSPlan.md)。Package.swift 目前尚未声明 watchOS 支持。
