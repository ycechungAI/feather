import WebKit

/// Page scripts for video: keeping Picture in Picture open through YouTube ads, and finding the
/// stream behind a video so it can be downloaded or given subtitles.
enum MediaScripts {
    static let pipMessage = "featherPiP"

    static var userScripts: [WKUserScript] {
        [WKUserScript(source: pipKeeper, injectionTime: .atDocumentStart, forMainFrameOnly: false),
         WKUserScript(source: streamWatcher, injectionTime: .atDocumentStart, forMainFrameOnly: false)]
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

extension MediaScripts {
    /// Players that stream through Media Source show a `blob:` address instead of the stream's,
    /// so this notes the playlists (.m3u8, .mpd) the page loads. It only reads the browser's own
    /// list of loaded resources.
    static let streamWatcher = #"""
    (() => {
      const key = Symbol.for('feather.streams');
      if (window[key]) return;
      const seen = [];
      Object.defineProperty(window, key, { value: seen });
      const note = name => { if (/\.(m3u8|mpd)([?#]|$)/i.test(name) && !seen.includes(name)) seen.push(name); };
      try {
        new PerformanceObserver(list => list.getEntries().forEach(e => note(e.name)))
          .observe({ type: 'resource', buffered: true });
      } catch (e) {}
    })();
    """#

    /// Describes this frame's main video (playing beats paused, bigger beats smaller) and
    /// remembers it for the subtitle scripts below.
    static let videoProbe = #"""
    const videos = [...document.querySelectorAll('video')].filter(v => v.offsetWidth > 0 && v.offsetHeight > 0);
    const area = v => v.offsetWidth * v.offsetHeight;
    const video = videos.find(v => !v.paused) || videos.sort((a, b) => area(b) - area(a))[0];
    if (!video) return JSON.stringify({ score: 0 });
    window[Symbol.for('feather.video')] = video;
    const kinds = ['subtitles', 'captions', 'forced', ''];
    const tracks = [...video.textTracks].map((t, i) => ({ index: i, label: t.label, language: t.language,
      kind: t.kind, showing: t.mode === 'showing' })).filter(t => kinds.includes(t.kind));
    return JSON.stringify({ score: area(video) + (video.paused ? 0 : 1e9), src: video.currentSrc || video.src || '',
      streams: window[Symbol.for('feather.streams')] || [], title: document.title, page: location.href,
      userAgent: navigator.userAgent, tracks });
    """#

    /// Shows subtitle track `index` (-1 = none) of the video found by videoProbe.
    static let showTrack = #"""
    const video = window[Symbol.for('feather.video')];
    if (!video) return 'none';
    const kinds = ['subtitles', 'captions', 'forced', ''];
    [...video.textTracks].forEach((t, i) => { if (kinds.includes(t.kind)) t.mode = i === index ? 'showing' : 'disabled'; });
    return 'ok';
    """#

    /// Adds `cues` ([start, end, text]) as a new subtitle track named `label` and shows it.
    static let addCues = #"""
    const video = window[Symbol.for('feather.video')];
    if (!video) return 'none';
    [...video.textTracks].forEach(t => { if (t.mode === 'showing') t.mode = 'disabled'; });
    const track = video.addTextTrack('subtitles', label, '');
    for (const [start, end, text] of cues) track.addCue(new VTTCue(start, end, text));
    track.mode = 'showing';
    return 'ok';
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
