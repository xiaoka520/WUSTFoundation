# WUSTFoundation

面向 Apple 平台的武汉科技大学基础接口 Swift Package

各功能的运行验收状态见对应文档，代码接入不代表全部场景已验收
支持 iOS 15+、macOS 15+、visionOS 1+。

- App 接入与登录状态处理：[登录文档](Documentation/Login.md)
- 物联网设备处理 [文档](Documentation/LaundryLogin.md)
- 课表接入与查询流程：[课表接入](Documentation/Timetable.md)
- 教学周与日期范围：[教学周接入](Documentation/TeachingCalendar.md)
- 图书馆只读接入：[图书馆接入](Documentation/Library.md)
- 学校通知、纯文本正文与返回示例：[通知接入](Documentation/Notices.md)
- 培养方案、纯文本与合并表格：[培养方案接入](Documentation/TrainingPlan.md)
- 课程成绩筛选、返回字段与示例：[成绩接入](Documentation/Grades.md)
- 考试安排、分类列表与日期时间：[考试安排接入](Documentation/Exams.md)
- 毕业学分进度、历史统计及修读明细：[学分完成情况接入](Documentation/CreditProgress.md)
- watchOS 后续能力与跨设备凭据方案：[watchOS 规划](Documentation/WatchOSPlan.md)（规划中，尚未声明支持）
- 交互演示：`swift run WUSTDemo`
- 本地合成协议回归：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`

App 负责界面和凭据存储策略；包负责认证协议、会话复用与恢复。Demo 提供按账号保存 TGT 的 Keychain 适配示例。

## TODO
- [x] 登录闭环
- [x] 学生信息解析
- [x] 课表解析
- [x] 学校通知解析（五源列表、正文、原始 PDF 与系统快速预览 Demo 已写入）
- [x] 学校新闻解析
- [ ] 一卡通余额查询
- [ ] 宿舍照明/空调电费查询
- [x] 课程成绩查询（筛选、解析、会话接入与 Demo 已写入；待验证）
- [x] 培养方案解析（说明正文、合并表格、会话接入）
- [x] 学分完成情况（毕业学分进度、历史统计与修读明细）
- [x] 考试安排查询（双表解析、日期时间、会话接入与 Demo 已写入，待验证）
- [ ] 第二学堂
- [ ] 双创学分
- [ ] 研究生支持
- [ ] watchOS核心功能支持
- [ ] 学校日历解析
- [x] 空闲洗衣机获取
- [ ] 洗衣机时间监测
- [ ] 洗衣机解析
- [ ] 饮水机解析
