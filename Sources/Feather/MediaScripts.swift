import WebKit

/// Page scripts for video: keeping Picture in Picture open through YouTube ads.
enum MediaScripts {
    static let pipMessage = "featherPiP"

    static var userScripts: [WKUserScript] {
        [WKUserScript(source: pipKeeper, injectionTime: .atDocumentStart, forMainFrameOnly: false)]
    }

    /// When an ad starts, YouTube swaps the video's source and sets `disablePictureInPicture`,
    /// which closes the floating window. This keeps that flag off, and if the window still
    /// closes during an ad or a source swap, asks Feather to reopen it (see PiPKeeper).
    /// Closing the window yourself while the main video plays leaves it closed.
    static let pipKeeper = #"""
    (() => {
      const desc = Object.getOwnPropertyDescriptor(HTMLVideoElement.prototype, 'disablePictureInPicture');
      if (desc && desc.configurable) {
        Object.defineProperty(HTMLVideoElement.prototype, 'disablePictureInPicture',
          { configurable: true, enumerable: desc.enumerable, get() { return false; }, set() {} });
      }
      const setAttribute = Element.prototype.setAttribute;
      Element.prototype.setAttribute = function (name, value) {
        if (this instanceof HTMLVideoElement && String(name).toLowerCase() === 'disablepictureinpicture') return;
        return setAttribute.call(this, name, value);
      };

      let wanted = null, swappedAt = 0;
      const swapped = () => { swappedAt = Date.now(); };
      document.addEventListener('emptied', swapped, true);
      document.addEventListener('loadstart', swapped, true);
      const changed = e => {
        const v = e.target;
        if (!(v instanceof HTMLVideoElement)) return;
        if (document.pictureInPictureElement === v || v.webkitPresentationMode === 'picture-in-picture') {
          wanted = v;
          return;
        }
        if (v !== wanted) return;
        const ad = document.querySelector('.html5-video-player.ad-showing');
        if (ad || Date.now() - swappedAt < 3000) {
          window.webkit?.messageHandlers?.featherPiP?.postMessage('restore');
        } else {
          wanted = null;
        }
      };
      document.addEventListener('webkitpresentationmodechanged', changed, true);
      document.addEventListener('enterpictureinpicture', changed, true);
      document.addEventListener('leavepictureinpicture', e => setTimeout(() => changed(e), 0), true);
    })();
    """#
}

/// Receives the PiP keeper's "restore" message and reopens the floating window in that tab.
final class PiPKeeper: NSObject, WKScriptMessageHandler {
    static let shared = PiPKeeper()

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let webView = message.webView,
              let tab = BrowserWindowController.all.first(where: { $0.webView === webView }) else { return }
        tab.restorePictureInPicture(in: message.frameInfo)
    }
}
