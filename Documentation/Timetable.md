# 本科生课表接入

更新：2026-11-05。课表模型、解析、请求服务、登录客户端入口和 Demo 查询代码已接入。用户已运行通过当前学期 19 条安排的读取，以及第 1 周按星期筛选；查询下一学期仍出现表单错误，尚待定位。自动化回归和其余边界尚未完成。

本文的学期、课程、教师和地点示例均为虚构演示数据，不是用户的实际课表。接口返回 Swift 对象；下方初始化表达式用于说明返回值内容，并不要求 App 自己构造这些结果。课表网页原始响应仍是 HTML，JSON 示例仅表示 App 对 Codable 模型进行编码后的形状。

## 1. 复用账号的登录客户端

沿用 [登录接入](Login.md) 中保存的 `WUSTLoginClient`，先处理登录、短信和 aTrust 的状态分支。查询课表不需要 App 重新传密码、验证码或 Cookie：

```swift
let terms = try await client.fetchAcademicTerms()
```

此方法检查当前教务会话，必要时使用已有 TGT 恢复，然后读取课表入口提供的学期选项。登录状态无法满足业务访问时抛 `WUSTLoginClientError.notAuthenticated`；App 再调用 `ensureSession()`，根据 `WUSTLoginResult` 展示所需交互，不自动发送短信。

一个账号保留一个 client。不要为每次刷新新建实例；切换账号前先退出旧 client。client 的 URLSession 不公开给 App。

## 2. 让用户选择服务器提供的学期

`AcademicTermList.terms` 保存服务器提供的 ID 和名称，`selectedTermID` 仅表示页面显式标记的选中项。没有明确选中项时为 nil，App 应让用户选择，不自行以数组首项代替当前学期。

```swift
let selectedTerm = terms.terms.first { $0.id == terms.selectedTermID }
```

App 将 `terms.terms` 作为选项展示，保存用户选择的 `AcademicTerm`。ID 作为服务器标识使用，不根据当前日期构造。服务器可能列出很多往年学期，选项数量不代表当前账号在所有这些学期都有课程。

`fetchAcademicTerms()` 和低层 `fetchAcademicTerms(cookie:using:)` 都返回 `AcademicTermList`，内容例如：

```swift
let exampleTerms = AcademicTermList(
    terms: [
        AcademicTerm(id: "2026-2027-2", name: "2026-2027-2"),
        AcademicTerm(id: "2026-2027-1", name: "2026-2027-1")
    ],
    selectedTermID: "2026-2027-1"
)
```

这个结果有 2 个可选学期，页面选中的是 `2026-2027-1`。每个选项中 `id` 用于请求，`name` 用于展示；它们可以相同，不是重复的两个 ID。App 在二者相同时显示一份即可。

页面未显式选中学期时，对应返回值为：

```swift
AcademicTermList(terms: exampleTerms.terms, selectedTermID: nil)
```

这表示选项仍然可用，但当前学期无法从显式选中标记确认；不是空学期列表。

## 3. 获取整学期课表

```swift
let timetable = try await client.fetchTimetable(term: chosenTerm)
```

请求流程为：读取入口 → 从 Form1 取得提交地址和字段 → 确认学期仍可选 → POST 指定学期并将周次设为空 → 检查学期、周次、模板回显 → 解析课程。

模板 ID、隐藏字段和同名字段来自实际表单；App 不必填写模板 ID。请求保留页面当前选中的节次模式。若服务器没有接受查询条件，抛 `selectionNotReflected`，不将其他学期的数据标记为请求的学期。

周次和节次的解析上限默认分别为 30、12；它们是当前实现的可配置校验范围，不是自然日期或每日作息。需要采用不同范围时：

```swift
let timetable = try await client.fetchTimetable(
    term: chosenTerm,
    maxWeek: configuredMaxWeek,
    maxSection: configuredMaxSection
)
```

参数必须为正数。上限应来自已确认的校历或节次规则；包不会从学期 ID 推算开学日期。

高层 `fetchTimetable(...)` 和低层 `fetchTimetable(term:cookie:using:)` 都返回 `Timetable`。完整返回内容例如：

```swift
let exampleTimetable = Timetable(
    term: AcademicTerm(id: "2026-2027-1", name: "2026-2027-1"),
    meetings: [
        CourseMeeting(
            name: "示例数学",
            weekday: .monday,
            weeks: [1, 2, 4],
            sections: [1, 2],
            courseID: nil,
            teacher: "示例教师甲",
            teachingClass: "示例教学班 A",
            location: "示例楼 A101"
        ),
        CourseMeeting(
            name: "示例数学",
            weekday: .monday,
            weeks: [3],
            sections: [1, 2],
            courseID: nil,
            teacher: nil,
            teachingClass: nil,
            location: "示例楼 B202"
        )
    ]
)
```

