import Foundation
import Darwin
import WUSTFoundation
#if os(macOS)
import AppKit
#endif

@main
struct WUSTDemo {
    enum DemoError: Error { case missingInput }

    #if os(macOS)
    @MainActor static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        Task {
            await runAndReport()
            application.terminate(nil)
        }
        // A command-line async main alone does not own AppKit's mouse/touch event loop.
        application.run()
    }
    #else
    static func main() async { await runAndReport() }
    #endif

    private static func runAndReport() async {
        do { try await run() }
        catch let error as URLError {
            log("网络请求失败（URLError \(error.code.rawValue)），未将其判定为凭据失效。")
            exit(EXIT_FAILURE)
        } catch is CancellationError {
            log("操作已取消。")
        } catch let error as DemoLoginFile.StoreError {
            switch error {
            case .keychain(let status): log("本地账密文件的密钥读取失败（OSStatus \(status)）。")
            default: log("本地账密文件不可用，请用 --update-login-file 重新保存。")
            }
            exit(EXIT_FAILURE)
        } catch let error as AuthServerCredentialError {
            log(error.localizedDescription)
            exit(EXIT_FAILURE)
        } catch let error as AuthServerLoginError {
            if case .smsCodeRejected(let code) = error {
                let safeCode = code.range(of: #"\A[A-Za-z0-9_]{1,32}\z"#, options: .regularExpression) != nil ? code : "UNKNOWN"
                log("学校未确认短信发送（业务码 \(safeCode)），请稍后再试或使用网页登录。")
            } else {
                log("新版认证登录未完成：\(error)。若学校要求其他验证，可使用网页登录入口。")
            }
            exit(EXIT_FAILURE)
        } catch let error as SliderCaptchaError {
            log("滑块验证未完成：\(error)。")
            exit(EXIT_FAILURE)
        } catch let error as WUSTLoginClientError {
            log("登录流程未完成：\(error)。")
            exit(EXIT_FAILURE)
        } catch let error as UndergraduateAuthServiceError {
            log("教务会话处理失败：\(error)。")
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
        #if os(macOS)
        if CommandLine.arguments.contains("--manual-slider-preview") {
            try await ManualSliderLoginDemo.preview()
            return
        }
        #endif
        if CommandLine.arguments.contains("--login-file-path") {
            log(DemoLoginFile.fileURL.path)
            return
        }
        if CommandLine.arguments.contains("--clear-login-file") {
            try DemoLoginFile.clear()
            log("已清除 Demo 本地账密文件。")
            return
        }
        if CommandLine.arguments.contains("--update-login-file") {
            let username = try input("请输入要保存的登录账号：")
            let password = try await DemoPasswordInput.read(savingLocally: true)
            try DemoLoginFile.save(.init(username: username, password: password))
            log("已保存 Demo 本地账密文件：\(DemoLoginFile.fileURL.path)")
            return
        }
        if CommandLine.arguments.contains("--slider-captcha") {
            try await SliderCaptchaDemo.run()
            return
        }
        if CommandLine.arguments.contains("--notices") {
            try await NoticeDemo.run()
            return
        }
        let savedLogin = !CommandLine.arguments.contains("--sms-login") && DemoLoginFile.exists ? try DemoLoginFile.load() : nil
        let username: String
        if let savedLogin {
            username = savedLogin.username
            log("已从本地账密文件读取测试账号。")
        } else {
            username = try input("请输入登录账号：")
        }
        let client = try makeClient(username: username)
        let choice: String?
        if CommandLine.arguments.contains("--manual-slider-login") {
            choice = "6"
        } else if CommandLine.arguments.contains("--sms-login") {
            choice = "5"
        } else if CommandLine.arguments.contains("--native-login") {
            choice = "4"
        } else {
            log("输入 1 检查当前会话（默认），2 在学校网页登录，3 清除当前会话，4 使用新版接口自动登录，5 短信登录，6 独立手动滑块登录：")
            choice = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if choice == "6" {
            #if os(macOS)
            let password: String
            if let saved = savedLogin?.password, !CommandLine.arguments.contains("--prompt-password") { password = saved }
            else { password = try await DemoPasswordInput.read(savingLocally: false) }
            let result = try await ManualSliderLoginDemo.run(using: client, password: password)
            guard describe(result) else { return }
            log("手动滑块登录及教务会话检查完成。")
            try await runSessionMenu(client: client, username: username)
            return
            #else
            throw WUSTLoginClientError.notAuthenticated
            #endif
        }
        if choice == "5" {
            log("请输入接收短信的绑定手机号或学号，回车使用当前账号。提交后会校验滑块并申请一次短信：")
            guard let entered = readLine() else { throw DemoError.missingInput }
            let account = entered.trimmingCharacters(in: .whitespacesAndNewlines)
            let diagnostics = DemoCaptchaDiagnostics()
            diagnostics.begin(1)
            var outcome = "短信申请未完成"
            defer {
                do { log("短信登录诊断日志：\(try diagnostics.save(outcome: outcome).path)") }
                catch { log("诊断日志保存失败（\(type(of: error))）。") }
            }
            let result: WUSTLoginResult
            do {
                let resendAfter = try await client.sendLoginSMSCode(to: account.isEmpty ? username : account) {
                    diagnostics.record($0, attempt: 1)
                }
                outcome = "短信已发送"
                log("服务器已确认短信发送。")
                if let resendAfter { log("服务器要求 \(resendAfter) 秒后再申请。") }
                let code = try await DemoPasswordInput.readCode()
                result = try await client.loginWithSMSCode(code)
            } catch let error as SliderCaptchaError {
                #if os(macOS)
                log("自动滑块校验未通过（\(error)），正在打开学校短信登录页。")
                result = try await WebLoginDemo.run(using: client, smsLogin: true)
                #else
                throw error
                #endif
            }
            guard describe(result) else { return }
            _ = try await client.fetchStudentInfo()
            outcome = "短信登录及学生信息读取完成"
            log("短信登录及学生信息读取成功。")
            try await runSessionMenu(client: client, username: username)
            return
        }
        if choice == "4" {
            let password: String
            if let savedLogin {
                password = savedLogin.password
                log("已从本地账密文件读取密码。")
            } else {
                password = try await DemoPasswordInput.read(savingLocally: true)
                try DemoLoginFile.save(.init(username: username, password: password))
                log("已保存 Demo 本地账密文件：\(DemoLoginFile.fileURL.path)")
            }
            log("正在通过新版接口登录并自动校验滑块……")
            let result = try await DemoCaptchaRetry.run(label: "新版自动登录") { diagnostics in
                try await client.loginWithAuthServer(password: password, maxSliderAttempts: 1, diagnostics: diagnostics)
            }
            guard describe(result) else { return }
            _ = try await client.fetchStudentInfo()
            log("新版登录与学生信息读取成功。")
            try await runSessionMenu(client: client, username: username)
            return
        }
        if choice == "3" {
            try await client.logout()
            log("已清除当前 client 会话；未退出学校服务端或其他 App。")
            return
        }
        var result: WUSTLoginResult
        #if os(macOS)
        if choice == "2" {
            result = try await WebLoginDemo.run(using: client)
        } else {
            log("正在检查当前教务会话……")
            result = try await client.ensureSession()
            if case .loginRequired = result { result = try await WebLoginDemo.run(using: client) }
        }
        #else
        if choice == "2" { throw WUSTLoginClientError.notAuthenticated }
        result = try await client.ensureSession()
        if case .loginRequired = result {
            throw WUSTLoginClientError.notAuthenticated
        }
        #endif
        guard describe(result) else { return }
        if CommandLine.arguments.contains("--shuttle") {
            try await CampusShuttleDemo.run(using: client)
            return
        }
        _ = try await client.fetchStudentInfo()
        log("学生信息读取成功。")
        try await runSessionMenu(client: client, username: username)
    }

    private static func runSessionMenu(client: WUSTLoginClient, username: String) async throws {
        var activeClient = client
        while true {
            log("输入 1 使用全新 client 重新登录，2 复用当前会话，3 清除当前会话，4 采集原始课表，5 查询并解析课表，6 查询教学周日期，7 查看学校通知，8 查看培养方案，9 查询课程成绩，10 查询考试安排，11 查看学分完成情况，12 查询图书馆只读信息，13 查询校车时刻表，14 查询第二课堂成绩单，其他输入结束：")
            switch readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) {
            case "1":
                let restored = try makeClient(username: username)
                #if os(macOS)
                guard describe(try await WebLoginDemo.run(using: restored)) else { return }
                #else
                throw WUSTLoginClientError.notAuthenticated
                #endif
                _ = try await restored.fetchStudentInfo()
                activeClient = restored
                log("全新 client 登录与学生信息读取成功；后续查询使用这个新会话。")
            case "2":
                guard describe(try await activeClient.ensureSession()) else { return }
                _ = try await activeClient.fetchStudentInfo()
                log("当前教务会话复用及学生信息读取成功。")
            case "3":
                try await activeClient.logout()
                log("当前 client 会话已清除。")
                return
            case "4":
                log("正在使用当前教务会话请求课表入口……")
                let captured = try await TimetablePageCapture.capture(
                    using: activeClient,
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
                    log("图书馆查询需要有效的图书馆会话，新版跨系统自动登录尚未接入。")
                    _ = describe(try await activeClient.ensureSession())
                    return
                }
            case "13":
                do {
                    try await CampusShuttleDemo.run(using: activeClient)
                } catch let error as CampusShuttleError {
                    log(CampusShuttleDemo.errorMessage(for: error))
                } catch WUSTLoginClientError.notAuthenticated {
                    log("校车查询需要有效的门户会话，新版跨系统自动登录尚未接入。")
                    return
                }
            case "14":
                do {
                    try await SecondClassDemo.run(using: activeClient)
                } catch let error as SecondClassError {
                    log(SecondClassDemo.errorMessage(for: error))
                } catch WUSTLoginClientError.notAuthenticated {
                    log("第二课堂查询需要有效的学工会话，新版跨系统自动登录尚未接入。")
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
        try WUSTLoginClient(username: username)
    }

    private static func describe(_ result: WUSTLoginResult) -> Bool {
        switch result {
        case .authenticated: log("教务会话已就绪。") ; return true
        case .loginRequired: log("教务会话不可用，需要重新登录。")
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

}
