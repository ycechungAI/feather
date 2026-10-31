import Foundation
import JavaScriptCore
import Testing
@testable import Feather

/// Runs Feather's injected page scripts in JavaScriptCore against a small fake page, so the
/// Picture in Picture and YouTube ad behaviour (fixed against real YouTube logs) can't regress.
@MainActor
private final class FakePage {
    let context = JSContext()!

    /// `setup` is JavaScript that builds the page on top of the shared fakes below.
    init(_ setup: String = "") {
        context.exceptionHandler = { _, error in Issue.record("JS error: \(error?.toString() ?? "?")") }
        context.evaluateScript(Self.fakes)
        context.evaluateScript(setup)
    }

    /// Runs `body` as the body of an async function and returns what it resolved to.
    func run(_ body: String) -> String? {
        context.evaluateScript("var __out; (async function () {\n\(body)\n})().then(v => __out = String(v), e => __out = 'throw: ' + e);")
        return waitFor("__out")
    }

    func eval(_ js: String) -> JSValue { context.evaluateScript(js) }

    /// Advances the page's clock in 10 ms steps until the global `name` is defined. Each step
    /// is its own evaluation, so promise callbacks run between timers as they do in a browser.
    func waitFor(_ name: String, timeout: TimeInterval = 20) -> String? {
        for _ in 0..<Int(timeout * 100) {
            if let v = context.objectForKeyedSubscript(name), !v.isUndefined { return v.toString() }
            context.evaluateScript("__advance(10)")
        }
        return nil
    }

    func settle(_ seconds: TimeInterval = 0.5) {
        for _ in 0..<Int(seconds * 100) { context.evaluateScript("__advance(10)") }
    }

