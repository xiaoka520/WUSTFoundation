import Foundation
import Testing
@testable import WUSTFoundation

struct AuthServerRequestHeadersTests {
    @Test func navigationAndAjaxUseTheSameSafariIdentity() {
        let url = URL(string: "https://auth.test/authserver/login")!
        var navigation = URLRequest(url: url)
        var ajax = URLRequest(url: url.appendingPathComponent("challenge"))
        ajax.httpMethod = "POST"
        AuthServerRequestHeaders.apply(to: &navigation, ajax: false)
        AuthServerRequestHeaders.apply(to: &ajax, ajax: true, referer: url)
        #expect(navigation.value(forHTTPHeaderField: "User-Agent") == ajax.value(forHTTPHeaderField: "User-Agent"))
        #expect(navigation.value(forHTTPHeaderField: "Accept")?.contains("text/html") == true)
        #expect(ajax.value(forHTTPHeaderField: "Accept")?.contains("application/json") == true)
        #expect(ajax.value(forHTTPHeaderField: "Referer") == url.absoluteString)
        #expect(ajax.value(forHTTPHeaderField: "Origin") == "https://auth.test")
        #expect(ajax.value(forHTTPHeaderField: "X-Requested-With") == "XMLHttpRequest")
        #expect(navigation.value(forHTTPHeaderField: "Origin") == nil)
        #expect(ajax.value(forHTTPHeaderField: "Cookie") == nil)
    }

    @Test func foreignRefererIsNotCopied() {
        var request = URLRequest(url: URL(string: "https://auth.test/authserver/login")!)
        AuthServerRequestHeaders.apply(to: &request, ajax: true, referer: URL(string: "https://other.test/private")!)
        #expect(request.value(forHTTPHeaderField: "Referer") == nil)
    }
}
