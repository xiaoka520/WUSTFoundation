# 学分完成情况查询

网页入口为“学籍成绩 → 学籍管理 → 学分完成情况”。登录后读取 `/jsxsd/xxwcqk/xxwcqk_idxOnzh.do` 即可：两个页签的数据都在同一个 GET 响应里，“毕业学分完成情况”在页面初始状态下只是隐藏。

```swift
let progress = try await client.fetchCreditProgress()
for category in progress.courseCategories {
    print(category.name, category.remainingCredits as Any)
}
```

沿用 [登录接入](Login.md) 中的账号客户端。App 已自行管理教务会话时，可使用 `CreditProgressService().fetchCreditProgress(cookie:using:)`。明确的认证失效由账号客户端最多恢复并重试一次。

| 返回属性 | 对应内容 |
| --- | --- |
| `courseCategories` | 学分类别进度，按课程性质与属性保留每一行 |
| `generalElectives` | 通识选修学分进度，按通识类别保留每一行 |
| `pastSemesterStatistics` | 学期数、已修、未选、不及格及必修未获学分等历史统计 |
| `courses` | 培养方案课程修读明细，含学期、课程编号、名称、学分、性质、属性及原始状态文字 |

学分使用 `Decimal`，门数使用 `Int`。网页空白字段为 `nil`，明确的零仍为零。两项学分均已知时，`remainingCredits` 为 `max(0, requiredCredits - earnedCredits)`。通识选修分类可能和课程类别有交叉，App 展示时应分别使用两组数据。这里的差额不等于学校最终毕业审核结果。

以下为虚构的分类条目 JSON 示例，`remainingCredits` 是计算属性，不重复编码：

```json
{
  "name": "示例课程类别",
  "courseAttribute": "必修",
  "requiredCredits": 5.5,
  "earnedCredits": 2
}
```

缺表、表头或行结构不符、数字格式异常会抛出 `CreditProgressError`，不会把这些异常当作零学分。修读状态由教务系统提供，例如“正在修读”，包不从状态文字推算已获得学分。

Demo 登录后选择 **11 查看学分完成情况**，先显示两组学分和过往学期统计，输入 1 可查看修读明细。已用 2026-11-06 的真实页面和原始 HTML 核对入口及四张表的结构；样本仅保存在 Git 忽略的 `TestData/credits/captured`，Swift 端尚待运行验收。
