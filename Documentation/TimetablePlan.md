# 本科生课表模块实施计划

日期：2026-11-02；2026-11-03 增补 watchOS 后续支持；2026-11-05 接入课表实现。模型、时间与 HTML 解析、表单与请求服务、client 入口和 Demo 菜单已写入。用户已运行通过当前学期 19 条安排的读取和第 1 周按星期筛选；下一学期查询仍有表单错误，自动化回归尚未运行。调用方式、返回对象及 JSON 编码示例见 [课表接入](Timetable.md)。后续规划不代表已经通过验收。

## 1. 第一版交付目标

App 指定学期，包通过已有登录会话获取整学期个人课表，返回结构化课程安排，并能按教学周、星期筛选。Demo 完成真实页面与结果的对应核对。

第一版包含：学期选项与页面当前选择、整学期课表、周次/星期/节次解析、同格多课、完全重复记录去重、按周与星期筛选、接入现有会话恢复。

后续支持 watchOS 的选定只读业务接口。账号密码、验证码和短信认证由 iPhone 等设备完成；Watch 消费手机同步的课表，或在跨设备凭据实测通过后使用导入凭据独立取数。完整能力划分和验收见 [watchOS 规划](WatchOSPlan.md)。当前 Package.swift 尚未启用 watchOS 支持。

课表 UI、配色、提醒、Widget、日历导出、课表本地数据库和刷新策略由 App 负责。教师/教室课表、选退课和首页单周接口不进入本轮。

2026-11-05 根据用户提供的外部接口实测报告，新增服务器周次校准与本地日期换算，见 [教学周与日期接入](TeachingCalendar.md)。数据来自首页 `main_index_loadkb.jsp` 的 `li_showWeek` 标签，不从通知或学期字符串推断开学日期。用户已运行通过正常校准与换周重新校准；三组边界回归已写入但尚未运行。调休和每日作息仍需独立的可靠数据源；状态汇总见 [第一版验收记录](TimetableAcceptance.md)。

## 2. 已确认事实与待核实项

2026-11-05 已取得课表入口 GET、整学期 POST 与指定周次 POST 原始响应，保存在本地被忽略的 TestData/timetable/captured/。入口包含 kbtable、42 个详细课表格子及学期/周次/节次模板选择器。后续批次的整学期和单周响应均为 HTTP 200、有效 UTF-8，提交条件回显一致；整学期有 14 个非空详细格子，单周有 1 个，课表内容摘要不同。已确认该批次周次筛选产生实际变化；其他学期切换和新版完整解析仍待运行验证。

当前样本的学期选择器有 56 项，是服务器提供的查询范围，不等于该账号在每一项中都有课程。周次选择器提供“全部”和第 1～30 周，学期与周次切换均提交 Form1；本地静态 HTML 不具备原站认证会话和服务器筛选环境。学期列表应保留服务器值，App 决定展示范围，不能根据选项数量推断个人就读历史。

原始 HTML 按响应字节保存，不作转码或添加标签。当前样本未在 meta 中声明字符集；以后采集元数据另外记录 HTTP Content-Type、textEncodingName、UTF-8 校验和字节数。旧样本未记录的响应头保持未知，不根据文件编码反推原始响应头。

Demo 的菜单 4 已增加表单 POST 采集：GET 入口后，从实际 Form1 读取学期、周次、模板和成功提交的控件，保留重复名称的隐藏字段。用户选择学期和模板后，先以 zc 为空提交整学期查询，再可选提交指定周次。新响应重新解析表单后才发下一次查询，避免沿用已变化的隐藏字段。

每次采集用同一个随机批次标识保存 entry、semester、week 原始 HTML 及对应 JSON。JSON 记录提交条件、响应表单条件是否一致、编码和摘要，以及详细课表文本摘要是否相对整学期改变；不记录 Cookie 或完整 POST 正文。每份响应保存后立即输出本地路径，即使后续解析或条件校验失败也保留排查依据。

条件回显一致和内容摘要改变是协议检查，不等于课程级解析已验证。课程全集恰好都落在所选周时，内容摘要也可能相同。已有真实 POST 采集和用户运行的当前学期解析结果；其他学期、格式边界、恢复重试等仍需后续集中验收。

参考 mywust 提交 `6d4de0492af9779aab6c1e61a2878b7b12ebace4`：

