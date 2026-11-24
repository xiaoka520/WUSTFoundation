# 新版统一认证与自动滑块

学校的统一认证目前使用 `/authserver/login`。旧 `/lyuapServer` 的算术图片接口不能直接替换成滑块接口。

## 运行 Demo

在终端进入 Swift 包目录后运行：

```sh
# 不提交账号密码，仅实测取图、匹配、加密和服务端滑块校验
swift run WUSTDemo --slider-captcha

# 输入账号和密码，使用新版原生登录；密码由终端隐藏读取
swift run WUSTDemo --native-login
```

也可以直接在 Xcode 中选择 `WUSTDemo` / `My Mac`，按 `⌘R`，在底部控制台输入账号并选择 `4`。Xcode 下使用安全密码弹窗；终端下使用隐藏密码输入。无需配置启动参数。

原有网页登录入口仍可使用。`--native-login` 遇到服务器要求额外验证时会明确报错，不会把未完成认证当作成功。

## App 调用

复用现有的 `WUSTLoginClient`：

```swift
let result = try await client.loginWithAuthServer(password: password)
if case .authenticated = result {
    let info = try await client.fetchStudentInfo()
}
```

此入口使用一个新的临时 URLSession 访问登录页、读取表单动态参数、获取并解决滑块、提交加密后的密码。最后通过学生信息接口确认登录账号，验证成功才替换 client 的教务会话。网络或识别失败不应视为密码错误。

目前此入口接入的是教务会话，不生成旧 `/lyuapServer` REST 接口使用的 TGT，也不承诺跨进程恢复或其他业务系统的登录。短信等额外认证流程仍可使用网页登录入口。

## 单独使用滑块模块

```swift
let session = URLSession(configuration: .ephemeral)
defer { session.finishTasksAndInvalidate() }
let service = AuthServerCaptchaService()
try await service.beginSession(using: session)
let solution = try await service.solveAndVerify(using: session)
// 当前 session 已经通过本次滑块校验；后续登录提交继续使用它。
```

若已在同一会话获取登录表单，直接调用 `solveAndVerify`，避免重新初始化登录页改变已有流程状态。

`SliderCaptcha` 保留 `bigImage`、`smallImage`、`tagWidth`、`yHeight`。图片格式和尺寸不固定；小图末尾的 16 字节是本次挑战的加密材料，必须保留原始 Base64，不能用重编码后的 PNG 替换。不要记录或持久化它、登录表单令牌、Cookie、密码或加密后的提交内容。

`SliderCaptchaSolver` 使用透明遮罩内的灰度归一化相关性寻找位置，允许目标区域亮度改变；匹配分数过低或存在相近的竞争位置就返回 `noReliableMatch`。它把原图像素位移转换成组件坐标，无须 OCR 或训练模型。`AuthServerCaptchaService` 按官网格式构造程序化移动采样，并使用 AES-CBC/PKCS7 加密校验内容；只有服务器 `errorCode == 1` 才返回成功。

定位现在使用 Accelerate 批量计算灰度和相关性，预先计算采样索引，并复用同尺寸的拼图解码结果。本机 Debug 编译下，14 张实际挑战图片的定位结果与原实现一致，解码与定位耗时中位数由约 73 毫秒降至 5.3 毫秒。这是该批样本的本地耗时，不包含取图、运动等待和服务端校验，也不代表其他设备上的耗时。

匹配分数不是服务端通过概率。部分服务端拒绝的样本在独立轮廓检查中也得到了相同位置，但服务端未返回具体拒绝原因；缩短运动等待、调整运动采样及编码格式的试验尚未形成稳定的通过率改善，因此保留原校验时序，不降低匹配阈值。

默认最多尝试 3 张新图片，允许范围为 1–5 次。网络错误、响应格式错误和取消会直接传出；不要针对同一挑战反复猜测坐标。

## 验证范围

本次已经在实际匿名会话中完成服务端滑块校验；这不等于已完成真实账号登录，也不是所有图片都能识别的保证。新账号密码入口需要使用者在本机实际运行验证。测试覆盖亮度变化后的定位、尺寸换算、非法图片、加密协议、服务端拒绝、表单令牌和表单来源检查。

协议依据：学校当前公开的 `ids-sliderCaptcha.js`、`longbow.slidercaptcha.js`、`encrypt.js` 和账号登录表单。服务器规则变化时需要重新核对。