这是同一门课的两条安排：第 1、2、4 周在 A101，第 3 周在 B202。教师和教学班缺失时为 nil，不会凭另一条记录补齐。

若 App 将上述示例通过 `JSONEncoder` 编码，内容形状为：

```json
{
  "term": {
    "id": "2026-2027-1",
    "name": "2026-2027-1"
  },
  "meetings": [
    {
      "name": "示例数学",
      "weekday": 1,
      "weeks": [1, 2, 4],
      "sections": [1, 2],
      "teacher": "示例教师甲",
      "teachingClass": "示例教学班 A",
      "location": "示例楼 A101"
    },
    {
      "name": "示例数学",
      "weekday": 1,
      "weeks": [3],
      "sections": [1, 2],
      "location": "示例楼 B202"
    }
  ]
}
```

`Weekday` 编码为 1～7，分别对应周一到周日；当前自动合成的 Codable 会省略值为 nil 的可选字段，JSON 键顺序不固定。例如这里不包含 `courseID`，第二条也不包含 `teacher`、`teachingClass`。

需要生成 JSON 时由 App 显式编码：

```swift
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let data = try encoder.encode(exampleTimetable)
```

## 4. 理解与筛选结果

一条 `CourseMeeting` 表示同一课程在同一星期、一组周次、一组节次和同一地点下的安排。课程每周在周一和周三各上一次，会有两条安排；分段周次采用不同地点时也分别保留。`meetings.count` 是安排数量，不一定是不同课程的数量。

结果包括课程名、可选课程 ID、教师、教学班、地点、星期、周次和节次。当前页面未明确提供课程 ID，因此保留 nil。教师、教学班和地点缺失时为 nil；课程名和时间缺失则报错。

```swift
let weekMeetings = timetable.meetings(inWeek: 8)
let mondayMeetings = timetable.meetings(inWeek: 8, on: .monday)
```

筛选在本地结构化数据上完成，无需再次联网。非连续周次和节次保持原有空档。同名但地点或时间不同的安排会保留，只对所有字段完全一致的安排去重。

以上面的 `exampleTimetable` 为例，筛选方法返回 `[CourseMeeting]`，不会返回整个 `Timetable`：

| 调用 | 返回内容 |
|---|---|
| `exampleTimetable.meetings(inWeek: 2)` | 一条安排：示例数学，周一，第 1、2 节，示例楼 A101 |
| `exampleTimetable.meetings(inWeek: 3, on: .monday)` | 一条安排：示例数学，周一，第 1、2 节，示例楼 B202 |
| `exampleTimetable.meetings(inWeek: 2, on: .sunday)` | `[]` |
| `exampleTimetable.meetings(inWeek: 5)` | `[]` |

筛选保留原记录全部字段。比如第 2 周选中的第一条记录，其 `weeks` 仍是 `[1, 2, 4]`，不会被改成 `[2]`。这些方法只做包含关系筛选，不校验参数；未匹配的周次（包括 0 或负数）返回空数组。

当前时间语法支持如 `1-17(周)[03-04节]`、`1-2,4-7(周)[01-02节]`。尚未确认的单双周和单块多组时间格式会明确报错，不静默忽略课程。

有效空课表返回空 `meetings`。找不到表格、星期标题不匹配、非空块缺少必要字段等情况返回错误，不当作无课。

已识别的整学期空课表返回值例如：

```swift
Timetable(
    term: AcademicTerm(id: "2026-2027-1", name: "2026-2027-1"),
    meetings: []
)
```

它与“完整课表有课程、某次筛选返回 `[]`”含义不同。目前用户查询下一学期得到的是 `unsupportedForm` 错误，不能用这个空课表示例代替实际响应，也不能据此认定下一学期没有课程。

`Timetable`、`AcademicTerm` 和 `CourseMeeting` 支持 Codable、Hashable、Sendable。App 负责本地缓存、课表 UI、颜色、提醒以及日历导出。手机与 Watch 的数据传输也由 App 负责；当前实现未验证 Watch 的独立取数。

教学周与自然日期的服务器校准已新增独立入口 `fetchTeachingCalendar(on:)`，可取得 `yyyyMMdd` 格式的周一至周日范围，见 [教学周与日期接入](TeachingCalendar.md)。用户已运行通过日期校准和服务器换周重新校准；边界回归尚未运行。当前日期接口没有学期 ID，`Timetable` 不会自动绑定它的结果；调休后的实际课程关系也不包含在普通周次换算中。

