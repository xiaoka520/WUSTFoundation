# 本科生考试安排查询

更新：2026-11-05。模型、查询表单、双表解析、日期时间转换、网络服务、登录客户端及 Demo 已写入。按当前要求未编译、未运行测试，Swift 请求与解析尚未验收。

## 网页入口与当前证据

入口为“考试报名 → 考试安排查询”，业务页面：

| 用途 | 方法 | 地址 |
| --- | --- | --- |
| 查询表单 | GET | `https://bkjx.wust.edu.cn/jsxsd/xsks/xsksap_query` |
| 提交查询并取得列表 | POST | `https://bkjx.wust.edu.cn/jsxsd/xsks/xsksap_list` |

表单根据网页的 `queryKsap()` 设置提交地址。非空学期类别还会将对应选项的名称写入隐藏字段 `xqlbmc`。包按此规则构造表单，保留其他隐藏字段，不执行网页 JavaScript。

已从 Safari 保存查询表单和直接 GET 的双表空列表，原文及源地址、时间、UTF-8 编码与 SHA-256 位于被 Git 忽略的 `TestData/exams/captured`。直接 GET 列表地址没有查询条件，其空结果不能证明指定学期没有考试。

最初查看已登录主页面时，界面显示过 1 条统一安排考试和空的自主申请列表；该有数据结果尚未保存为原始 HTML，随后浏览器控制工具出现窗口捕获错误，未能重新核对。本版的数据行字段依据可见表头和界面，仍需真实有数据响应及 Swift 运行审核，不能标为已验收。

页面包含两张都叫 `dataList` 的表格：统一安排表包含“考试场次”，自主申请表不包含该列。本版使用属性选择器取得全部同名表格，再根据表头区分来源，不使用只能取首项的 `getElementById`。

本版只查询安排，不实现考试报名、撤销、申请、考试须知确认、下载准考证或自动创建提醒。

## App 调用流程

复用 [登录接入](Login.md) 中已登录的账号客户端，先取服务器选项：

```swift
let options = try await client.fetchExamQueryOptions()
```

`ExamQueryOptions` 包含学期 `terms`、学期类别 `categories` 及页面显式标记的 `selectedTermID`、`selectedCategoryID`。没有明确 selected 标记时为 nil，不从日期或数组首项推断当前学期。每项为 `ExamOption(id:name:)`，ID 用于请求，name 用于显示。

以下为简化演示值，不是完整采集内容：

```swift
ExamQueryOptions(
    terms: [
        ExamOption(id: "2026-2027-2", name: "2026-2027-2"),
        ExamOption(id: "2026-2027-1", name: "2026-2027-1")
    ],
    categories: [
        ExamOption(id: "", name: "---请选择---"),
        ExamOption(id: "1", name: "期初"),
        ExamOption(id: "2", name: "期中"),
        ExamOption(id: "3", name: "期末")
    ],
    selectedTermID: "2026-2027-1",
    selectedCategoryID: nil
)
```

由 App 让用户选择，再提交：

```swift
let query = ExamQuery(termID: selectedTermID, categoryID: selectedCategoryID)
let schedule = try await client.fetchExamSchedule(query: query)
```

学期必填，必须来自 `terms`。`categoryID` 为 nil 或空字符串时提交网页的空类别；它不被包定义为“全部类别”，具体结果由服务器决定。若查询期末，使用服务器选项中对应的 ID，当前页面为 `"3"`，不要在 App 中以日期猜测类别。

每次正式查询重新读取表单，再 POST。服务器当前不提供的学期或类别会抛 `invalidQuery`。隐藏字段如 `sxxnxq`、`dqxnxq`、`ckbz` 保持页面值，不伪造考试须知确认状态。

客户端延续已有教务会话，必要时使用已有 TGT 恢复；明确认证失效最多恢复并重试一次。网络错误、页面结构变化和 HTTP 500 不视为凭据失效。需要交互登录时，按已有 `WUSTLoginResult` 流程处理，查询不会自动发送短信。

## 返回内容

`ExamSchedule` 包含 `query` 和 `lists`，每个 `ExamArrangementList` 包含 `source`、`columns` 和 `arrangements`。正常情况下始终返回统一安排、自主申请两组；空组仍然保留。

来源枚举为 `.centralized` 和 `.selfRequested`。`schedule.arrangements` 是按列表顺序拼接的便捷计算属性，不合并重复课程、不排序、不丢失来源。`query` 记录本次提交条件，不是服务器独立确认的筛选回显。

每条 `ExamArrangement` 含来源、按网页列顺序排列的 `[ExamField]` 及可选 `timeRange`。字段值为纯文本，不返回 HTML、CSS 或点击脚本。可用便捷属性如下：

