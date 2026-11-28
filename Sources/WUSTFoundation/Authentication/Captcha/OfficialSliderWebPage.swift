import Foundation

enum OfficialSliderWebPage {
    static let componentURL = URL(string: "https://auth.wust.edu.cn/authserver/common/toSliderCaptcha.htl")!

    static func isComponentURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == componentURL.host &&
        [nil, 443].contains(url.port) && url.path == componentURL.path &&
        url.user == nil && url.password == nil && url.query == nil && url.fragment == nil
    }

    // No login page, login.js or password form is loaded into this document.
    static let html = #"""
    <!doctype html>
    <html lang="zh-CN"><head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title>安全验证</title>
    <script>var contextPath = '/authserver';</script>
    <script src="/authserver/wustTheme/static/common/jquery-latest.min.js"></script>
    <script src="/authserver/wustTheme/static/common/encrypt.js"></script>
    <style>
      html, body { margin:0!important; padding:0!important; min-width:0!important; overflow:hidden!important; background:transparent!important; }
      body { font-family:system-ui,sans-serif; }
      #sliderCaptchaDiv { width:100%; padding:8px 0; }
      #captcha-id { position:static!important; display:block!important; width:100%!important; margin:0!important; transform:none!important; }
      .slidercaptcha-fluid { position:static!important; top:auto!important; left:auto!important; transform:none!important; }
      .slidercaptcha.card { position:relative!important; left:0!important; top:0!important; width:300px!important; margin:0 auto!important; background:white; color:#45494c; }
      .slidercaptcha .card-header { padding:12px 10px; }
      .slidercaptcha .card-body { padding:10px!important; }
      #bjGray, .closeIcon { display:none!important; }
    </style>
    </head><body><div id="sliderCaptchaDiv"></div></body></html>
    """#

    static func script(id: UUID) -> String {
        template.replacingOccurrences(of: "__WUST_NONCE__", with: id.uuidString)
    }

    // The official scripts handle all drawing, pointer events and verification. This bridge only
    // loads the standalone fragment and observes a server-confirmed result; it creates no movement.
    private static let template = #"""
    (() => {
      'use strict';
      const nonce = '__WUST_NONCE__';
      let verified = false, sent = false, ready = false, hooked;
      const post = kind => window.webkit.messageHandlers.wustManualCaptcha.postMessage({nonce, kind});
      document.documentElement.style.opacity = '0';
      const nativeOpen = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function(method, path) {
        let target;
        try { target = new URL(path, location.href); } catch (_) {}
        if (target && target.origin === location.origin && target.pathname === '/authserver/common/verifySliderCaptcha.htl') {
          verified = false;
          this.addEventListener('readystatechange', () => {
            if (this.readyState !== 4 || this.status !== 200) return;
            try {
              const finalURL = new URL(this.responseURL || target.href);
              if (finalURL.origin !== target.origin || finalURL.pathname !== target.pathname) return;
              const result = JSON.parse(this.responseText);
              verified = result.errorCode === 1 || result.errorCode === '1';
            } catch (_) { verified = false; }
          });
        }
        return nativeOpen.apply(this, arguments);
      };
      const bridgeSuccess = () => setTimeout(() => {
        if (!verified || sent) return;
        sent = true;
        post('verified');
      }, 0);
      const install = () => {
        if (!window.jQuery) return;
        const instance = jQuery('#sliderDiv').data('lgb.SliderCaptcha');
        if (!instance || !instance.options) return;
        if (hooked !== instance) { hooked = instance; instance.options.onSuccess = bridgeSuccess; }
        if (!ready) { ready = true; document.documentElement.style.opacity = '1'; post('ready'); }
      };
      window.addEventListener('load', () => setTimeout(() => {
        try {
          const target = document.getElementById('sliderCaptchaDiv');
          if (!target || !window.jQuery || typeof window.encryptPassword !== 'function') throw new Error('component unavailable');
          new MutationObserver(install).observe(target, {childList:true, subtree:true});
          // Same fragment endpoint and insertion method used by the official login page.
          jQuery.ajax({url:contextPath + '/common/toSliderCaptcha.htl', type:'GET', dataType:'html', cache:false,
            success: html => {
              if (typeof html !== 'string' || !html.includes('id="sliderDiv"')) { post('unavailable'); return; }
              jQuery(target).html(html);
              install();
            },
            error: () => post('unavailable')
          });
          install();
          const timer = setInterval(install, 50);
          setTimeout(() => { clearInterval(timer); if (!ready) post('unavailable'); }, 20000);
        } catch (_) { post('unavailable'); }
      }, 0), {once:true});
    })();
    """#
}
