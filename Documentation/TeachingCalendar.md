# 教学周与日期接入

更新：2026-11-05。状态：用户已运行通过本包的 `20261105` 教学周校准，并确认 `20261109` 换周重新校准通过。正常接口链路已验收；边界回归已写入但尚未编译或运行，详见 [第一版验收记录](TimetableAcceptance.md)。

## 数据来源

使用教务系统首页课表片段接口：

```http
POST https://bkjx.wust.edu.cn/jsxsd/framework/main_index_loadkb.jsp
Content-Type: application/x-www-form-urlencoded; charset=UTF-8

rq=2026-11-05
```

返回 HTML 片段。报告给出的关键脚本摘录是：

```javascript
$("#li_showWeek").html("...第10周</span>/22周");
```

解析器只读取 `li_showWeek` 元素或针对该元素的 jQuery html 赋值字符串，再从标签文本提取当前周和总周数；不执行返回的 JavaScript，也不从课程正文或通知文章推断日期。

根据服务器报告的“查询日期处于第 N 周”，以周一为一周起点，计算第一周周一，再计算其他周的日期范围。第一周日期、当前周和总周数均不在代码中固定。

该接口的已知参数只有日期 `rq`。当前公开方法不接受学期 ID，不宣称可以直接查询任意指定学期。调用方不要将一次校准结果直接套给另一个学期。

## 1. 通过已有登录客户端校准

复用已经登录的 `WUSTLoginClient`：

```swift
let calendar = try await client.fetchTeachingCalendar()
```

未传日期时，以 `Asia/Shanghai` 时区的今天请求服务器。也可以明确指定日期：

```swift
let date = try AcademicDate(yyyyMMdd: "20261105")
let calendar = try await client.fetchTeachingCalendar(on: date)
```

传给 App 的日期字符串用 `yyyyMMdd`；请求工厂将其转换成接口要求的 `yyyy-MM-dd`。非法日期（例如 20260230）会抛 `TimetableError.invalidDate`，不会自动滚到下个月。

查询复用 client 的 Cookie 和 URLSession。明确的 `authenticationRequired` 最多触发一次已有凭据恢复和重试；缺少周次标签、未知 HTML、网络错误等不会被当作 TGT 失效。

## 2. 返回值示例

返回类型是 `TeachingCalendar`，支持 Codable、Hashable、Sendable。以下数值最初来自外部实测报告，之后已由用户运行本包的 Demo 核对。

当 `20261105` 得到第 10 周、共 22 周时，JSONEncoder 编码后的内容形状为：

```json
{
  "referenceDate": "20261105",
  "referenceWeek": 10,
  "totalWeeks": 22,
  "firstMonday": "20260831",
  "lastSunday": "20270131"
}
```

| 属性 | 类型 | 含义 |
|---|---|---|
| `referenceDate` | `AcademicDate` | 本次实际提交给服务器的查询日期 |
| `referenceWeek` | `Int` | 服务端标签返回的该日期教学周编号 |
| `totalWeeks` | `Int` | 服务端标签返回的总周数 |
| `firstMonday` | `AcademicDate` | 根据本次锚点计算的第一周周一 |
| `lastSunday` | `AcademicDate` | 最后一周周日，范围包含该日 |

`firstMonday`、`lastSunday` 是根据日期和周次计算的，不是服务器直接返回的日期字段。模型从 JSON 恢复时，也会使用 `referenceDate`、`referenceWeek`、`totalWeeks` 重新校验并计算这两个边界。

`AcademicDate` 是不带时分秒的日期值，公开 `year`、`month`、`day` 和 `yyyyMMdd`。JSON 中编码为一个 `yyyyMMdd` 字符串，而不是 Date 的时间戳或包含三个数字的对象。

## 3. 一次校准后在本地换算

获取某一教学周的完整日期范围：

```swift
let week = try calendar.range(ofWeek: 10)
let monday = week.startDate.yyyyMMdd
let sunday = week.endDate.yyyyMMdd
```

返回类型为 `TeachingWeek`。使用上述锚点，编码后的内容是：

```json
{
  "number": 10,
  "startDate": "20261102",
  "endDate": "20261108"
}
```

日期区间包含起止两天。第 1 周为 `20260831`～`20260906`，第 22 周为 `20270125`～`20270131`。

