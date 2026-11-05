# 学校通知接入

更新：2026-11-05。五个通知源的列表、分页、详情、HTML 纯文本转换、原始 PDF 资源及 Demo 系统快速预览已写入；按用户要求未编译或测试，不代表五个来源已由本包运行验收。当前范围是通知栏目，普通新闻频道后续单独接入。

## 1. 通知来源

| NoticeSource | 来源 | 实际通知列表 |
|---|---|---|
| `.campus` | 校园通知 | https://www.wust.edu.cn/index/tzgg.htm |
| `.academicAffairs` | 教务通知 | https://jwc.wust.edu.cn/tzgg.htm |
| `.studentAffairs` | 学工通知 | https://xgc.wust.edu.cn/tzgg.htm |
| `.research` | 科研通知 | https://kjc.wust.edu.cn/tzgg.htm |
| `.graduateSchool` | 研究生院通知 | https://ysxy.wust.edu.cn/tzgg.htm |

用户提供的四个部门首页包含多个栏目，库使用其中“通知公告”的更多链接对应列表，不把首页新闻、工作动态和其他栏目混入通知流。学工、科研入口优先使用 HTTPS。

公开通知不依赖 WUSTLoginClient，不要求先完成教务登录。校园通知列表中部分文章会跳转统一身份认证；此时详情请求抛 `NoticeError.authenticationRequired`，不自动提交账号密码。App 可交由原文入口处理认证，或自行提供已有授权的 URLSession。

## 2. 读取第一页与后续页面

调用方管理 URLSession：

```swift
let session = URLSession(configuration: .ephemeral)
let service = NoticeService()
let page = try await service.fetchPage(source: .academicAffairs, using: session)
```

返回 `NoticePage`，下面是虚构数据的 JSON 形状，不是从真实通知拼接出的样本：

```json
{
  "source": "academicAffairs",
  "url": "https://jwc.wust.edu.cn/tzgg.htm",
  "items": [
    {
      "source": "academicAffairs",
      "title": "示例通知：下学期事项安排",
      "url": "https://jwc.wust.edu.cn/info/1371/00000.htm",
      "publishedDate": "2027-01-10"
    }
  ],
  "currentPage": 1,
  "totalPages": 10,
  "nextPageURL": "https://jwc.wust.edu.cn/tzgg/9.htm",
  "filteredItemCount": 1
}
```

日期字符串统一为 `yyyy-MM-dd`。示例中的未来日期正常保留。值为 nil 的可选属性由当前自动合成的 Codable 省略；例如第一页没有 previousPageURL。

| 属性 | 含义 |
|---|---|
| `source` | 这条通知来自哪个通知流；校园汇总中的链接可能指向其他学校部门 |
| `url` | 本页地址或通知的原文地址 |
| `items` | 去除重复 URL 并经过日期过滤的通知，保持页面顺序，保留置顶顺序 |
| `currentPage`、`totalPages` | 从分页组件读取，无法确认时为 nil |
| `previousPageURL`、`nextPageURL` | 服务器实际给出的分页链接，无对应链接时为 nil |
| `filteredItemCount` | 本页因无效、缺失或被规则排除的发布日期而未返回的条目数 |

使用服务器返回的链接翻页：

```swift
if let nextURL = page.nextPageURL {
    let nextPage = try await service.fetchPage(
        source: page.source,
        at: nextURL,
        using: session
    )
}
```

CMS 的分页文件编号与展示页码可能相反，不自行拼 `第 N 页.htm`。本页全部被过滤时，`items` 可以为空；是否结束仍以 nextPageURL 为准。库不无限翻页补齐某个条数，也不将未知页面当成正常空列表。

## 3. 日期规则

当前默认配置严格遵循用户要求：

```swift
let policy = NoticeDatePolicy(excludedDates: ["1980-01-01"])
let service = NoticeService(datePolicy: policy)
```

- 只按完整日期排除 `1980-01-01`，包括页面中同一日期的 `1980年1月1日` 等等价写法。
- `1980-01-02`、其他真实旧日期和未来日期均保留，不排除整个 1980 年，也不默认设置“不能晚于今天”。
- 日期缺失、格式无法解析、实际不存在（例如 2026-02-30）时不返回该条通知，不猜测成今天。
- 列表和详情都检查日期；详情有独立发布日期时以详情为准，被排除则抛 `filteredPublicationDate`。详情没有独立日期字段时沿用该列表项已知的发布日期。
- 标题里提到的事件年份不是发布日期，不能用标题年份决定保留与否。

