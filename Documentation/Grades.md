# 本科生课程成绩查询

更新：2026-11-05。模型、表单解析、成绩解析、网络请求、登录客户端入口和 Demo 已写入。按当前要求未编译、未运行测试。

## 实际入口与验证范围

网页路径为“学籍成绩 → 我的成绩 → 课程成绩查询”。主页面 `https://bkjx.wust.edu.cn/jsxsd/framework/xsMain.jsp` 包含多层 iframe，业务请求直接访问对应子页面：

| 用途 | 方法 | 路径 |
| --- | --- | --- |
| 外层成绩页面 | GET | `/jsxsd/kscj/cjcx_frm` |
| 查询选项与表单 | GET | `/jsxsd/kscj/cjcx_query` |
| 提交查询 | POST | `/jsxsd/kscj/cjcx_list` |

已在已登录的 Safari 中查看查询选项，并点击“查询”确认全部学期的响应。当前账号无可见成绩，页面明确显示“未查询到数据”。保存了表单页和直接 GET 列表页的空结果源码，均为 UTF-8，位于被 Git 忽略的 `TestData/grades/captured`，附带源地址、采集方式、时间和 SHA-256。

因此，目前确认了真实表单、提交脚本、表头和空结果结构；有成绩的行、成绩详情链接、补重记录及有数据时的分页尚未实测。代码写入不表示实际成绩解析已经验收。

本版是课程成绩查询，不包含“等级考试成绩”、成绩认定、免修申请、成绩档案打印或成绩证明下载。

## App 接入步骤

沿用 [登录接入](Login.md) 中已完成登录的账号客户端，一个账号保留一个 client：

```swift
let options = try await client.fetchGradeQueryOptions()
```

返回的 `GradeQueryOptions` 包含 `terms`、`courseNatures`、`displayModes`，每个选项都是 `GradeOption(id:name:)`。ID 用于请求，name 用于显示。空 ID 是服务器提供的“不限制”选项，不是无效数据。学期列表可能包含大量历史学期，不能据此认定账号在这些学期都有成绩。

以下为虚构的返回值示例：

```swift
GradeQueryOptions(
    terms: [
        GradeOption(id: "", name: "全部学期"),
        GradeOption(id: "2026-2027-1", name: "2026-2027-1")
    ],
    courseNatures: [
        GradeOption(id: "", name: "---请选择---"),
        GradeOption(id: "00", name: "公共基础课")
    ],
    displayModes: [
        GradeOption(id: "all", name: "显示全部成绩"),
        GradeOption(id: "max", name: "显示最好成绩")
    ]
)
```

取得选项后，由 App 展示筛选条件，再查询：

```swift
let report = try await client.fetchGrades(query: GradeQuery(
    termID: selectedTermID,
    courseNatureID: nil,
    courseName: "",
    displayMode: .all,
    includesRetakes: false
))
```

`selectedTermID` 是 App 从 `options.terms` 选择并保存的 ID。nil 或空字符串表示不限制。查询所有学期、所有课程性质、不限制名称，可直接使用：

```swift
let report = try await client.fetchGrades()
```

每次正式查询都会重新读取表单，保留成功表单控件中的其他字段，再覆盖指定筛选条件。学期、课程性质和显示方式必须仍是服务器允许的选项。表单空 action 由网页的 `queryKscj()` 设置为成绩列表地址；实现只核对该已知提交赋值，不执行页面 JavaScript。

客户端沿用已有教务会话；明确认证失效时最多恢复并重试一次。其他网络错误、服务器错误、页面变化不会被视为凭据失效。若抛 `WUSTLoginClientError.notAuthenticated`，App 再调用 `ensureSession()` 并按登录状态处理，查询接口不会自动发送短信。

## 查询条件与服务器字段

| Swift 条件 | 服务器字段 | 含义 |
| --- | --- | --- |
| `termID` | `kksj` | 开课学期；nil/空字符串不限制 |
| `courseNatureID` | `kcxz` | 课程性质 ID；nil/空字符串不限制 |
| `courseName` | `kcmc` | 课程名称关键词；空字符串不限制 |
| `.all` / `.best` | `xsfs=all` / `xsfs=max` | 全部成绩／最好成绩，由服务器筛选 |
| `includesRetakes` | 勾选时 `sfxsbcxq=1` | 对应网页“是否显示补重成绩”；false 时不提交此复选框 |