- 整学期请求使用 POST `/jsxsd/xskb/xskb_list.do`，学期字段为 `xnxq01id`。
- 工厂同时传 `jx0404id`、`cj0701id`、`zc`、`demo`、`sfFD`、`kbjcmsid`。其中模板 ID 被写死，尚不能认定当前学校页面仍使用同值。
- 原库选择 `.kbcontent:not(.sykb2)`，读取课程自身文本，以及 `title` 为课堂名称、老师、周次(节次)、教室的元素。
- 示例时间格式包括 `1-17(周)[03-04节]`、`1-2,4-7(周)[01-02节]`。
- 原库说明可能产生重复记录；它按格子序号推算星期，仅取首个时间元素/匹配，去重未包含教室。这些行为需要结合真实结构改进。

实施前需要确认：当前页面实际 URL/请求方法、完整表单、模板 ID 来源、课表容器和星期标题结构、单双周实际表示、无课学期的页面形式、是否存在多组时间/地点对应关系，以及学期选项是否由同页提供。

Java 源码是协议线索；当前学校页面是最终依据。页面不一致时先修订结构说明，再开始解析。

## 3. 文件与职责

模块目录与后续回归文件规划：

```text
Sources/WUSTFoundation/Timetable/
    Models/
        AcademicTerm.swift
        CourseMeeting.swift
        Timetable.swift
    Parsing/
        TimetableFormParser.swift
        TimetableParser.swift
        TimetableTimeParser.swift
    Networking/
        TimetableRequestFactory.swift
        TimetableService.swift
    TimetableError.swift
Sources/WUSTFoundation/Authentication/Client/
    WUSTLoginClientTimetable.swift
Tests/WUSTFoundationTests/
    TimetableParserTests.swift
    TimetableServiceTests.swift
TestData/timetable/
    synthetic/
    README.md
```

SwiftPM 自动识别源码子目录。TestData 仅保留本地，已通过 .gitignore 排除，不作为必须上传的测试资源。关键自动化回归在测试代码中构造小型合成 HTML，保证其他电脑和 CI 不依赖本地样本；真实页面用于本地人工核对，不在测试中写入个人目录的绝对路径。

样本来自真实账号时保留本地来源记录，原始页面和脱敏副本均不上传。合成样本单独标记，不拿合成页面宣称已完成真实数据验收。

## 4. 数据模型

模型使用值类型，采用 Sendable、Codable、Hashable，使用 let 属性并提供公开初始化方法。

模型、纯解析和业务请求将保持可拆入 Watch 轻量产品的依赖边界；不在这些类型中依赖 Vision、SwiftUI 或 WatchConnectivity。WatchConnectivity 的账号状态、凭据和课表传递由 App 层负责。

### AcademicTerm

- `id: String`：服务器提交用的实际 value，作为不透明标识保存。
- `name: String`：页面展示的学期名称。

不根据日期或展示名称自行生成 id。第一轮先支持明确传入服务器学期 ID；随后从真实页面学期选项中取得可选项与当前选中项。

同文件增加 `AcademicTermList`，包含 `terms: [AcademicTerm]` 和 `selectedTermID: String?`。后者只反映页面实际选中值，无法确认时为 nil。

### CourseMeeting

一条记录表示同一课程在同一星期、同一组节次和地点下的安排。

- `courseID: String?`：只有页面确实提供时才填写。
- `name: String`：必需的课程名。
- `teacher: String?`：缺失时为 nil。
- `teachingClass: String?`：教学班。
- `location: String?`：教室/地点原文，不先拆楼栋和校区。
- `weekday: Weekday`：星期一为 1，星期日为 7。
- `weeks: [Int]`：实际教学周，正数、去重、升序。
- `sections: [Int]`：实际节次，正数、去重、升序。

Weekday 枚举可放在 CourseMeeting.swift；未知星期必须报错，不能默认为星期一。

同课程周一和周三各上一节，输出两条安排。同一课因为周次不同换了教室，也保留两条。周次 `[1,2,4,5,6,7]` 不压成 1～7；不连续节次也不压成连续区间。

### Timetable

- `term: AcademicTerm`。
- `meetings: [CourseMeeting]`：稳定排序后的安排列表。
- `meetings(inWeek:)`：筛选教学周。
- `meetings(inWeek:on:)`：筛选教学周与星期。

