import Foundation
import JavaScriptCore
import Testing
@testable import WUSTFoundation

@MainActor
struct OfficialSliderWebPageTests {
    @Test(arguments: ["0", "true", "1", "'1'"])
    func bridgeRequiresAnActualSuccessfulServerResult(_ code: String) throws {
        let context = try environment()
        context.evaluateScript(OfficialSliderWebPage.script(id: UUID()))
        context.evaluateScript("listeners.load(); flush();")
        #expect(context.exception == nil)
        #expect(context.evaluateScript("JSON.stringify(fragmentLoads)")?.toString() == "[\"/authserver/common/toSliderCaptcha.htl\"]")
        #expect(context.evaluateScript("messages.filter(x => x.kind === 'ready').length")?.toInt32() == 1)
        // Calling a presentation callback alone cannot make the native side accept a challenge.
        context.evaluateScript("instance.options.onSuccess(); flush();")
        #expect(context.evaluateScript("messages.filter(x => x.kind === 'verified').length")?.toInt32() == 0)
        context.evaluateScript("var request = new XMLHttpRequest(); request.open('POST', '/authserver/common/verifySliderCaptcha.htl'); request.reply(\(code), 200); instance.options.onSuccess(); flush();")
        #expect(context.exception == nil)
        let expected: Int32 = code == "1" || code == "'1'" ? 1 : 0
        #expect(context.evaluateScript("messages.filter(x => x.kind === 'verified').length")?.toInt32() == expected)
        context.evaluateScript("instance.options.onSuccess(); flush();")
        #expect(context.evaluateScript("messages.filter(x => x.kind === 'verified').length")?.toInt32() == expected)
        #expect(context.evaluateScript("nativeSubmits")?.toInt32() == 0)
    }

    @Test func foreignResponseAndHTTPFailureCannotAuthorizeTheBridge() throws {
        let context = try environment()
        context.evaluateScript(OfficialSliderWebPage.script(id: UUID()))
        context.evaluateScript("listeners.load(); flush();")
        context.evaluateScript("var a = new XMLHttpRequest(); a.open('POST', '/authserver/common/verifySliderCaptcha.htl'); a.reply(1, 200, 'https://other.invalid/response'); instance.options.onSuccess(); flush();")
        context.evaluateScript("var b = new XMLHttpRequest(); b.open('POST', '/authserver/common/verifySliderCaptcha.htl'); b.reply(1, 503); instance.options.onSuccess(); flush();")
        #expect(context.exception == nil)
        #expect(context.evaluateScript("messages.filter(x => x.kind === 'verified').length")?.toInt32() == 0)
    }

    @Test func standaloneDocumentContainsOnlyComponentDependencies() {
        let html = OfficialSliderWebPage.html
        #expect(html.contains("jquery-latest.min.js"))
        #expect(html.contains("encrypt.js"))
        #expect(html.contains("id=\"sliderCaptchaDiv\""))
        for excluded in ["<form", "pwdFromId", "login.js", "createSliderCaptcha", "password"] {
            #expect(!html.contains(excluded))
        }
        #expect(OfficialSliderWebPage.isComponentURL(OfficialSliderWebPage.componentURL))
        for url in ["http://auth.wust.edu.cn/authserver/common/toSliderCaptcha.htl",
                    "https://other.invalid/authserver/common/toSliderCaptcha.htl",
                    "https://auth.wust.edu.cn/authserver/login",
                    "https://auth.wust.edu.cn/authserver/common/toSliderCaptcha.htl?service=other"] {
            #expect(!OfficialSliderWebPage.isComponentURL(URL(string: url)!))
        }
    }

    private func environment() throws -> JSContext {
        let context = try #require(JSContext())
        let parse: @convention(block) (String, String) -> NSDictionary = { raw, base in
            guard let base = URL(string: base), let url = URL(string: raw, relativeTo: base)?.absoluteURL,
                  let scheme = url.scheme, let host = url.host else { return [:] }
            let port = url.port.map { ":\($0)" } ?? ""
            return ["origin": "\(scheme)://\(host)\(port)", "pathname": url.path, "href": url.absoluteString]
        }
        context.setObject(parse, forKeyedSubscript: "parseNativeURL" as NSString)
        context.evaluateScript(#"""
        var window = this, messages = [], listeners = {}, jobs = [], nativeSubmits = 0;
        var location = {href:'https://auth.wust.edu.cn/authserver/common/toSliderCaptcha.htl', origin:'https://auth.wust.edu.cn'};
        function URL(raw, base) { Object.assign(this, parseNativeURL(String(raw), base || location.href)); }
        window.webkit = {messageHandlers:{wustManualCaptcha:{postMessage: x => messages.push(x)}}};
        window.addEventListener = (name, callback) => { listeners[name] = callback; };
        function setTimeout(fn, ms) { jobs.push({fn, ms}); return jobs.length; }
        function setInterval() { return 1; }
        function clearInterval() {}
        function flush() { for (var i=0; i<20; i++) { var index=jobs.findIndex(x => x.ms === 0); if(index<0) break; jobs.splice(index,1)[0].fn(); } }
        function element() { return {style:{setProperty(){}}, appendChild(){}}; }
        var target = element();
        var document = {
          documentElement:{style:{}},
          body:{children:[], appendChild(x){ this.children.push(x); }},
          head:{appendChild(){}}, createElement:element, getElementById:() => target
        };
        function MutationObserver() { this.observe = () => {}; }
        var instance, fragmentLoads = [], contextPath = '/authserver';
        function encryptPassword() {}
        function jQuery() { return {
          data:() => instance,
          html:() => { instance = {options:{onSuccess:() => { nativeSubmits++; }}}; }
        }; }
        jQuery.ajax = options => {
          fragmentLoads.push(options.url);
          options.success('<div id="sliderDiv"></div>');
        };
        function XMLHttpRequest() { this.events=[]; }
        XMLHttpRequest.prototype.open = function(method,path) { this.target = new URL(path,location.href); };
        XMLHttpRequest.prototype.addEventListener = function(name, fn) { this.events.push(fn); };
        XMLHttpRequest.prototype.reply = function(code,status,finalURL) {
          this.readyState=4; this.status=status; this.responseText=JSON.stringify({errorCode:code});
          this.responseURL=finalURL || this.target.href; this.events.forEach(fn => fn());
        };
        """#)
        #expect(context.exception == nil)
        return context
    }
}
