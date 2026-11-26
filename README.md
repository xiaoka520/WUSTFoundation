# WUSTFoundation

面向武汉科技大学 Apple 平台应用的 Swift Package，提供学校新版登录、教务只读查询、通知正文与 PDF，以及胖乖洗衣机查询。

**[开发与接入手册](Documentation/Manual.md)** 是统一文档入口，包含完整架构图、模块职责、函数调用示例、返回模型、错误处理和源码函数索引。

- [项目架构](Documentation/Manual.md#architecture)
- [登录和会话](Documentation/Manual.md#login)
- [课表与教学周日期](Documentation/Manual.md#timetable)
- [成绩](Documentation/Manual.md#grades)、[考试](Documentation/Manual.md#exams)、[学分](Documentation/Manual.md#credits)、[培养方案](Documentation/Manual.md#training)
- [通知与原版 PDF](Documentation/Manual.md#notices)
- [图书馆](Documentation/Manual.md#library)、[第二课堂与校车](Documentation/Manual.md#other-services)
- [胖乖登录与洗衣机倒计时](Documentation/Manual.md#laundry)
- [完整公开 API](Documentation/Manual.md#public-api)、[内部函数地图](Documentation/Manual.md#internals)

Swift tools 6.4；平台声明为 iOS 15+、macOS 15+、visionOS 1+，尚未支持 watchOS。

```sh
swift run WUSTDemo
swift run WUSTLaundryDemo
```

学校登录使用 `/authserver`，旧登录及 TGT/aTrust 自动换票已移除。新版续期、跨启动恢复和图书馆／门户／学工跨系统自动登录尚待接入；算术图片识别器独立保留。各功能的调用前提和验证范围见手册。

[许可证](LICENSE)
