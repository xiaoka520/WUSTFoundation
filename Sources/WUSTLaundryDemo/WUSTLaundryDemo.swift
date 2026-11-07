import Darwin
import Foundation
import WUSTFoundation

@main
struct WUSTLaundryDemo {
    static func main() async {
        do {
            log("胖乖生活演示。输入 1 查询洗衣机，2 测试登录，0 退出。")
            switch readInput() {
            case "1": try await showDevices()
            case "2": try await testLogin()
            default: return
            }
        } catch let error as LaundryQueryError {
            log(message(for: error))
        } catch let error as LaundryAuthError {
            log(message(for: error))
        } catch let error as URLError {
            log("网络请求失败（\(error.code.rawValue)）。")
        } catch LaundryDemoCredentialStore.StoreError.keychain(let status) {
            log("钥匙串操作失败（\(status)）。")
        } catch {
            log("测试未完成（\(type(of: error))）。")
        }
    }

    private static func showDevices() async throws {
        let service = LaundryDeviceService()
        log("正在查询武汉科技大学黄家湖校区附近的洗衣机……")
        let page = try await service.fetchNearbyShops()
        guard !page.items.isEmpty else {
            log("附近没有查到洗衣机门店。")
            return
        }

        log("附近共 \(page.total) 家门店，本页显示 \(page.items.count) 家。")
        for (index, shop) in page.items.enumerated() {
            let available = shop.freeMachine.map(String.init) ?? "未知"
            let total = shop.machineCount.map(String.init) ?? "未知"
            log("\(index + 1). \(shop.name)，空闲 \(available) / 总数 \(total)")
        }

        log("输入门店编号查看空闲设备，回车默认选 1，输入 0 退出。")
        guard let choice = readInput(),
              let index = choice.isEmpty ? 1 : Int(choice),
              index > 0, index <= page.items.count else { return }
        let shop = page.items[index - 1]
        let inventory = try await service.fetchInventory(for: shop)
        let total = inventory.shop.machineCount.map(String.init) ?? "未知"
        log("\(inventory.shop.name)　设备总数 \(total)，空闲 \(inventory.availableDevices.count) 台。")
        if inventory.allDevices != nil {
            log("全部设备均为空闲，以下名单同时覆盖全部设备。")
        } else {
            log("胖乖本次仅返回空闲设备明细。")
        }
        for device in inventory.availableDevices {
            log("- \(device.name)")
        }
    }

    private static func testLogin() async throws {
        let auth = LaundryAuthService()
        let store = LaundryDemoCredentialStore()
        log("输入 1 验证已保存的登录，2 申请短信并登录，3 清除本地登录，0 退出。")
        switch readInput() {
        case "1":
            guard let saved = try store.load() else {
                log("暂无已保存的登录。首次测试请选择 2。")
                return
            }
            let restored = try await auth.restore(saved)
            try store.save(restored)
            let seconds = max(0, restored.lastVerifiedAt.timeIntervalSince(restored.firstVerifiedAt))
            log("胖乖服务端确认登录仍有效。同一凭据至少已验证可用 \(Int(seconds / 60)) 分钟。")
        case "2":
            log("请输入胖乖手机号，提交后将申请一条登录短信。")
            guard let phone = readInput(), !phone.isEmpty else { return }
            try await auth.sendSMSCode(to: phone)
            guard let code = readSMSCode(), !code.isEmpty else { return }
            let credential = try await auth.login(phone: phone, smsCode: code)
            try store.save(credential)
            log("胖乖登录已通过服务端验证，凭据已保存到本机钥匙串。")
        case "3":
            try store.clear()
            log("已清除本机保存的胖乖登录。")
        default:
            return
        }
    }

    private static func readSMSCode() -> String? {
        var buffer = [CChar](repeating: 0, count: 32)
        let hiddenInput = buffer.withUnsafeMutableBufferPointer { buffer -> String? in
            guard let address = buffer.baseAddress else { return nil }
            defer { _ = memset(address, 0, buffer.count) }
            guard readpassphrase("请输入收到的验证码（输入时隐藏）：", address, buffer.count, RPP_REQUIRE_TTY) != nil else {
                return nil
            }
            return String(cString: address).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let hiddenInput { return hiddenInput }
        log("请输入收到的验证码：")
        return readInput()
    }

    private static func readInput() -> String? {
        readLine()?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func log(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
    }

    private static func message(for error: LaundryQueryError) -> String {
        switch error {
        case .invalidQuery: "洗衣机查询参数无效。"
        case .invalidResponse: "无法识别胖乖返回的设备数据。"
        case .unexpectedStatusCode(let status): "洗衣机查询失败（HTTP \(status)）。"
        case .rejected(let code): "胖乖拒绝了设备查询（业务码 \(code)）。"
        }
    }

    private static func message(for error: LaundryAuthError) -> String {
        switch error {
        case .invalidPhoneNumber: "手机号格式有误。"
        case .invalidSMSCode: "短信验证码须为数字。"
        case .captchaRequired: "胖乖要求在官方登录页完成人机验证，当前短信申请已停止。"
        case .loginRequired: "胖乖服务端判定凭据已失效，请重新登录。"
        case .unexpectedStatusCode(let status): "胖乖请求失败（HTTP \(status)）。"
        case .rejected(let code): "胖乖服务端拒绝了请求（业务码 \(code)）。"
        case .invalidResponse: "胖乖响应格式无法识别。"
        case .accountMismatch: "胖乖返回的账号与已保存的凭据不一致。"
        case .unexpectedWebOrigin: "请在胖乖官方网页完成登录。"
        }
    }
}
