# WUSTFoundation

面向 Apple 平台的武汉科技大学基础接口 Swift Package。

目前实现统一认证、短信二次验证、aTrust 环境认证、教务会话恢复与学生信息解析。支持 iOS 15+、macOS 15+、visionOS 1+。

- App 接入与登录状态处理：[登录文档](Documentation/Login.md)
- 交互演示：`swift run WUSTDemo`
- 本地合成协议回归：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`

App 负责界面和凭据存储策略；包负责认证协议、会话复用与恢复。Demo 提供按账号保存 TGT 的 Keychain 适配示例。
