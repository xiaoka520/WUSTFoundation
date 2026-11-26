# 胖乖生活登录

洗衣机门店与空闲设备的查询可独立于账号登录。需要读取用户本人的订单时，使用胖乖生活凭据。App 负责手机号和验证码输入、用户界面及钥匙串存储。

## 短信登录与复用

```swift
import WUSTFoundation

let auth = LaundryAuthService()
try await auth.sendSMSCode(to: phone)
let credential = try await auth.login(phone: phone, smsCode: smsCode)

// App 将 credential 编码为 Data 存入本设备的钥匙串。
let restored = try await auth.restore(credential)
```

`sendSMSCode` 先向服务器确认是否需要人机验证。若抛出 `LaundryAuthError.captchaRequired`，App 可以在 `WKWebView` 打开 `LaundryWebLogin.url`，由用户完成胖乖官方页面的验证和登录。完成后在主线程调用 `LaundryWebLogin.credential(from: webView, using: auth)`，方法只从胖乖官方来源读取凭据，并向服务端验证。登录视图可使用独立的临时网站数据存储。

`restore` 使用 `user/info` 确认凭据及账号。服务端业务码 `2` 表示需要重新登录。超时、HTTP 错误和异常响应保留原凭据，方便稍后重试。恢复成功后，把更新后的 `LaundryCredential` 写回钥匙串。其编码内容包含 Token，只适合用于受保护的存储。

## 有效期

`firstVerifiedAt` 与 `lastVerifiedAt` 是同一凭据首次及最近一次验证成功的本地时间。两者之差只表示实测可用时长的下限。胖乖网页把 Token 保存在浏览器的持久存储中，公开网页代码里没有找到过期时间或可调用的续期接口。保存凭据可跨启动复用，查询成功只更新本地观测时间。实际有效期由胖乖服务端决定，退出、换设备及服务端策略都可能影响结果，需分别实测。

## 查询洗衣机

App 可以调用 `LaundryDeviceService.fetchNearbyShops(latitude:longitude:page:)` 传入高德坐标查询附近门店，也可以直接调用 `fetchNearbyShops()` 使用武汉科技大学黄家湖校区的默认定位。两种调用都支持用 `page` 指定页码。

取得门店后，用 `fetchInventory(for:)` 获取设备总数与名单。南区、北区依次排列，各区内按楼栋和机号自然排序。`南5-1` 和 `南楼5-3` 会排在同一栋，设备名称沿用胖乖返回的原文。

`inventory.shop.machineCount` 是门店报告的设备总数，`inventory.availableDevices` 是实际查到的空闲设备。`inventory.allDevices` 只在空闲名单已覆盖门店设备总数时有值，否则为 `nil`。已验证的设备接口只提供空闲明细，门店统计与名单分开查询，设备状态变化时数字可能不同。

## 使用中订单与剩余时间

登录后查询本账号的使用中洗衣机订单。

```swift
let service = LaundryOrderService()
let snapshots = try await service.fetchRunningWashers(credential: credential)

for snapshot in snapshots {
    let name = snapshot.order.machineName
    let end = snapshot.estimatedCompletionTime
    let seconds = snapshot.remainingSeconds(at: Date())
}
```

订单来自官方网页“我的 → 我的订单”。服务先用 GET `order/list` 分页读取订单，再筛选 orderType 为 1、orderStatus 为 2、parentTypeId 为洗衣机类别的记录，并用 POST `order/detail` 查询当前详情。不会因为首页出现已完成订单就停止翻页。

`fetchOrders(credential:page:)` 提供单页订单与 nextPage，`fetchOrderDetail(orderID:credential:)` 支持单独刷新某一订单。列表与详情之间已结束的订单会从使用中结果排除。

返回快照包括以下字段。

| 字段 | 含义 |
| --- | --- |
| `order` | 订单 ID、状态、设备名、门店名、设备类别和可用的模式名称 |
| `estimatedCompletionTime` | 接口 completeTime 按北京时间解析后的 Date，可为空 |
| `observedAt` | 本次详情请求完成的本地采样时间 |
| `remainingSeconds` | 以 HTTP Date 中服务器时间为基准计算的剩余秒数，无服务器时间时采用本地采样时间 |
| `remainingSeconds(at:)` | 按采样后的本地时间流逝推算倒计时，最低为 0 |

例如服务器时间为北京时间 21:00:00，completeTime 为 21:02:22，返回 remainingSeconds 为 142。采样后经过 10 秒，remainingSeconds(at:) 返回 132。这是合成的字段示例。

已完成订单与未提供结束时间的订单返回 nil 倒计时。倒计时归零时，orderStatus 仍保留查询时的状态。completeTime 是服务器提供的预计时间。

## 按剩余时间校正

每笔订单创建并复用一个 `LaundryOrderMonitor`，调用 `currentSnapshot()` 更新剩余时间。

```swift
let monitor = LaundryOrderMonitor(
    orderID: snapshot.order.id,
    credential: credential,
    initialSnapshot: snapshot
)

let latest = try await monitor.currentSnapshot()
let seconds = latest.remainingSeconds(at: Date())
```

| 当前剩余时间 | 远端详情的最长缓存时间 |
| --- | --- |
| 大于 10 分钟 | 2 分钟 |
| 大于 5 分钟、至多 10 分钟 | 1 分钟 |
| 大于 2 分钟、至多 5 分钟 | 30 秒 |
| 至多 2 分钟，包括倒计时归零 | 每次调用均请求远端 |

首次没有快照时直接请求远端。有快照时，每次调用先估算当前剩余秒数，再按当前区间检查缓存年龄。跨入较短的区间后使用较短的缓存期限。未提供剩余时间时也会请求远端。相互重叠的调用共享进行中的同一次请求。

远端延长预计结束时间时，下次校正会采用新的时间，并重新选择缓存期限。校正失败会抛错，保留的旧快照不会被当作本次成功结果返回；再次调用仍会尝试校正。

App 负责安排调用和绘制界面。`remainingSeconds(at:)` 用于快照的本地倒计时，`currentSnapshot()` 根据上述规则决定何时请求远端。请复用 monitor 实例，以保留缓存。`fetchOrderDetail` 始终请求远端，适合主动强制刷新。

业务码 2 会抛出 LaundryAuthError.loginRequired，网络错误和其他业务码继续向上传递。

已在登录的 Safari 中核对使用中洗衣机订单、状态值、详情中的 completeTime 以及网页计算逻辑。包内分页、服务器时钟计算、未知时间和凭据失效路径使用合成响应回归测试，真实账号通过包查询仍待 Demo 验证。

## 独立测试

在 Xcode 顶部选择 `WUSTLaundryDemo`，运行后在控制台输入 `1` 查询洗衣机，输入 `2` 测试胖乖登录，或输入 `3` 查询本账号使用中的洗衣机及剩余时间。终端也可以运行以下命令。

```sh
swift run WUSTLaundryDemo
```

首次测试登录时，在登录菜单选择 `2`，在本机输入手机号和短信验证码。下次运行选 `1` 可用钥匙串里的同一凭据验证登录状态。遇到人机验证时，命令行会停在发短信前。

菜单 3 使用此前保存在钥匙串里的胖乖凭据。输入 1 使用 monitor 更新当前订单，按剩余时间决定是否请求远端；输入 2 重新查询本账号当前使用中的订单。首次使用先通过菜单 2 完成胖乖登录。