只有 App 显式希望缩小时间范围时，才设置可选的 earliestDate、latestDate，例如：

```swift
let policy = NoticeDatePolicy(
    excludedDates: ["1980-01-01"],
    earliestDate: "2010-01-01",
    latestDate: nil
)
```

这不是默认行为。若 App 希望取消特殊日期过滤，可显式传 `excludedDates: []`。配置中的日期要求严格的 `yyyy-MM-dd`，错误配置抛 `invalidDatePolicy`。

核对的五个通知栏尾页，最早可见日期分别为[校园 2015-11-30](https://www.wust.edu.cn/index/tzgg/1.htm)、[教务 2018-01-03](https://jwc.wust.edu.cn/tzgg/1.htm)、[学工 2015-05-22](https://xgc.wust.edu.cn/tzgg/1.htm)、[科研 2017-05-09](https://kjc.wust.edu.cn/tzgg/1.htm)、[研究生院 2017-05-15](https://ysxy.wust.edu.cn/tzgg/1.htm)。它们只是当前栏目可见的存档范围，不代表网站完整历史，代码不把这些日期当作过滤下限。

## 4. 读取详情：优先纯文本

```swift
let item = page.items[0]
let detail = try await service.fetchDetail(item, using: session)
```

App 实际使用时先确认 items 非空。服务端详情中的完整标题会覆盖列表中的截断标题。

返回 `NoticeDetail`，字段示例如下，全部是虚构内容：

```json
{
  "summary": {
    "source": "academicAffairs",
    "title": "示例通知：下学期事项安排",
    "url": "https://jwc.wust.edu.cn/info/1371/00000.htm",
    "publishedDate": "2027-01-10"
  },
  "text": "各位同学：\n\n这是第一段示例正文。\n\n这是第二段示例正文。",
  "paragraphs": ["各位同学：", "这是第一段示例正文。", "这是第二段示例正文。"],
  "images": [
    {"url": "https://jwc.wust.edu.cn/__local/example.png", "alt": "示例图片说明"}
  ],
  "attachments": [
    {"title": "示例附件.docx", "url": "https://jwc.wust.edu.cn/files/example.docx"}
  ],
  "links": [],
  "documents": []
}
```

`text` 是纯文本，`paragraphs` 是供 App 分段排版的字符串数组。HTML 样式、文字颜色、背景色、脚本和站点导航不会作为正文返回。表格行转换成文本行，单元格以制表符分隔；复杂表格结构不会保留。

App 用原生 Text 或其他文本组件即可适配深色模式，无需继承站点固定的黑字白底样式。库不返回供 App 直接渲染的正文 HTML。

图片保留独立 URL 和可选 alt；正文链接保留标题和 URL；附件保留名称和下载地址。图片本身的颜色、扫描页的白色背景不会因为文本接口自动变成深色，如何预览由 App 决定。

`hasText` 是计算属性，表示 HTML 正文转换后的 text 非空，不参与 JSON 编码。PDF 正文保留为完整原始文档，不合并进 text；仅有内嵌 PDF 的文章可能 hasText 为 false，但 documents 非空，是正常返回。

## 5. 原始 PDF 整体返回

实际通知页可能只有 `showVsbpdfIframe(...)`，没有 HTML 文字正文。HTML 解析器从加载脚本、iframe、embed 或 object 中取得原始 PDF 地址，并将整份文档作为一个资源返回；不执行网页脚本，也不把 PDF 拆成多张预览图。PDF 使用原版快速预览，不做文字层提取或 OCR。

有 PDF 的详情会包含如下 documents 数组，示例地址为虚构：

```json
{
  "text": "",
  "paragraphs": [],
  "documents": [
    {
      "url": "https://jwc.wust.edu.cn/__local/example.pdf",
      "sourceURL": "https://jwc.wust.edu.cn/info/1371/00000.htm"
    }
  ]
}
```

这个片段只展示详情中与 PDF 有关的字段。`url` 是原始 PDF 地址，`sourceURL` 是它所在的通知页面。PDF 同时作为“正文 PDF”列入 attachments，便于已有附件列表 UI 使用。

`fetchDetail` 不自动下载二进制文件。App 可以直接使用 PDF URL 显示完整文档；需要自己保存或交给 PDF 阅读组件时，显式取得整份原始 Data：

```swift
if let document = detail.documents.first {
    let data = try await service.fetchPDF(document, using: session)
}
```

`fetchPDF` 会携带通知页面作为 Referer，检查 HTTP 响应及 PDF 文件标识，返回未经拆页、转码或文字提取的原始 Data。需要认证时抛 authenticationRequired；服务端返回 HTML 等非 PDF 内容时抛 invalidDocument。

默认允许返回不超过 20 MiB 的原始 PDF，可通过 `NoticeService(maximumPDFBytes:)` 调整。大小在响应读入后检查，不是流式下载限额；超过上限时抛 documentTooLarge，不裁切文件。普通 Word、Excel 或压缩包附件仍只返回链接。

### 原版快速预览由 App 展示

App 下载整份 PDF 后，将原始 Data 保存为本地 PDF 文件，再交给系统 Quick Look。PDF 的分页、字体、表格和图片保持原版，不先拆页或转换成纯文本。库不提供网页 PDF 组件，也不返回界面对象。

```swift
let data = try await service.fetchPDF(document, using: session)
let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let fileURL = directory.appendingPathComponent("notice.pdf")
try data.write(to: fileURL, options: .atomic)
```

随后由 App 将 fileURL 交给预览界面：

- iOS/iPadOS/visionOS：[QLPreviewController](https://developer.apple.com/documentation/quicklook/qlpreviewcontroller) 与它的数据源提供本地预览项。
- 原生 macOS：[QLPreviewPanel](https://developer.apple.com/documentation/quicklookui/qlpreviewpanel)。
- App 也可以自行封装这些系统预览界面供 SwiftUI 使用。

App 应保持文件在预览期间有效，并持有需要的数据源对象；预览关闭后自行清理临时文件。包只负责获取原始文件，不保存 App 缓存、不控制界面生命周期。

PDF 自身的页面背景和颜色保留原版，不保证随深色模式重排。普通 HTML 正文仍是纯文本，由 App 的原生文本组件适配主题。

macOS 命令行 Demo 的通知详情菜单 3 会下载原始 PDF，写入独立临时目录，然后通过系统 qlmanage -p 发起 Quick Look。预览进程退出后清理该临时目录；异常结束时清理为尽力处理。这个进程调用仅用于 Demo，iOS App 不调用 qlmanage。

## 6. 错误与会话边界

列表/HTML 详情的 HTTP、TLS、解码和页面结构错误会抛出，不会冒充空页面。详情被过滤时抛 `filteredPublicationDate`，日期缺失或无效时抛 `missingPublicationDate`。

常见 NoticeError 包括 authenticationRequired、unexpectedStatusCode、listNotFound、bodyNotFound、unsupportedURL。URLError 保留为网络错误；显式下载 PDF 失败时抛错，不返回部分文件，也不影响此前已经取得的详情对象。

库不再提供 PDF 文字提取入口或对应错误。下载失败会抛错，文件是否能预览由系统阅读器处理；包不会因 PDF 没有文字层而拒绝原文件。

服务不创建登录客户端、不申请票据、不自动下载外站正文。校园汇总中指向其他学校部门的文章仍保留原通知流 source；学校域内受支持的文章链接可以读取，外部链接可由 App 打开原文。

## 7. Demo 与当前验证状态

无需登录运行通知演示：

```sh
swift run WUSTDemo --notices
```

也可以在原有 Demo 登录后的主菜单选择 7。选择五个通知源之一后，输入文章序号查看纯文本，n/p 翻页；详情默认展示前 2000 字符，可选择完整文本、资源链接或输入 3 下载并原版快速预览 PDF。

当前通过网页访问核对了五个来源的通知栏目与尾页，取得了校园、教务、科研部分原始 HTML。研究时本机直接请求学工和研究生院出现 TLS/连接失败；两站网页内容可从网页工具核对，但不能据此宣称本机网络链或本包解析已通过。不会为此关闭证书校验或自动降级连接。

原始公开页面及来源元数据只保存在被 Git 忽略的 TestData/notices/captured/；不依赖该目录发布包。本轮没有运行编译、自动化测试或新版 Demo，实际五源调用、PDF 原文件下载、系统快速预览及页面兼容需后续用户审核。