去重依据完整安排，包括地点、教师、教学班、星期、周次和节次。只删除完全重复项，不把时间相同的不同课程合并。排序以星期、起始节次、课程名及完整字段作为后续顺序，保证同输入结果稳定。

## 5. 解析流程

TimetableTimeParser 是纯字符串解析器；TimetableParser 是纯 HTML 解析器。两者不联网、不读取 Cookie、不参与登录。

按以下层次实现：

1. 确认响应是有效课表页面，定位详细课表区域，排除页面中精简版/隐藏副本。
2. 按真实表头和行列结构确定星期。空格子也参与定位，不允许先过滤空格子再计算星期。
3. 识别一个格子里的多门课程。优先利用 DOM 边界，确需按分隔符切割时只对已确认的课程区域处理。
4. 分别读取课程名、教师、教学班、地点和时间元素，不能对整个格子直接 text() 后猜测字段边界。
5. 解析所有时间组。各组有独立地点/教师时保持对应关系，不做笛卡尔组合，不取首组后丢弃剩余安排。
6. 解析连续周、分段周、单周和单节/多节。真实样本出现单双周时加入相应语法；暂未出现的格式只用明确标记的合成用例校验，不宣称已经支持学校实际格式。
7. 完整字段去重并稳定排序，组装 Timetable。

第一版解析采用严格模式：非空课程块缺少关键时间或无法识别时，返回带安全位置上下文的解析错误，不静默丢课。教师、教学班、地点允许缺失。

必须区分：

- 已识别的有效空课表：返回空 meetings。
- 登录/aTrust 页面：认证相关错误。
- 没有预期课表结构或未知时间格式：解析错误。

错误中只放字段名、行列位置、格式类型等定位信息，不附带完整 HTML、Cookie 或个人课表正文。

## 6. 请求服务与公开入口

拟定低层接口：

```swift
public func fetchTimetable(
    term: AcademicTerm,
    cookie: String,
    using session: URLSession
) async throws -> Timetable
```

TimetableRequestFactory 负责 URLRequest、POST 表单编码及 Cookie；Service 负责执行请求、检查 HTTP/最终地址、解码和调用解析器。

模板 ID 优先从当前入口页表单中读取；如果学校当前协议确实要求固定模板，集中保存在请求工厂中，并记录验证来源，不散落在模型或 App 中。首版不让 App 手填模板 ID。

学期列表接口从真实页面确认后增加：

```swift
public func fetchAcademicTerms(
    cookie: String,
    using session: URLSession
) async throws -> AcademicTermList
```

返回的 AcademicTermList 同时包含可选项及页面实际选中 ID；不以排序最前一项当成当前学期。App 可从已确认的选中项发起首次查询，选中项不明时由用户选择。

高层入口放独立文件 WUSTLoginClientTimetable.swift：

```swift
public func fetchAcademicTerms() async throws -> AcademicTermList
public func fetchTimetable(term: AcademicTerm) async throws -> Timetable
```

现有 client 的 session、version 都是 private，不能仅把扩展写进另一文件就直接访问。新增包内共用的 `withUndergraduateSession` 认证执行方法，由原 actor 内部取得 Cookie、session 和版本快照，再执行业务请求并检查退出/切换状态；学生信息调用也复用该方法。session 不公开给 App。

流程：ensureSession → 有效教务 Cookie → 同一 session 请求课表 → 检查响应和解析 → 确认请求期间账号会话未被重置 → 返回结果。

业务请求的有界恢复已写入：只针对课表 Service 识别出的 `authenticationRequired` 最多恢复并重试一次；目前识别 HTTP 401 和最终跳转至已知统一认证/aTrust 域名。同地址未知 HTML 与其他重定向仍报错，不凭缺少表格判断过期。网络故障、未知 HTML、解析失败不触发自动密码登录，也不反复换票。低层 Service 只报告错误，高层 client 决定恢复；这一路径尚未运行验证。

## 7. 包与 App 边界

| 事项 | 负责方 |
|---|---|
| 学期与课程数据获取、解析、规范化 | 包 |
| 按教学周/星期筛选 | 包的纯数据方法 |
| Cookie 复用、TGT 恢复 | 现有 client |
| 页面与网格布局、课程颜色、点击详情 | App |
| 教学周日期校准与范围换算 | 包通过日期接口取得服务端锚点；App 负责缓存与刷新时机 |
| 作息表、调休规则的配置与展示 | 需要独立数据源；当前不由普通教学周换算推断 |
| 本地课表缓存、刷新按钮、过期展示 | App |
| 提醒和日历展示 | App，使用已确认的数据与日期规则 |