    /// A DOM just big enough for the scripts: one YouTube-style player with one video whose
    /// WebKit presentation mode changes 50 ms after it's asked to (as WebKit's does).
    static let fakes = #"""
    // A virtual clock: timers run only when the test advances time, so tests are exact and fast.
    var __now = 0, __timers = [];
    function setTimeout(fn, ms) { __timers.push({ at: __now + (ms || 0), fn }); }
    function __advance(ms) {
      const end = __now + ms;
      for (;;) {
        __timers.sort((a, b) => a.at - b.at);
        const t = __timers[0];
        if (!t || t.at > end) break;
        __timers.shift();
        __now = t.at;
        t.fn();
      }
      __now = end;
    }
    class ClassList extends Set { contains(c) { return this.has(c); } }
    var messages = [];
    var window = globalThis;
    window.webkit = { messageHandlers: { featherPiP: { postMessage: m => messages.push(m) } } };
    var location = { hostname: 'www.youtube.com' };
    class Element {
      constructor() { this.listeners = {}; this.classList = new ClassList(); this.children = []; }
      setAttribute(name, value) { this['attr_' + name] = value; }
      removeAttribute(name) { delete this['attr_' + name]; }
      addEventListener(type, fn) { (this.listeners[type] ||= []).push(fn); }
      fire(type) {
        const fns = this.listeners[type] || [];
        this.listeners[type] = fns.filter(f => !f.once);
        fns.forEach(f => f());
        document.dispatch(type, this);
      }
      querySelector(sel) { return this.children.find(c => c.matches?.(sel)) || null; }
    }
    class HTMLVideoElement extends Element {}
    Object.defineProperty(HTMLVideoElement.prototype, 'disablePictureInPicture',
      { configurable: true, enumerable: true, get() { return this._dpip || false; }, set(v) { this._dpip = v; } });
    function makeVideo(props = {}) {
      const v = new HTMLVideoElement();
      Object.assign(v, { readyState: 4, offsetWidth: 640, offsetHeight: 360, paused: false, muted: false,
        duration: 30, currentTime: 0, webkitPresentationMode: 'inline', modeCalls: 0 }, props);
      v.addEventListener = function (type, fn, opts) { if (opts?.once) fn.once = true; Element.prototype.addEventListener.call(this, type, fn); };
      v.webkitSupportsPresentationMode = m => true;
      v.webkitSetPresentationMode = function (mode) {
        this.modeCalls++;
        setTimeout(() => { this.webkitPresentationMode = mode; this.fire('webkitpresentationmodechanged'); }, 50);
      };
      return v;
    }
    var video = makeVideo();
    var player = new Element();
    player.matches = sel => sel.includes('html5-video-player');
    player.querySelector = sel => sel === 'video' ? video : null;
    var document = {
      pictureInPictureElement: null,
      head: { appendChild() {} }, documentElement: { appendChild() {} },
      createElement: () => ({}),
      capture: {},
      addEventListener(type, fn) { (this.capture[type] ||= []).push(fn); },
      dispatch(type, target) { (this.capture[type] || []).forEach(fn => fn({ type, target })); },
      querySelectorAll: sel => sel === 'video' ? [video] : [],
      querySelector(sel) {
        if (sel.includes('ad-showing')) return player.classList.has('ad-showing') ? player : null;
        if (sel.includes('html5-video-player')) return player;
        if (sel.includes('video')) return video;
        return null;
      },
      exitPictureInPicture: () => new Promise(() => {}), // a stale PiP element never exits
    };
    class MutationObserver { constructor(fn) { this.fn = fn; } observe() {} disconnect() {} }
    var intervals = [];
    var setInterval = fn => intervals.push(fn);
    """#
}

@MainActor
struct PictureInPictureScriptTests {
    /// The state YouTube's next video left behind: the window closed (WebKit mode is inline)
    /// but the standard PiP element still points at the video.
    private let staleNextVideo = "document.pictureInPictureElement = video; video.webkitPresentationMode = 'inline';"

    @Test func probeIgnoresStaleStandardPiPState() throws {
        let page = FakePage(staleNextVideo)
        let json = try #require(page.run("\(BrowserWindowController.pipProbeScript)"))
        #expect(json.contains("\"active\":false"))
    }

    @Test func buttonOpensPiPAfterNextVideoClosedIt() {
        let page = FakePage(staleNextVideo)
        #expect(page.run(BrowserWindowController.pipScript) == "entered")
        #expect(page.eval("video.webkitPresentationMode").toString() == "picture-in-picture")
    }

    @Test func buttonClosesOpenPiP() {
        let page = FakePage("video.webkitPresentationMode = 'picture-in-picture';")
        #expect(page.run(BrowserWindowController.pipScript) == "exited")
        #expect(page.eval("video.webkitPresentationMode").toString() == "inline")
    }

    @Test func restoreReopensAfterNextVideo() {
        let page = FakePage(staleNextVideo)
        #expect(page.run(BrowserWindowController.pipRestoreScript) == "entered")
        #expect(page.eval("video.webkitPresentationMode").toString() == "picture-in-picture")
    }

    @Test func restoreLeavesOpenPiPAlone() {
        let page = FakePage("video.webkitPresentationMode = 'picture-in-picture';")
        #expect(page.run(BrowserWindowController.pipRestoreScript) == "entered")
        #expect(page.eval("video.modeCalls").toInt32() == 0)
    }

    /// During YouTube's countdown the next video has no data yet; restore retries on "none".
    @Test func restoreWaitsForTheNextVideosData() {
        let page = FakePage("video.readyState = 0;")
        #expect(page.run(BrowserWindowController.pipRestoreScript) == "none")
    }

    @Test func clearsYouTubesDisablePiPFlag() {
        let page = FakePage("video.disablePictureInPicture = true; video.setAttribute('disablepictureinpicture', '');")
        _ = page.run(BrowserWindowController.pipRestoreScript)
        #expect(page.eval("video.disablePictureInPicture").toBool() == false)
        #expect(page.eval("'attr_disablepictureinpicture' in video").toBool() == false)
    }

    @Test func fallsBackToStandardAPIWithoutWebKitModes() {
        let page = FakePage("""
            video = makeVideo(); delete video.webkitPresentationMode;
            video.webkitSupportsPresentationMode = undefined;
            video.requestPictureInPicture = async function () { document.pictureInPictureElement = this; };
            """)
        #expect(page.run(BrowserWindowController.pipScript) == "entered")
    }

    /// The stale case for the standard API: requestPictureInPicture "succeeds" without opening
    /// anything. That must be reported, not taken as success.
    @Test func reportsAStandardAPIRequestThatDidNothing() throws {
        let page = FakePage("""
            video = makeVideo(); video.webkitSupportsPresentationMode = () => false;
            video.requestPictureInPicture = async () => {};
            """)
        let result = try #require(page.run(BrowserWindowController.pipScript))
        #expect(result.hasPrefix("error:"))
    }
}

@MainActor
struct PictureInPictureKeeperTests {
    /// Loads the keeper and puts the video into PiP the way WebKit reports it.
    private func pageInPiP() -> FakePage {
        let page = FakePage()
        page.eval(MediaScripts.pipKeeper)
        page.eval("video.webkitSetPresentationMode('picture-in-picture');")
        page.settle()
        page.eval("messages = [];")
        return page
    }

    private func requests(_ page: FakePage) -> [String] {
        (page.eval("messages.filter(m => !m.startsWith('debug'))").toArray() as? [String]) ?? []
    }

    @Test func nextVideoClosingPiPAsksToReopen() {
        let page = pageInPiP()
        page.eval("video.fire('emptied'); video.webkitSetPresentationMode('inline');")
        page.settle()
        #expect(requests(page) == ["restore"])
    }

    @Test func staleStandardStateStillAsksToReopen() {
        let page = pageInPiP()
        page.eval("document.pictureInPictureElement = video; video.fire('emptied'); video.webkitSetPresentationMode('inline');")
        page.settle()
        #expect(requests(page) == ["restore"])
    }

    @Test func closingDuringAnAdAsksToReopen() {
        let page = pageInPiP()
        page.eval("player.classList.add('ad-showing'); video.webkitSetPresentationMode('inline');")
        page.settle()
        #expect(requests(page) == ["restore"])
    }

    @Test func closingItYourselfStaysClosed() {
        let page = pageInPiP()
        page.eval("video.webkitSetPresentationMode('inline');")
        page.settle()
        #expect(requests(page) == ["left"])
    }

    /// Ads swap the video's source without closing PiP; that alone must not close and reopen it.
    @Test func adSourceSwapAloneDoesNothing() {
        let page = pageInPiP()
        page.eval("video.fire('emptied'); video.fire('loadstart'); video.fire('playing');")
        page.settle()
        #expect(requests(page).isEmpty)
    }

    @Test func keepsDisablePiPOff() {
        let page = FakePage()
        page.eval(MediaScripts.pipKeeper)
        page.eval("video.disablePictureInPicture = true; video.setAttribute('disablePictureInPicture', '');")
        #expect(page.eval("video.disablePictureInPicture").toBool() == false)
        #expect(page.eval("'attr_disablePictureInPicture' in video").toBool() == false)
    }
}

@MainActor
struct YouTubeAdScriptTests {
    private func pageWithAd() -> FakePage {
        let page = FakePage("player.classList.add('ad-showing'); video.duration = 30; video.currentTime = 2;")
        page.eval("var skip = { clicks: 0, click() { this.clicks++; } }; player.querySelector = sel => sel === 'video' ? video : skip;")
        page.eval(Blocklist.youtubeScript)
        page.eval("intervals.forEach(f => f());")
        return page
    }

    /// Jumping to the ad's end made YouTube interrupt playback and close PiP every few minutes.
    @Test func adsPlayToTheEnd() {
        let page = pageWithAd()
        #expect(page.eval("video.currentTime").toDouble() == 2)
        #expect(page.eval("skip.clicks").toInt32() == 0)
    }

    @Test func adsAreMutedAndUnmutedAfter() {
        let page = pageWithAd()
        #expect(page.eval("video.muted").toBool())
        page.eval("player.classList.delete('ad-showing'); intervals.forEach(f => f());")
        #expect(page.eval("video.muted").toBool() == false)
    }

    @Test func leavesYourOwnMuteAlone() {
        let page = FakePage("video.muted = true; player.classList.add('ad-showing');")
        page.eval(Blocklist.youtubeScript)
        page.eval("intervals.forEach(f => f()); player.classList.delete('ad-showing'); intervals.forEach(f => f());")
        #expect(page.eval("video.muted").toBool())
    }
}

@MainActor
struct VideoTabSleepTests {
    private func isActive(_ setup: String) -> Bool? {
        FakePage(setup).run("return \(BrowserWindowController.videoActiveScript)").map { $0 == "true" }
    }

    @Test func playingVideoKeepsTabAwake() { #expect(isActive("video.paused = false;") == true) }
    @Test func floatingPausedVideoKeepsTabAwake() {
        #expect(isActive("video.paused = true; video.webkitPresentationMode = 'picture-in-picture';") == true)
    }
    @Test func pausedVideoLetsTabSleep() { #expect(isActive("video.paused = true;") == false) }
}

struct MemoryPreferenceTests {
    /// Auto-increasing timer throttling stretched hidden pages' timers to minutes and stalled
    /// video floating in PiP over another app.
    @Test func noAutoIncreasingTimerThrottling() {
        let keys = BrowserWindowController.memoryPreferences.map(\.0)
        #expect(!keys.contains("hiddenPageDOMTimerThrottlingAutoIncreases"))
        #expect(keys.contains("hiddenPageDOMTimerThrottlingEnabled"))
    }
}