## 5. 恢复与错误处理

课表查询共用 client 的认证执行方法，请求完成后会检查账号会话是否已被重置。请求过程中若发生退出或重新登录，旧请求结果不会被当作新会话数据返回。

低层 Service 将 HTTP 401 或最终跳转至已知统一认证/aTrust 域名识别为 `TimetableError.authenticationRequired`。高层 client 对这一错误最多恢复一次 aTrust 和教务会话，再重试整个只读查询；并发失败会优先使用已经完成的会话恢复。恢复期间出现 TGT 失效或额外验证要求时，不自动继续密码或短信登录。

同地址返回的未知 HTML、其他重定向、网络错误、其他 HTTP 错误、解码错误、结构变化和时间格式错误不触发这一恢复重试。不能仅凭出现 script 标签或没有课表就断定凭据失效。

| 错误 | 含义与 App 动作 |
|---|---|
| `WUSTLoginClientError.notAuthenticated` | 重新取得登录状态，展示对应的登录或验证交互 |
| `URLError` | 网络问题；保留 TGT，由用户发起下一次查询 |
| `invalidTerm` | 学期已不在最新选项中，重新加载选项 |
| `selectionNotReflected` | 服务器未按提交条件返回，不展示为目标学期课表 |
| `unexpectedRedirect` | 非预期跳转，保留为请求异常 |
| `formNotFound`、`unsupportedForm` | 表单结构或协议与当前实现不符 |
| `tableNotFound`、`invalidTableStructure` | 无法确认预期课表结构，不显示为空课表 |
| `invalidTimeFormat`、`invalidNumberList` | 时间格式或范围不受当前解析器支持 |
| `missingCourseName`、`missingCourseTime` | 非空课程块缺少必需信息 |
| `teachingWeekNotFound`、`invalidTeachingWeek`、`invalidDate` | 教学周日期查询的标签、周次或日期异常，详见教学周文档 |

失败通过 `throws` 传递，不返回 `Timetable(error: ...)`、`success: false` 或伪装成空数组。比如 `selectionNotReflected` 是抛出的错误，调用方不会同时收到一份课表。低层错误也可能是 SwiftSoup 的解析错误；上表不是所有底层异常的封闭清单。

不要记录完整错误 URL、请求正文、原始页面、Cookie 或票据。App 根据错误类别和安全的状态码显示提示即可。

## 6. 自行管理会话的低层入口

已有自定义认证流程的调用方可复用同一 URLSession 和教务 Cookie：

```swift
let service = TimetableService()
let terms = try await service.fetchAcademicTerms(cookie: cookie, using: session)
let timetable = try await service.fetchTimetable(
    term: chosenTerm,
    cookie: cookie,
    using: session
)
```

低层服务不新建会话、不换票、不登录，也不销毁调用方的 session。调用方负责认证、账号隔离、会话恢复和退出期间的结果处理。跨设备凭据是否可用仍需按学校策略实测。

## 7. Demo 审核入口

运行 WUSTDemo，完成或恢复登录后选择菜单 5：

1. 回车查询页面选中学期，或输入学期 ID；输入 `?` 查看全部服务器选项。
2. 出现“课表解析完成”后，检查学期和安排条数。
3. 输入 1 查看课程名称、星期、周次、节次、地点。
4. 输入 2 按教学周和星期筛选；星期留空查看整周。
5. 返回主菜单后可再选 5 查询其他学期。
6. 主菜单选择 1，在新 client 中恢复；之后再选 5 检查恢复后的课表查询。

菜单 4 继续用于原始响应采集，数据保存在被 Git 忽略的本地 TestData 中。菜单 5 不自动保存课表或原始 HTML，也不会自动输出教师、教学班和账号字段。

菜单 6 提供教学周日期校准和本地日期换算，与课程查询菜单分开；操作及返回示例见 [教学周文档](TeachingCalendar.md)。

用户已运行新版 Demo：恢复登录和学生信息读取成功；当前学期解析得到 19 条安排；第 1 周周一返回空数组、周日返回 1 条安排；程序正常退出。该日志证明当前学期的读取和上述筛选路径已运行，不代表每条课程都已逐项人工核对，也不代表其他学期、自动恢复重试、iPhone 或 Watch 已验证。下一学期查询的表单错误仍待解决，自动化回归尚未运行。

教学周日期也已完成正常流程验收；课程解析、请求和日期边界的三组回归用例已写入但尚未运行。已通过项与保留边界见 [第一版验收记录](TimetableAcceptance.md)。
