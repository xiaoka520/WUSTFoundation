# watchOS 后续支持规划

更新：2026-11-03。状态：规划，当前 Package.swift 尚未声明 watchOS 支持，本文不代表已经通过 watchOS 编译或真机认证。

## 1. 能力边界

iPhone 等具备完整登录能力的设备负责账号密码、图形验证码、短信和其他交互验证。Watch 只消费已授权的数据或凭据，提供课表等选定的只读功能。

这里区分两件事：

- 首次身份认证：必须在 iPhone 等设备上完成。
- 已有凭据恢复：Watch 可能仍需使用 TGT 申请自己的 ST、建立自己的 aTrust/教务 Cookie 容器。这属于已有授权的会话恢复，不能理解为 Watch 完全不发送认证请求。

Watch 接口不提供 login(password:)、图形验证码识别、发送短信和提交短信。需要重新认证时返回 needsCompanionAuthentication，由 App 引导用户回到 iPhone 完成验证。

## 2. 当前证据和不能直接下结论的部分

Apple 官方支持 watchOS 使用 URLSession 访问网络，并支持 WatchConnectivity 在配对 iPhone 与 Watch App 间传输数据。

本包目前用 TGT 换 ST 时只提交 TGT 和 service，没有在该请求内显式绑定手机硬件标识。因此“从另一设备导入 TGT 后恢复业务会话”在客户端结构上可实现。

但学校是否在服务端绑定设备、IP、风控上下文，以及 aTrust 是否允许 Watch 的真实环境建立会话，尚未验证。同一 Mac 上的新 URLSession 恢复成功，不等于跨设备恢复成功。

手机登录成功、手机可访问校园网，均不自动证明手表会话有效或手表所在网络可达。不能用伪装手机设备标识、谎报平台或忽略服务端验证要求的方式强行通过。

## 3. 两条取数路径

### A：导入凭据，Watch 自己取数

```text
iPhone 完成完整登录
    → App 将账号及现有凭据传到配对 Watch
    → Watch 将凭据存入自己的安全存储
    → Watch 用 URLSession 建立自己的业务会话
    → Watch 调用课表等只读接口
```

优先验证 TGT 导入路径。ST 一次性且与 service 绑定，不作为长期同步和持久化的凭据。

业务 Cookie 也可以设计导入入口，但是否能跨设备使用需要实测；只拿到 Cookie 字符串不代表拿到了完整 aTrust 状态。若传 Cookie，必须保留适用域名、路径、Secure、过期时间等必要属性，按目标域隔离。

Watch 不共享 iPhone 的 URLSession、Cookie 容器或内存状态。不能把两个 App 配置相同 App Group、Keychain access group 或 deviceID，当作自动读取另一设备凭据的实现。当前 Demo 的 ThisDeviceOnly Keychain 存储也不是跨设备同步功能。

Watch 使用自身稳定的设备标识。aTrust 对平台和环境信息的接受方式必须核实；需要额外验证时停止恢复，并请求 iPhone 处理。

TGT 是账户登录凭据，不是学校签发的只读、低权限 Watch token。只读限制由 Watch 客户端公开接口实施，不宣称服务器缩小了 TGT 的权限范围。

### B：iPhone 取数，向 Watch 同步数据

```text
iPhone 使用现有 client 获取课表
    → App 通过 WatchConnectivity 同步 Codable 数据
    → Watch 保存并展示最近一次课表
```

作为配对 App 的同步路径和独立直连不可用时的备用方案。优先同步课表等必要业务数据，不必把 TGT 发给 Watch。

iPhone 暂不可达时，Watch 展示带更新时间的本地数据。不能承诺手机离线、后台未获运行机会时仍能立即刷新。后续若需要长期脱离 iPhone 的实时查询，必须完成 A 路径真机验收。

## 4. WatchConnectivity 和跨设备职责

WatchConnectivity 由 App 层实现，不放进学校接口包的网络服务中。

- 可达时使用 sendMessage/sendMessageData 做即时请求和响应。
- updateApplicationContext 适合最新账号状态、授权版本和最新数据快照；它会替换旧快照，不作为每条必达命令的队列。
- transferUserInfo 可用于需排队传递的状态事件；传输可能延迟，不视为实时送达。
- 每份同步数据至少包含协议版本、账号标识、授权版本和更新时间；凭据导入需校验账号及版本。
- 拒绝旧账号、旧授权版本的延迟消息，避免退出或切换账号后旧消息恢复旧登录。
- 不传密码、短信验证码和图形验证码答案；凭据不输出到日志，也不作为普通课表缓存落盘。

