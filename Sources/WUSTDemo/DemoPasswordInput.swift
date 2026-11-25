import Foundation
import Darwin
#if os(macOS)
import AppKit
#endif

enum DemoPasswordInput {
    static func readCode() async throws -> String {
        #if os(macOS)
        if isatty(STDIN_FILENO) == 0 {
            return try await MainActor.run {
                let app = NSApplication.shared
                if app.activationPolicy() == .prohibited { app.setActivationPolicy(.accessory) }
                let alert = NSAlert()
                alert.messageText = "请输入学校短信验证码"
                alert.addButton(withTitle: "登录")
                alert.addButton(withTitle: "取消")
                let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
                alert.accessoryView = field
                alert.window.initialFirstResponder = field
                app.activate()
                defer { field.stringValue = "" }
                guard alert.runModal() == .alertFirstButtonReturn else { throw CancellationError() }
                guard !field.stringValue.isEmpty else { throw WUSTDemo.DemoError.missingInput }
                return field.stringValue
            }
        }
        #endif
        guard let bytes = getpass("请输入学校短信验证码："), bytes.pointee != 0 else {
            throw WUSTDemo.DemoError.missingInput
        }
        let code = String(cString: bytes)
        bytes.initialize(repeating: 0, count: strlen(bytes))
        return code
    }

    static func read(savingLocally: Bool = false) async throws -> String {
        #if os(macOS)
        // Xcode's debug console is a pipe, not a terminal with controllable password echo.
        if isatty(STDIN_FILENO) == 0 {
            return try await MainActor.run {
                let app = NSApplication.shared
                if app.activationPolicy() == .prohibited { app.setActivationPolicy(.accessory) }
                let alert = NSAlert()
                alert.messageText = "请输入统一认证密码"
                alert.informativeText = savingLocally
                    ? "账密会保存为本机的加密文件，供 Demo 重复测试使用。"
                    : "本次使用新版接口登录，滑块由程序自动处理。"
                alert.addButton(withTitle: savingLocally ? "保存" : "登录")
                alert.addButton(withTitle: "取消")
                let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
                field.placeholderString = "密码"
                alert.accessoryView = field
                alert.window.initialFirstResponder = field
                app.activate()
                defer { field.stringValue = "" }
                guard alert.runModal() == .alertFirstButtonReturn else { throw CancellationError() }
                guard !field.stringValue.isEmpty else { throw WUSTDemo.DemoError.missingInput }
                return field.stringValue
            }
        }
        #endif
        guard let bytes = getpass("请输入密码："), bytes.pointee != 0 else {
            throw WUSTDemo.DemoError.missingInput
        }
        let password = String(cString: bytes)
        bytes.initialize(repeating: 0, count: strlen(bytes))
        return password
    }
}