查询某个日期处于哪周：

```swift
let date = try AcademicDate(yyyyMMdd: "20261105")
let weekNumber = try calendar.week(containing: date)
```

`weekNumber` 的类型是 `Int?`；该示例为 `10`。日期在本次校准范围之外时为 nil，例如 `20270201`。这只表示超出当前模型的范围，不表示该日期在学校所有学期中都没有教学安排。

查询某周某个星期的具体日期：

```swift
let date = try calendar.date(inWeek: 10, on: .thursday)
let value = date.yyyyMMdd
```

该示例的 `value` 为 `"20261105"`。上述范围、周次和星期换算都是纯本地计算，不会再次请求服务器。日期运算使用公历日加减，不以固定秒数跨日。

`AcademicDate(date:)` 将一个 Date 时刻转换为上海当地日期；`adding(days:)`、`weekday()` 和 `yyyyMMdd` 操作则处理该日期值本身。

## 4. 学期外和异常返回

用户提供的报告说明，学期外日期的响应没有周次标签。但目前没有完整的学期外原始片段，尚不能以“标签不存在”单独区分学期外、登录页和页面结构变化。

因此当前处理方式是：

| 情况 | 返回或错误 |
|---|---|
| 从已校准模型本地查询范围外日期 | `week(containing:)` 返回 nil |
| 请求服务器后没有可读取的周次标签 | 抛 `teachingWeekNotFound`，不返回第 0 周或伪造空校历 |
| 当前周小于 1、总周数小于当前周、发现冲突标签 | 抛 `invalidTeachingWeek` |
| 请求模型中不存在的周次，例如上述第 23 周 | `range(ofWeek:)` 抛 `invalidTeachingWeek` |
| 日期字符串格式或实际年月日无效 | 抛 `invalidDate` |
| HTTP、重定向、编码和认证问题 | 沿用 TimetableError 中对应错误 |

取得学期外响应的完整原始结构后，再决定是否增加明确的非教学期状态。不会将任意无标签页面一律显示为正常的学期外结果。

## 5. 缓存与更新由 App 决定

App 可以通过 JSONEncoder 缓存 `TeachingCalendar`，之后用同一个模型换算周次和日期范围。模型不包含 Cookie、TGT、学生身份或课程字段。

包不内置持久化、后台定时校准或固定缓存时长。日期超出已校准范围、学校更新周历或用户主动刷新时，由 App 再调用 `fetchTeachingCalendar(on:)`。服务端仍无法提供周次时，保留明确的不可用状态，不自动推测新学期开学日。

## 6. 周次日期和调休是不同的数据

本功能只处理“某日期属于哪一教学周”和“某教学周覆盖哪些自然日期”。它不提供调休后的实际课程替换关系。

例如某个周日补上另一周周二的课，当天的自然日期、自然星期和所在教学周不变，但实际课程安排应使用另外的来源。当前不把补课信息、节假日和老师临时调课从周次锚点推算出来。

整学期 `Timetable` 继续只保存课程周次和星期，不自动附带校历，以免把当前日期接口的校准结果错误绑定到任意历史或未来学期。App 需要确认两份数据属于同一学期后再组合。

## 7. 低层接口与 Demo

自行管理认证的调用方可使用：

```swift
let calendar = try await TeachingCalendarService().fetchTeachingCalendar(
    on: try AcademicDate(yyyyMMdd: "20261105"),
    cookie: cookie,
    using: session
)
```

低层服务不新建会话、不申请票据、不自动恢复登录；调用方传入同一认证会话。

Demo 登录后选择菜单 6，输入校准日期或直接回车使用今天。成功后会显示服务端周次、总周数、整个日期范围及当前周起止日期。随后可选择查看指定周范围、查询指定日期的周次，或重新请求校准。

依据报告，输入 `20261105` 的预期显示为：

```text
服务器校准成功：20261105，第 10 周 / 共 22 周。
本次日期范围：20260831～20270131。
第 10 周：20261102（周一）～20261108（周日）。
```

上述校准结果已与用户提供的本包运行日志一致。用户另确认 `20261109` 重新校准返回第 11 周、总周数仍为 22、整个范围不变。其他本地边界已补回归用例，但助手未编译或运行这些用例，不将其记为通过。