| 属性 | 网页字段 |
| --- | --- |
| `termID` | 学年学期 |
| `courseID` | 课程编号 |
| `courseName` | 课程名称 |
| `examSession` | 考试场次，自主申请表通常没有此列 |
| `weekText` | 周次 |
| `weekdayText` | 星期 |
| `sectionText` | 节次，例如 `"0708"`，保留前导零 |
| `timeText` | 时间原文 |
| `seatNumber` | 座位号 |
| `location` | 场地 |
| `campus` | 校区 |

列不存在时可选属性为 nil，列存在但内容空白时为 `""`。空座位号、空场地或空时间不被猜测为取消、待定或不参加。序号及未来新增的列仍在 `fields` 中保留，可用 `value(for:)` 按表头读取。

下面是虚构的单条返回对象示例，不是账号实际安排：

```swift
ExamArrangement(
    source: .centralized,
    fields: [
        ExamField(name: "学年学期", value: "2026-2027-1"),
        ExamField(name: "课程编号", value: "DEMO001"),
        ExamField(name: "课程名称", value: "示例课程"),
        ExamField(name: "考试场次", value: "示例考试"),
        ExamField(name: "周次", value: "20"),
        ExamField(name: "星期", value: "1"),
        ExamField(name: "节次", value: "0304"),
        ExamField(name: "时间", value: "2027-01-11 10:00~11:40"),
        ExamField(name: "座位号", value: ""),
        ExamField(name: "场地", value: "示例楼101"),
        ExamField(name: "校区", value: "示例校区")
    ],
    timeRange: ExamTimeRange(start: exampleStart, end: exampleEnd)
)
```

其中 `exampleStart`、`exampleEnd` 表示示例北京时间对应的 Date，实际使用时由解析器生成。将 JSONEncoder 的 `dateEncodingStrategy` 设为 `.iso8601` 后，该时间范围编码为：

```json
{
  "start": "2027-01-11T02:00:00Z",
  "end": "2027-01-11T03:40:00Z"
}
```

JSON 的 Z 表示 UTC，和北京时间 10:00～11:40 是同一时刻；App 显示时使用 `Asia/Shanghai`。便捷计算属性不额外编码，默认 JSONEncoder 的 Date 策略也不是上述 ISO 格式，需由 App 明确设置。

## 日期时间与提醒边界

目前识别 `yyyy-MM-dd HH:mm~HH:mm` 及全角 `～` 分隔符。校验真实日期、小时、分钟，并按照 `Asia/Shanghai` 的公历时间生成 `ExamTimeRange(start:end:)`。结束时间必须晚于同一天的开始时间。

未安排时间、未知格式、非法日期或可能跨午夜但缺少明确结束日期时，`timeRange` 为 nil，时间原文仍保留，不丢弃整条考试。未来日期正常保留。不使用教学周和节次反推时间，不套用课表作息，也不根据文字猜测日期。

App 可以用明确的 `timeRange` 生成展示或提醒，但应自行管理授权、提前量、变更更新及旧提醒撤销；包不请求通知权限，不写入系统日历。考试安排可能调整，App 应刷新后更新展示与提醒。

## 空结果、错误与限制

两张表各自出现与列数匹配的“未查询到数据”行时，对应 `arrangements` 返回空数组。若两组都空，`schedule.arrangements` 也为空；这仅表示本次查询的服务器结果。

缺表、缺必要表头、重复来源、列数量不匹配、没有明确空结果标记的空表或不支持的合并单元格会抛错，不伪装成没有考试。数据行至少要求非空学期、课程编号和名称；学期与请求不一致时抛 `selectionNotReflected`。类别筛选无法仅凭行内容独立确认，仍需真实请求审核。

目前没有可验证的分页样本。检测到下一页、尾页、末页链接或多页数量提示时抛 `unsupportedPagination`，不静默返回明显不完整的数据；其他分页结构尚未验证。考试场次的详情弹窗不在本版范围。

低层入口为 `ExamService.fetchQueryOptions(cookie:using:)`、`fetchExamSchedule(query:cookie:using:)`，调用方自行管理同一账号的会话。离线 HTML 可调用 `ExamParser().parse(from:query:)`。真实安排、座位号、Cookie 和原始页面不要写入公开日志或上传仓库。

## Demo

登录或恢复后选择 **10 查询考试安排**。学期回车使用页面明确选中的学期；类别可输入 `?` 查看选项，选择期末等所需类别。查询后先显示两组条数，主动输入 1 才打印考试详情，并显示是否得到可用起止时间。

运行审核时应对照网页的两组条数、时间、节次原文、空座位号、场地及校区。当前仅完成代码写入和页面结构调查，没有运行 Swift 请求、编译或测试。
