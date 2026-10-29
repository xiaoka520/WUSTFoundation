# 测试数据采集记录

采集日期：2026-10-24（Asia/Shanghai）。本次已通过 Safari 已登录的本科教务系统保存完整学籍卡片页面源码；此前门户片段另行保留。

**已采集真实的 `table#xjkpTable`。** 完整原始文件位于 [学籍卡片.html](../../webPageData/学籍卡片.html)，来源为 `https://bkjx.wust.edu.cn/jsxsd/grxx/xsxx`。文件与 Safari 保存的页面源码逐字节一致（22,425 字节），没有脱敏、替换字段、截取表格或拼接内容，包含真实个人信息。文件哈希与来源见 `manifest.json` 的第一条记录。此前门户入口出现的安全连接错误是历史采集情况，本次已能正常访问。

## 已采集的真实片段

| 文件 | 来源 | 保留内容与处理 |
| --- | --- | --- |
| `captured/portal-student-info.html` | `https://portal.wust.edu.cn/#/index46` | `.userInfo_JSGRXX` DOM；姓名、学号替换为测试值；移除照片和链接地址，重新排版并添加离线 HTML 外壳。 |
| `captured/portal-grades-placeholder.html` | `https://portal.wust.edu.cn/#/index73` | 两张表格的完整 outerHTML，添加离线 HTML 外壳；两张表格均通过长度和内容校验核对，未改变字段、空格、类名和结构。 |
| `captured/portal-source-shell.html` | Safari 保存上述成绩页的“页面源码” | 从保存文件提取空的 `div#root`，添加离线 HTML 外壳；证明原始源码尚无渲染后的业务数据。 |

上述旧门户片段使用 UTF-8；文件名描述的是采集状态，不代表后端一定没有数据。旧片段未保存 Cookie、令牌、身份证号、照片或真实姓名学号。本次新增的完整学籍卡片原始源码包含页面上的真实字段值，未作替换。

## 从当前页面确认的注意事项

- 门户使用 `.userInfo_JSGRXX .infoTop p` 展示学号等信息，不是教务系统学籍卡，不能与 `#xjkpTable` 的格式混用。
- 门户的“学院”当前显示“武汉科技大学”，不能据此认定是院系名称；门户没有提供专业、班级、出生日期、性别、民族、籍贯、身份证号。
- “上次登录”和“上次登录IP”当前为空，不能补成虚构值。
- 成绩表实际有七列：学年、学期、课程名称、学分、综合成绩、考试性质、补重学期；固定列另生成一张仅含“学年”的表，遍历全部表格会重复。
- 成绩表当前出现一行全部为 `0` 的值。仅确认页面显示此内容，无法判断后台是无成绩、同步异常还是占位。不可当作七个有效成绩字段，也不可无条件丢弃任意真实的零分记录。
- 表头含制表符，单元格含前后空格；读取时需要规范化空白。
- 普通“保存源码”不含动态填充后的表格；测试静态 HTML 解析时应明确输入来自服务器响应还是渲染后的 DOM。

## 人工边界样本

这些文件只依据当前 `StudentInfoParser` 的选择器构造，**不证明真实学籍卡布局**。

| 文件 | 场景 | 当前解析器预期行为 |
| --- | --- | --- |
| `synthetic/student-id-normal.html` | 第三行第五个 td，正常标签与测试学号 | 返回 `209900000001` |
| `synthetic/student-id-whitespace.html` | 嵌套 span、换行、不换行空格 | 返回 `209900000001` |
| `synthetic/student-id-empty.html` | 有单元格，无学号值 | `studentIDNotFound` |
| `synthetic/student-id-cell-missing.html` | 缺目标单元格 | `studentIDNotFound` |
| `synthetic/student-id-label-mismatch.html` | 同一坐标改为姓名字段 | 已知问题：当前错误返回 `姓名：测试学生`；期望拒绝 |

三份 `captured/` 样本对当前学籍卡解析器都应为 `tableNotFound`，不可从门户页或无数据框架中误读学号。机器可读的来源和预期行为见 `manifest.json`。本次只添加数据，没有修改生产解析器或包配置。

## 本次真实学籍卡核对结果

- 直达 `/jsxsd/grxx/xsxx` 后，学籍卡片位于主文档，无需从首页 iframe 中提取。
- 完整 `table#xjkpTable` 有 54 行；第三行有五个 `td`，第五个为“学号：”加真实学号，合并单元格不改变 `td` 的顺序。
- Safari 保存的源码没有显式 `tbody`；SwiftSoup 2.14.3 解析时会补入，现有选择器已实测匹配。
- 在临时执行程序中原样编译项目当前的 `StudentInfoParser.swift`，用完整原始 HTML 调用 `parseStudentID(from:)`，结果与 Safari 实际显示的学号一致。未修改项目解析器、包配置或测试代码。
- 出生日期在源码中为八位 `yyyyMMdd`；籍贯单元格真实为空，不补值。
- 本次原始页面没有改写个人字段。`synthetic/` 与此前脱敏的门户片段仍仅代表各自已注明的测试场景。
