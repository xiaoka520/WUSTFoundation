import Foundation

struct LoginTicketResponse: Decodable {
    let ticket: String?
    let data: LoginResponseInfo?
    let tgt: String?
}

struct LoginResponseInfo: Decodable {
    let code: String?
    let uid: String?
    let data: String?
}
