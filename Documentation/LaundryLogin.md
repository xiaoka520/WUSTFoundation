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

## 独立测试

在 Xcode 顶部选择 `WUSTLaundryDemo`，运行后在控制台输入 `1` 查询洗衣机，或输入 `2` 测试胖乖登录。终端也可以运行以下命令。

```sh
swift run WUSTLaundryDemo
```

首次测试登录时，在登录菜单选择 `2`，在本机输入手机号和短信验证码。下次运行选 `1` 可用钥匙串里的同一凭据验证登录状态。遇到人机验证时，命令行会停在发短信前。
