# 第二课堂成绩单

## App 调用

```swift
let transcript = try await client.fetchSecondClassTranscript()
```

该 client 需要已有的学工系统会话。旧 TGT 换票分支和 `fetchTranscript(credential:using:)` 已移除；新版教务登录暂不能自动建立学工会话。App 已有认证后的学工 URLSession 时，使用 `SecondClassService.fetchTranscript(using:)`。会话失效抛 `SecondClassError.authenticationRequired`，由 App 提供对应站点的登录交互。

## 返回内容

`SecondClassTranscript` 提供分类学分、素质发展总学分和服务器评价。字段均为结构化值，App 可自行绘制进度条。

| 字段 | 含义 |
| --- | --- |
| `categories` | 有学分要求的分类 |
| `earnedCredits` | 服务器返回的素质发展总学分 |
| `evaluation` | 服务器给出的评价文本 |

每个分类提供 `id`、`name`、`requiredCredits`、`earnedCredits` 和 `requirements`。每项 requirement 提供 `kind`（required 或 elective）、`requiredCredits`、`earnedCredits`、`remainingCredits` 和 `isCompleted`。

所有学分使用 Decimal。requirements 会过滤要求学分等于 0 的项目，整个分类都没有学分要求时也会过滤。0/2 会保留，0/0 会过滤。选修已获学分采用网页显示的 xxyxxfR 字段。

以下为虚构的返回示例。

```json
{
  "categories": [
    {
      "id": "example",
      "name": "文化艺术与身心发展",
      "requiredCredits": 2,
      "earnedCredits": 0,
      "requirements": [
        {"kind": "elective", "requiredCredits": 2, "earnedCredits": 0}
      ]
    }
  ],
  "earnedCredits": 0,
  "evaluation": "不及格"
}
```

示例为返回模型经 JSONEncoder 编码后的字段。remainingCredits 和 isCompleted 是计算属性，App 读取 Swift 对象时可直接使用。

## 数据来源与验证

查询入口为 https://xg.wust.edu.cn/xsfw/sys/dektapp/*default/index.do#/cjdcx。

先以空请求体 POST 访问应用初始化接口，取得当前应用的 _WEU Cookie。
`/xsfw/sys/swpubapp/indexmenu/getAppConfig.do?appId=5446046383738452&appName=dektapp`

随后使用同一个 URLSession，以空请求体 POST 查询学分。

- `/xsfw/sys/dektapp/modules/cjdcxManage/getCj.do` 返回分类要求和已获学分。
- `/xsfw/sys/dektapp/modules/cjdcxManage/getSzfzpj.do` 返回总学分和评价。

当前接口覆盖上述学分汇总。活动明细、勋章、雷达图及学生基本资料需要各自的接口。

接口与字段已在登录的 Safari 页面核对。应用初始化顺序、数值解码和零要求过滤有离线回归测试，包内真实账号换票与读取仍需运行 Demo 验证。

## Demo

运行 WUSTDemo，登录或恢复后选择菜单 14。控制台输出总学分、评价和各分类的要求、已获学分。认证或网络错误通过 throws 传递，Demo 仅输出安全的状态和业务码。
