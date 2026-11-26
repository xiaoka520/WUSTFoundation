# 图书馆只读接口接入

登录后的 App 可用 `WUSTLoginClient.fetchLibraryStatistics()` 一次读取五张卡片。图书馆查询复用客户端的 Cookie 容器。数据请求收到登录重定向时，客户端用已有 TGT 换取图书馆会话后重试一次。

| 卡片 | 统计字段 | 明细方法 |
| --- | --- | --- |
| 当前借阅 | `loanCount` | `fetchLibraryCurrentLoans(page:pageSize:)` |
| 即将到期 | `expireCount` | `fetchLibraryOverdueSoon(page:pageSize:)` |
| 滞纳金｜违章 | `fineSum` | `fetchLibraryFines(page:pageSize:)` |
| 我的请求 | `requestCount` | `fetchLibraryRequests(page:pageSize:)` |
| 我的书单 | `booklistCount` | `fetchLibraryBooklists()` |

`fineSum` 以 `Decimal?` 暴露服务端金额。滞纳金明细的条数取 `totalItems`，它对应服务端的 `data.total`。其余四个统计字段用 `Int?`，缺失字段为 `nil`。统计的其他字段仍可从 `statistics.fields` 读取。

```swift
let stats = try await client.fetchLibraryStatistics()
let requests = try await client.fetchLibraryRequests()
let fines = try await client.fetchLibraryFines()
let booklists = try await client.fetchLibraryBooklists()
if let id = booklists.first?.id {
    let books = try await client.fetchLibraryBooklistBooks(id: id)
}
```

`LibraryPage` 保留响应给出的页号、每页条数、总条数与总页数。例如请求每页 5 条但响应给出 10 条时，`pageSize` 为 10。已有的 `fetchLibraryDashboard()` 继续一次返回统计、当前借阅和即将到期分页。

请求、滞纳金和书目条目目前使用 `LibraryRecord`，也就是保留字段名和值的 JSON 对象。采集样本中这几种条目都是空数组。书单对象另外提供模板中出现的 ID、名称、封面、描述、点击数和书目数。

| 方法和路径（相对 `/meta-local/opac`） | 参数 |
| --- | --- |
| GET `/users/stats` | 无 |
| GET `/users/loans`、`/users/overdue_soon` | `page`、`pageSize` |
| GET `/users/fines` | `page`、`pageSize` |
| GET `/users/requests/list` | `requestFlagStatus=all`、`processStatus=0`、`page`、`pageSize` |
| GET `/booklists/tree` | 无 |
| GET `/booklists/{id}/info` | 书单 ID，入口为 `fetchLibraryBooklistInfo(id:)` |
| POST `/booklists/{id}/detls` | 书单 ID 和 JSON 分页参数 `page`、`pageSize`，用于只读书目查询 |

调用方已有图书馆 Cookie 时，也可用 `LibraryService` 的对应方法，传入 Cookie 与 URLSession。业务响应中的非成功码抛 `LibraryError.serviceRejected`。图书馆数据请求的 HTTP 302 按所采集的登录跳转处理。

Demo 登录后选主菜单 **12**，进入五项查询。请求、滞纳金及书目页面显示总条数和条目字段名。本次按用户提供的抓包结果实现。书单详情的成功响应格式仍待非空书单确认。新增代码尚未编译或运行测试。
