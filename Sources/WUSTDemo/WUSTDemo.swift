import Foundation
import Darwin
import WUSTFoundation

@main
struct WUSTDemo {
    enum DemoError: Error { case missingInput, deviceIDStorageUnavailable }

    static func main() async {
        do { try await run() }
        catch let error as URLError {
            log("网络请求失败（URLError \(error.code.rawValue)），未将其判定为凭据失效。")
            exit(EXIT_FAILURE)
        } catch is CancellationError {
            log("操作已取消。")
        } catch let error as WUSTLoginClientError {
            log("登录流程未完成：\(error)。")
            exit(EXIT_FAILURE)
        } catch let error as UnionAuthServiceError {
            switch error {
            case .loginFailed(let code):
                let safeCode = code.range(of: #"\A[A-Z0-9_]{1,32}\z"#, options: .regularExpression) != nil ? code : "UNKNOWN"
                log("统一认证失败（业务码 \(safeCode)）。")
            case .smsCodeRejected(let code, _), .smsVerificationRejected(let code, _):
                log("短信操作被服务器拒绝（业务码 \(code)）。")
            case .unexpectedStatusCode(let code), .configurationRejected(let code):
                log("统一认证请求失败（状态码 \(code)）。")
            default:
                log("统一认证未完成，请检查凭据或验证状态。")
            }
            exit(EXIT_FAILURE)
        } catch let error as ATrustAuthServiceError {
            switch error {
            case .rejected(let code): log("aTrust 拒绝认证（业务码 \(code)）。")
            case .unexpectedStatusCode(let code): log("aTrust 请求失败（HTTP \(code)）。")
            case .requestFailed(_, let status, let code):
                log("aTrust 请求失败（HTTP \(status)，业务码 \(code.map(String.init) ?? "未知")）。")
            default: log("aTrust 响应或回调无效。")
            }
            exit(EXIT_FAILURE)
        } catch let error as UndergraduateAuthServiceError {
            log("教务会话处理失败：\(error)。")
            exit(EXIT_FAILURE)
        } catch let error as DemoCredentialStore.StoreError {
            switch error {
            case .keychain(let status): log("Keychain 操作失败（OSStatus \(status)）。")
            case .invalidData: log("已保存的凭据数据无效，请清除后重新登录。")
            }
            exit(EXIT_FAILURE)
        } catch let error as TimetablePageCapture.CaptureError {
            log("课表入口采集未完成：\(error)。")
            exit(EXIT_FAILURE)
        } catch let error as TimetableError {
            log(TimetableDemo.errorMessage(for: error))
            exit(EXIT_FAILURE)
        } catch let error as NoticeError {
            log(NoticeDemo.errorMessage(for: error))
            exit(EXIT_FAILURE)
        } catch let error as TrainingPlanError {
            log(TrainingPlanDemo.errorMessage(for: error))
            exit(EXIT_FAILURE)
        } catch let error as GradeError {
            log(GradeDemo.errorMessage(for: error))
            exit(EXIT_FAILURE)
        } catch let error as ExamError {
            log(ExamDemo.errorMessage(for: error))
            exit(EXIT_FAILURE)
        } catch let error as LibraryError {
            log(LibraryDemo.errorMessage(for: error))
            exit(EXIT_FAILURE)
        } catch let error as CreditProgressError {
            log(CreditProgressDemo.errorMessage(for: error))
            exit(EXIT_FAILURE)
        } catch let error as CampusShuttleError {
            log(CampusShuttleDemo.errorMessage(for: error))
            exit(EXIT_FAILURE)
        } catch {
            log("演示未完成，错误类型：\(String(reflecting: type(of: error)))。")
            exit(EXIT_FAILURE)
        }
    }

    private static func run() async throws {
        if CommandLine.arguments.contains("--notices") {
            try await NoticeDemo.run()
            return
        }
        let username = try input("请输入账号（学号）：")
        let client = try makeClient(username: username)
        log("输入 1 恢复已保存的登录（默认），2 重新登录，3 清除本账号本地登录：")
        let choice = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines)
        if choice == "3" {
            try await client.logout()
            log("已清除本账号的本地 TGT 和会话；未撤销服务端或其他 App 的登录。")
            return
        }
        var password: String? = nil
        var result: WUSTLoginResult
        if choice == "2" {
            let value = try input("请输入密码：")
            password = value
            log("正在进行统一认证及会话建立……")
            result = try await client.login(password: value)
        } else {
            log("正在尝试复用或恢复登录……")
            result = try await client.ensureSession()
        }
        if case .loginRequired = result {
            let value = try input("没有可用 TGT，或 TGT 已失效。请输入密码：")
            password = value
            result = try await client.login(password: value)
        }
        if case .verificationRequired(_, let methods) = result {
            log("统一认证要求二次验证；可用方式：\(methods.map { $0 == .sms ? "短信" : "微信" }.joined(separator: "、"))")
            guard methods.contains(.sms) else {
                log("当前 Demo 未提供微信验证界面。")
                return
            }
            log("输入 1 发送一次短信验证码，其他输入结束：")
            guard readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) == "1" else { return }
            try await client.sendSMSCode()
            let code = try input("服务器已确认发送，请输入短信验证码：")
            let value: String
            if let password { value = password }
            else { value = try input("请输入密码以继续统一认证：") }
            log("正在校验短信并继续登录……")
            result = try await client.submitSMSCode(code, password: value)
        }
        password = nil
        guard describe(result) else { return }
        if CommandLine.arguments.contains("--shuttle") {
            try await CampusShuttleDemo.run(using: client)
            return
        }
        _ = try await client.fetchStudentInfo()
        log("学生信息读取成功，学号与登录账号一致。")
        try await runSessionMenu(client: client, username: username)
    }

    private static func runSessionMenu(client: WUSTLoginClient, username: String) async throws {
        var activeClient = client
        while true {
            log("输入 1 在全新 client 中恢复，2 复用当前会话，3 清除本地凭据，4 采集原始课表，5 查询并解析课表，6 查询教学周日期，7 查看学校通知，8 查看培养方案，9 查询课程成绩，10 查询考试安排，11 查看学分完成情况，12 查询图书馆只读信息，13 查询校车时刻表，其他输入结束：")
            switch readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) {
            case "1":
                let restored = try makeClient(username: username)
                guard describe(try await restored.ensureSession()) else { return }
                _ = try await restored.fetchStudentInfo()
                activeClient = restored
                log("全新 client 恢复与学生信息读取成功；后续查询使用这个新会话。")
            case "2":
                guard describe(try await activeClient.ensureSession()) else { return }
                _ = try await activeClient.fetchStudentInfo()
                log("当前教务会话复用及学生信息读取成功。")
            case "3":
                try await activeClient.logout()
                log("本账号的本地凭据及当前 client 会话已清除。")
                return
            case "4":
                guard let credential = await activeClient.currentCredential() else {
                    log("当前没有可用 TGT，请重新登录后采集。")
                    continue
                }
                log("正在用已有 TGT 建立采集会话，并请求课表入口……")
                let captured = try await TimetablePageCapture.capture(
                    credential: credential,
                    deviceID: loadOrCreateATrustDeviceID(),
                    choose: chooseTimetableQuery,
                    onSaved: { url in log("已保存原始响应：\(url.path)") }
                )
                log("入口原始响应：\(captured.entryURL.path)")
                log("整学期 POST 响应：\(captured.semesterURL.path)")
                if let weekURL = captured.weekURL {
                    log("指定周次 POST 响应：\(weekURL.path)")
                    log("筛选条件已在响应表单中确认；详细课表内容\(captured.weeklyContentChanged == true ? "有变化" : "相同，仍需结合该周课程核对")。")
                }
                log("原始 HTML 与请求条件、编码及摘要均已保存在本地。解析查询请使用菜单 5。")
            case "5":
                do {
                    try await TimetableDemo.run(using: activeClient)
                } catch let error as TimetableError {
                    log(TimetableDemo.errorMessage(for: error))
                } catch WUSTLoginClientError.notAuthenticated {
                    log("课表查询需要重新处理登录状态。")
                    _ = describe(try await activeClient.ensureSession())
                    return
                }
            case "6":
                do {
                    try await TeachingCalendarDemo.run(using: activeClient)
                } catch let error as TimetableError {
                    log(TimetableDemo.errorMessage(for: error))
                } catch WUSTLoginClientError.notAuthenticated {
                    log("教学周查询需要重新处理登录状态。")
                    _ = describe(try await activeClient.ensureSession())
                    return
                }
            case "7":
                try await NoticeDemo.run()
            case "8":
                do {
                    try await TrainingPlanDemo.run(using: activeClient)
                } catch let error as TrainingPlanError {
                    log(TrainingPlanDemo.errorMessage(for: error))
                } catch WUSTLoginClientError.notAuthenticated {
                    log("培养方案查询需要重新处理登录状态。")
                    _ = describe(try await activeClient.ensureSession())
                    return
                }
            case "9":
                do {
                    try await GradeDemo.run(using: activeClient)
                } catch let error as GradeError {
                    log(GradeDemo.errorMessage(for: error))
                } catch WUSTLoginClientError.notAuthenticated {
                    log("成绩查询需要重新处理登录状态。")
                    _ = describe(try await activeClient.ensureSession())
                    return
                }
            case "10":
                do {
                    try await ExamDemo.run(using: activeClient)
                } catch let error as ExamError {
                    log(ExamDemo.errorMessage(for: error))
                } catch WUSTLoginClientError.notAuthenticated {
                    log("考试安排查询需要重新处理登录状态。")
                    _ = describe(try await activeClient.ensureSession())
                    return
                }
            case "11":
                do {
                    try await CreditProgressDemo.run(using: activeClient)
                } catch let error as CreditProgressError {
                    log(CreditProgressDemo.errorMessage(for: error))
                } catch WUSTLoginClientError.notAuthenticated {
                    log("学分查询需要重新处理登录状态。")
                    _ = describe(try await activeClient.ensureSession())
                    return
                }
            case "12":
                do {
                    try await LibraryDemo.run(using: activeClient)
                } catch let error as LibraryError {
                    log(LibraryDemo.errorMessage(for: error))
                } catch WUSTLoginClientError.notAuthenticated {
                    log("图书馆查询需要可用的统一认证 TGT。请使用已保存或新登录的凭据。")
                    _ = describe(try await activeClient.ensureSession())
                    return
                }
            case "13":
                do {
                    try await CampusShuttleDemo.run(using: activeClient)
                } catch let error as CampusShuttleError {
                    log(CampusShuttleDemo.errorMessage(for: error))
                } catch WUSTLoginClientError.notAuthenticated {
                    log("校车查询需要可用的统一认证 TGT。")
                    return
                }
            default:
                return
            }
        }
    }

    private static func chooseTimetableQuery(_ form: TimetableCaptureForm) throws -> TimetableCaptureSelection {
        log("服务器提供 \(form.terms.count) 个学期选项；以下为前 5 项：")
        for term in form.terms.prefix(5) { log("\(term.value)  \(term.title)") }
        log("当前学期：\(form.selectedTermID ?? "未明确")。输入目标学期 ID，回车保留当前值：")
        guard let termInput = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) else { throw DemoError.missingInput }
        let term = termInput.isEmpty ? (form.selectedTermID ?? "") : termInput
        guard !term.isEmpty, form.terms.contains(where: { $0.value == term }) else {
            throw TimetableCaptureError.invalidSelection
        }
        for (index, option) in form.templates.enumerated() { log("节次模式 \(index + 1)：\(option.title)") }
        log("输入节次模式序号，回车保留当前模式：")
        guard let templateInput = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) else { throw DemoError.missingInput }
        let template: String
        if templateInput.isEmpty { template = form.selectedTemplateID ?? "" }
        else {
            guard let index = Int(templateInput), index > 0, index <= form.templates.count else {
                throw TimetableCaptureError.invalidSelection
            }
            template = form.templates[index - 1].value
        }
        let weekOptions = form.weeks.filter { !$0.value.isEmpty }
        log("可验证周次：\(weekOptions.map(\.value).joined(separator: ", "))")
        let defaultWeek = weekOptions.first?.value ?? ""
        log("将先采集整学期，再采集指定周。输入周次，回车使用 \(defaultWeek)，输入“全部”跳过单周采集：")
        guard let weekInput = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) else { throw DemoError.missingInput }
        let week = weekInput == "全部" ? "" : (weekInput.isEmpty ? defaultWeek : weekInput)
        guard form.weeks.contains(where: { $0.value == week }),
              form.templates.contains(where: { $0.value == template }) else {
            throw TimetableCaptureError.invalidSelection
        }
        return TimetableCaptureSelection(termID: term, week: week, templateID: template)
    }

    private static func makeClient(username: String) throws -> WUSTLoginClient {
        try WUSTLoginClient(
            username: username, deviceID: loadOrCreateATrustDeviceID(),
            credentialStore: DemoCredentialStore()
        )
    }

    private static func describe(_ result: WUSTLoginResult) -> Bool {
        switch result {
        case .authenticated: log("aTrust 与教务会话已就绪。请勿打印 Cookie 或 TGT。") ; return true
        case .loginRequired: log("TGT 不可用，需要重新登录。")
        case .verificationRequired: log("服务器仍要求二次验证，本次演示停止，不自动重复发送短信。")
        case .additionalAuthenticationRequired: log("aTrust 要求尚未接入的后续认证，本次演示停止。")
        }
        return false
    }

    private static func input(_ prompt: String) throws -> String {
        log(prompt)
        guard let value = readLine(), !value.isEmpty else { throw DemoError.missingInput }
        return value
    }

    private static func log(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
    }

    private static func loadOrCreateATrustDeviceID() throws -> String {
        guard let preferences = UserDefaults(suiteName: "WUSTFoundation.WUSTDemo") else {
            throw DemoError.deviceIDStorageUnavailable
        }
        let key = "ATrustDeviceID"
        if let saved = preferences.string(forKey: key), !saved.isEmpty { return saved }
        let value = (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "").lowercased()
        preferences.set(value, forKey: key)
        return value
    }
}