第一版提供 Codable 数据，方便 App 保存；包不自建数据库、后台轮询或缓存 TTL。

## 8. 实施与学习顺序

| 单元 | 具体工作 | 完成标准 |
|---|---|---|
| 0：页面与协议确认 | 获取当前个人整学期课表与表单结构，记录请求方法、参数、响应类型、学期选项；建立来源记录 | 至少有一份完整有效样本，参数与对应学期明确 |
| 1：数据模型 | AcademicTerm、Weekday、CourseMeeting、Timetable | 能手工表示分段周、多地点和同一天多课；类型与命名明确 |
| 2：时间解析 | TimetableTimeParser | 连续周/分段周/单节可解析，未知格式明确失败 |
| 3：HTML 解析 | 定位表格、星期、课程块与字段，调用时间解析，去重排序 | 本地真实页面输出与网页人工核对一致 |
| 4：请求服务 | RequestFactory、Service、学期选项读取，复用现有 session | 能请求指定学期并返回相同解析结果；不重新输入账号密码 |
| 5：client 与 Demo | 高层入口、受控过期恢复、Demo 学期选择与查询输出 | 登录后查课表、换学期、复用会话、恢复后查询均连通 |
| 6：集中回归 | 单次补齐关键样本/异常测试、构建与接入文档 | 主要解析边界通过；macOS 和 iOS 库构建通过 |

用户继续编写核心模型、时间解析和 HTML 解析，每单元一次说明目标、输入输出、方法位置、变量名和错误分支。助手负责 Demo、请求链诊断与构建修复。不会把一整个文件当作学习结果要求直接复制。

若用户另行要求由助手完成实现，则按相同单元顺序完成，保留可审查的小模块。

## 9. 一次性集中验证范围

解析：普通课程、空格子、周日、同格多课、分段周、单节、同名不同地点、隐藏课表副本、完全重复记录、多组时间、缺少可选字段、缺少关键时间、未知格式、有效空课表和结构缺失。

网络：表单参数与编码、指定学期、HTTP 错误、跳转登录页、编码错误、会话复用、明确过期最多恢复一次、断网不清除 TGT、退出期间不返回旧账号数据。

数据筛选：某周/某天的包含关系、分段周不补齐空档、去重不合并不同课程和不同地点。

不为简单字段或每个私有辅助方法单独安排真实登录测试。真实校园网验收集中为一次：查询完整课表、与网页核对、切换学期，再验证已有会话和恢复路径。

## 10. 本轮结束标准

- App 能取得服务器提供的学期选项，并明确选择一个学期。
- 能通过已有 client 取得对应整学期结构化课表。
- 星期、教学周、节次、地点与页面一致；重复项和同格多课处理正确。
- App 无需为课表再登录一次。
- 有效空课表、认证失效和页面变化可区分。
- 能按周/星期筛选；不伪造自然日期和作息时间。
- Demo 的真实校园网结果与关键本地回归均通过。

watchOS 是上述主线之后的独立阶段：先验证轻量产品编译与手机同步数据，再验证 Watch 导入 TGT 的独立取数；不把当前 Mac 上的新会话恢复成功当成跨设备成功。

## 原库依据

- [请求工厂](https://github.com/xiaoka520/mywust/blob/6d4de0492af9779aab6c1e61a2878b7b12ebace4/mywust-core/src/main/java/cn/wustlinghang/mywust/core/request/factory/undergrade/BkjxRequestFactory.java)
- [接口地址](https://github.com/xiaoka520/mywust/blob/6d4de0492af9779aab6c1e61a2878b7b12ebace4/mywust-common/src/main/java/cn/wustlinghang/mywust/urls/UndergradUrls.java)
- [整学期解析器](https://github.com/xiaoka520/mywust/blob/6d4de0492af9779aab6c1e61a2878b7b12ebace4/mywust-core/src/main/java/cn/wustlinghang/mywust/core/parser/undergraduate/UndergradCourseTableParser.java)
- [课程模型](https://github.com/xiaoka520/mywust/blob/6d4de0492af9779aab6c1e61a2878b7b12ebace4/mywust-common/src/main/java/cn/wustlinghang/mywust/data/common/Course.java)