默认值与网页的全部学期、全部成绩、未勾选补重一致。false 不代表包会在客户端删除补考记录，true 也不代表包会补齐服务器未返回的记录。服务器如何选取“最好成绩”、如何合并补重成绩，由教务系统决定，包不自行比较或覆盖。

## 返回字段及示例

`GradeReport` 包含：

- `query`：本次提交的查询条件。
- `columns`：网页表头顺序，表头内部空白会规范化。
- `records`：成绩记录，保持网页顺序，不按课程编号去重。

每条 `GradeRecord.fields` 按列顺序保存全部 `GradeField(name:value:)`，包括未知的新增列和序号。字段值是去掉两端空白的纯文本，页面 HTML、CSS、点击事件和 JavaScript 不返回。App 可据此自行适配深色模式。

常用列提供便捷计算属性：

| 属性 | 网页列 |
| --- | --- |
| `termID` | 开课学期 |
| `courseID` | 课程编号 |
| `courseName` | 课程名称 |
| `score` | 成绩 |
| `groupName` | 分组名 |
| `scoreFlag` | 成绩标识 |
| `credits` | 学分 |
| `totalHours` | 总学时 |
| `gradePoint` | 绩点 |
| `retakeTermID` | 补重学期 |
| `assessmentMethod` | 考核方式 |
| `examType` | 考试性质 |
| `courseNature` | 课程性质 |
| `generalElectiveCategory` | 通选课类别 |

成绩、学分、绩点等全部保留原文字符串。`score` 可以是 `"88"`、`"优秀"`、`"缺考"` 或空白，包不把非数字成绩变成 0，不自行判定通过、计算加权平均分或 GPA。其他非必需列缺失时便捷属性为 nil，列存在但空白时为 `""`；两者不同。

以下 JSON 是虚构的返回示例，不是账号实际成绩：

```json
{
  "query": {
    "termID": "2026-2027-1",
    "courseName": "",
    "displayMode": "all",
    "includesRetakes": false
  },
  "columns": ["开课学期", "课程编号", "课程名称", "成绩", "学分", "绩点"],
  "records": [
    {
      "fields": [
        {"name": "开课学期", "value": "2026-2027-1"},
        {"name": "课程编号", "value": "DEMO001"},
        {"name": "课程名称", "value": "示例课程"},
        {"name": "成绩", "value": "优秀"},
        {"name": "学分", "value": "2.5"},
        {"name": "绩点", "value": ""}
      ]
    }
  ]
}
```

计算属性不会额外重复编码到 JSON。读取成绩可使用：

```swift
for record in report.records {
    let name = record.courseName
    let scoreText = record.score
    let creditText = record.credits
}
```

明确的“未查询到数据”返回 `records: []`，仍保留当前表头和请求条件。没有成绩表格、只有表头但没有明确空结果标记、列数量不匹配等情况会抛错，不冒充空列表。

## 校验与边界

按表头名称映射字段；至少要求“开课学期、课程编号、课程名称、成绩”。有数据的行必须具备非空的学期、课程编号和课程名称，普通成绩行不接受跨行或跨列。其他结构变化抛 `invalidTableStructure`，不会错位继续返回。指定单个学期时，若记录的开课学期不同，抛 `selectionNotReflected`。

`query` 记录提交条件，不是服务器独立回显的保证。当前空结果页面无法证明学期、课程性质、名称和显示方式的筛选语义，后续需要用有成绩的账号核对。名称模糊匹配、课程性质与最好成绩筛选不在本地重复实现。

当前空结果页未提供分页控件，因此本版未实现自动翻页。解析器检测到“下一页／尾页／末页”链接或多页页数提示时抛 `unsupportedPagination`，避免把明显的单页响应当作完整结果；其他分页结构尚未验证。

低层服务为 `GradeService.fetchQueryOptions(cookie:using:)` 与 `fetchGrades(query:cookie:using:)`，会话由调用方管理。离线解析可调用 `GradeParser().parse(from: html, query: query)`。原始成绩及 Cookie 不应写入公开日志、上传 Git 或作为公开测试样本。

## Demo

登录或恢复后选择 **9 查询课程成绩**，按提示输入学期、课程性质、课程名、显示方式及补重开关。学期和课程性质输入 `?` 查看选项；回车不限制。查询后只有主动输入 1 才打印成绩详情。

当前账号应先核对是否能得到明确的空结果提示。后续拿到真实成绩数据后，再审核数字与等级成绩、补重记录及完整列映射；无需为了这次代码写入另加编译或测试。