WatchConnectivity 这条路径面向配对 iPhone。macOS、iPadOS 或其他设备的凭据传递不能直接套用相同连接，需要 App 另行提供受信任的传递机制；第一阶段只验证配对 iPhone。

## 5. 包的分层调整

未来新增 Watch 可依赖的轻量产品 WUSTFoundationCore；现有 WUSTFoundation 继续作为完整入口，兼容已有调用方。

WUSTFoundationCore 计划包含：

- Sendable/Codable 的学期、课程、课表等业务模型。
- 纯 HTML/字符串解析及必要的 SwiftSoup 依赖。
- 已有业务会话下的只读请求服务。
- 已有凭据的表示、导入与存储协议。
- 在跨设备实测通过后加入仅凭已有 TGT 的换票/会话恢复能力。

完整登录、Vision 验证码识别、密码编码和短信验证留在完整登录能力中。当前 WUSTLoginClient 默认直接引用 VisionCaptchaSolver，Union 请求工厂同时包含密码、短信和换票构造；这些依赖需要按能力拆开，不能只在 Package.swift 增加 .watchOS 就宣称完成。

不依赖“某个最新 watchOS SDK 能否导入 Vision”来划分能力：产品要求本身就是 Watch 不发起完整登录。支持的最低 watchOS 版本在基础 target 的 API 可用性与编译验收后确定。

公开业务模型只保留一个定义来源；完整产品继续提供兼容入口，避免各平台维护不同的 CourseMeeting 或 Timetable。

## 6. Watch 客户端接口方向

计划新增 WUSTReadOnlyClient，只暴露：

- 导入来自 App 的有效授权上下文。
- ensureSession：检查业务会话，必要时只用已有凭据恢复。
- fetchAcademicTerms、fetchTimetable 等实际已实现的只读业务方法。
- clearAuthorization：清除本设备凭据、会话和按策略处理的账号缓存。

暂定结果语义：ready、needsCompanionAuthentication；网络不可达、服务器故障和页面解析失败作为单独错误保留，不能把所有错误都提示为需要登录。

如果要获取新的验证码或二次验证，立即交回 iPhone；Watch 不自动尝试密码登录、不发送短信、不循环恢复。

App 负责 WCSession、界面、Watch Keychain、课表缓存、Widget/复杂功能和刷新时机。包负责服务器请求、解析及状态表达。

## 7. 过期、退出和账号切换

- Watch 端 TGT 或业务会话失效：请求新的手机授权，未取得前只展示允许保留的缓存。
- iPhone 退出或切换账号：清理手机本地状态，并发送带新授权版本的清除状态。
- Watch 收到清除状态后，清理自身凭据与该账号会话，拒绝此前版本的延迟消息。
- 手机上的本地 logout 不会自动撤销学校服务器上的 TGT。Watch 离线时无法保证立即收到退出消息；若要求跨设备即时撤销，需要服务器提供经过验证的撤销机制。
- 不假定两个设备上的凭据过期时间相同，也不编造 TGT 有效期；仅使用服务器已确认的信息。

## 8. 实施顺序和验收

1. 当前课表模型与解析继续使用 Foundation/SwiftSoup，业务数据采用 Codable、Sendable，先避免引入平台 UI 依赖。
2. 完成 iPhone/macOS 课表主线后，拆分轻量产品并进行 watchOS 编译验证。期间保留现有完整登录回归。
3. App 层实现配对设备的数据同步路径，先让 Watch 能查看最近课表。
4. 在真机上验证 iPhone 获得的 TGT 是否能让 Watch 申请 ST、完成必要的 aTrust/教务恢复并读取业务信息。
5. 通过后开放 Watch 独立取数；未通过时保留手机取数同步，并记录服务端拒绝的具体环节，不绕过风控。
6. 集中验收：Watch 经 iPhone 代理联网、Watch 自身 Wi-Fi、Watch 蜂窝、手机不可达、凭据过期、退出事件延迟、切换账号与旧消息回放。

模拟器通过不等于真机网络和凭据策略通过。不同网络可能走不同校园网/aTrust 路径，应分别核对。

## 官方依据

- [Keeping your watchOS content up to date](https://developer.apple.com/documentation/watchos-apps/keeping-your-watchos-app-s-content-up-to-date)
- [WCSession](https://developer.apple.com/documentation/watchconnectivity/wcsession)
- [Watch Connectivity](https://developer.apple.com/documentation/watchconnectivity)
- [TN3135: Low-level networking on watchOS](https://developer.apple.com/documentation/technotes/tn3135-low-level-networking-on-watchos)

这些来源证明 Apple 平台具备对应网络和配对通信能力，不证明学校已接受跨设备凭据。
