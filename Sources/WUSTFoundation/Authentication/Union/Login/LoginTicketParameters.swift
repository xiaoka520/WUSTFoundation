import Foundation

struct LoginTicketParameters {
    let username: String //用户账号
    let encodedPassword: String //按认证协议处理后的密码
    let service: String //系统地址
    let captchaID: String
    let captchaCode: String //验证码答案
}
