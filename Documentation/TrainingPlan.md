# 本科生培养方案

更新：2026-11-05。模型、解析器、请求服务、登录客户端和 Demo 已写入，未编译、未运行测试，也未通过 Swift 请求进行实际验收。

## 入口与范围

页面位置为“培养管理 → 培养方案 → 培养方案及完成情况”，当前实际正文地址为 `https://bkjx.wust.edu.cn/jsxsd/pyfa/topyfamx`，使用 GET。

本版实现的是该页面的说明正文、培养目标实现矩阵及课程设置总表。菜单中的“执行计划”“辅修执行计划”“辅修培养方案明细”是独立功能，本版没有实现。请求不需要选择课表学期，也不从当前日期推算年级或培养方案。

2026-11-05 从已登录的 Safari 页面保存了 UTF-8 原始 HTML，保存在被 Git 忽略的 `TestData/training-plan/captured`，并记录源地址、保存方式、文件时间和 SHA-256。解析规则依据此页面的 `#dataList`、直接子级 `caption` 和内部 `table#mxh`，其他院系或年级的页面结构尚未验证。

## App 调用

复用 [登录接入](Login.md) 中已经建立的账号客户端：

```swift
let plan = try await client.fetchTrainingPlan()
```

客户端先确认教务会话，必要时使用已有 TGT 恢复。业务请求明确遇到认证失效时最多恢复并重试一次。解析错误、HTTP 500 和网络异常不视为凭据过期。需要重新登录或二次验证时，App 按已有的 `WUSTLoginResult` 流程处理；该接口不弹界面、不自动发送短信。

独立管理会话的调用方可使用低层入口：

```swift
let plan = try await TrainingPlanService().fetchTrainingPlan(
    cookie: cookie,
    using: session
)
```

调用方负责提供属于同一账号的 Cookie 和 URLSession。离线 HTML 可交给 `TrainingPlanParser().parse(from: html)`。不要将 Cookie、正文中的个人完成情况或原始 HTML 写入公开日志。

## 返回内容

主要返回值是 `TrainingPlan`，所有文档模型均为 `Codable`、`Hashable`、`Sendable`：

| 模型 | 字段 | 含义 |
| --- | --- | --- |
| `TrainingPlan` | `title`, `blocks` | 页面标题、按原顺序排列的正文块 |
| `TrainingPlanBlock` | `.paragraph(text:)` 或 `.table(value:)` | 纯文本段落或结构化表格 |
| `TrainingPlanTable` | `caption`, `rowCount`, `columnCount`, `cells` | 表格标题、尺寸、实际单元格 |
| `TrainingPlanCell` | `row`, `column`, `rowSpan`, `columnSpan`, `isHeader`, `blocks` | 单元格起点、合并范围、表头标记及内容 |

坐标从 0 开始，跨度包含起点本身。合并区域只返回一个实际单元格，不为被覆盖位置重复生成数据。空单元格保留，内容为 `blocks: []`。`isHeader` 对应网页的 `th`；网页以 `td` 写出的标题文字不会被猜测为表头。单元格内部同样可包含文本和表格。

`#dataList` 是页面的外层排版表格，本身不作为内容表格返回；其中的矩阵和课程设置表作为正文块保留。多级表头、课程体系跨行、小计、合计均保留。课程名称、编号、学分、学时、开设学期及完成情况目前都是单元格里的原始文本，没有转换成单独的课程业务模型。空白的完成情况不推断为“未完成”，学时分类也不自行换算为学分。

以下是虚构的返回对象示例，并非采集结果：

```swift
TrainingPlan(
    title: "示例专业培养方案",
    blocks: [
        .paragraph(text: "一、培养目标"),
        .paragraph(text: "这里是专业培养目标说明。"),
        .table(value: TrainingPlanTable(
            caption: "课程示例",
            rowCount: 3,
            columnCount: 2,
            cells: [
                TrainingPlanCell(row: 0, column: 0, columnSpan: 2,
                    isHeader: true, blocks: [.paragraph(text: "专业课程")]),
                TrainingPlanCell(row: 1, column: 0,
                    isHeader: true, blocks: [.paragraph(text: "课程名称")]),
                TrainingPlanCell(row: 1, column: 1,
                    isHeader: true, blocks: [.paragraph(text: "学分")]),
                TrainingPlanCell(row: 2, column: 0,
                    blocks: [.paragraph(text: "示例课程")]),
                TrainingPlanCell(row: 2, column: 1,
                    blocks: [.paragraph(text: "2.5")])
            ]
        ))
    ]
)
```

单元格编码后的 JSON 形状例如：

```json
{
  "row": 0,
  "column": 0,
  "rowSpan": 1,
  "columnSpan": 2,
  "isHeader": true,
  "blocks": [{ "paragraph": { "text": "专业课程" } }]
}
```

表格块编码形状是 `{ "table": { "value": { ...表格字段... } } }`。`text` 是计算属性，不会额外出现在 JSON 中。

## 显示与深色模式

App 按 `blocks` 顺序渲染。段落使用系统文字颜色；表格按坐标及跨度布局，保留多级表头，宽表可横向滚动。包不返回网页 CSS、背景色、字体或可执行脚本，因此 App 可以自行适配深色模式和动态字体。

Markdown 的常见管道表格无法完整表达 `rowspan`、`colspan` 和多级表头，所以本版不以 Markdown 作为主要返回格式。若 App 需要分享 Markdown，可在展示层展开合并单元格后导出，并明确这是扁平化后的格式。

不需要表格布局时可读取 `plan.text`、`table.text` 或 `cell.text`。全文是有损的纯文本便捷表示：表格以换行和制表符分隔，合并单元格只在起点输出文字；它不替代结构化数据。查询任意坐标使用：

```swift
if let cell = table.cell(atRow: 2, column: 0) {
    print(cell.text)
}
```

坐标落在合并区域内时返回拥有该区域的起点单元格；越界或原本不存在的格位返回 nil。

## 错误与当前边界

`TrainingPlanError.authenticationRequired` 表示明确的认证失效。`planNotFound` 表示没有找到支持的正文与课程表；不将空页面当作空培养方案。缺失标题为 `titleNotFound`；必要课程表头缺失、合并区域重叠或越界为 `invalidTableStructure`。

解析限制每张表最多 4096 行、256 列、262144 个占用格位，内容表格嵌套不超过 16 层。超出大小范围抛 `contentTooLarge`，不截断返回。图片仅保留非空的替代文字，本版不下载图片、不做 OCR。服务器错误、非预期跳转及非 UTF-8 响应分别抛出对应错误。

## Demo 审核

运行 WUSTDemo，完成登录或恢复后选择 **8 查看培养方案**。先确认标题和表格概况，然后可选择 1 查看全文，或 2 查看每张表的尺寸、实际单元格数量和合并数量，并按序号读取表格文本。

控制台的制表符输出仅用于核对文字。实际 App 的合并单元格布局由 App 实现。审核时重点对照网页中的矩阵、课程设置多级表头、跨行课程体系、小计和合计；代码写入不代表这些场景已经通过运行验收。
