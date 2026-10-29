import Foundation
import Testing
@testable import Feather

struct VideoToolsTests {
    private let base = URL(string: "https://cdn.example.com/video/master.m3u8")!

    // MARK: - HLS

    @Test func testMasterPlaylistPicksBestMuxedVariant() {
        let text = """
        #EXTM3U
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="English",URI="audio/en.m3u8"
        #EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360
        low/index.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=2500000,RESOLUTION=1280x720
        https://other.example.com/mid.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=6000000,RESOLUTION=1920x1080,AUDIO="aud"
        high/index.m3u8
        """
        guard case .master(let variants) = HLS.parse(text, base: base) else { Issue.record("not a master"); return }
        #expect(variants.count == 3)
        #expect(variants[0].url.absoluteString == "https://cdn.example.com/video/low/index.m3u8")
        #expect(variants[2].separateAudio)
        // The 1080p variant needs its separate audio, so the best one Feather can save is 720p.
        #expect(HLS.bestVariant(variants)?.url.absoluteString == "https://other.example.com/mid.m3u8")
    }

    @Test func testMediaPlaylist() {
        let text = """
        #EXTM3U
        #EXT-X-TARGETDURATION:4
        #EXT-X-MEDIA-SEQUENCE:12
        #EXT-X-MAP:URI="init.mp4"
        #EXTINF:4.0,
        seg12.m4s
        #EXTINF:4.0,
        seg13.m4s?token=abc
        #EXT-X-ENDLIST
        """
        guard case .media(let media) = HLS.parse(text, base: base) else { Issue.record("not media"); return }
        #expect(media.initSegment?.absoluteString == "https://cdn.example.com/video/init.mp4")
        #expect(media.segments.map(\.lastPathComponent) == ["seg12.m4s", "seg13.m4s"])
        #expect(media.segments[1].query == "token=abc")
        #expect(media.firstSequence == 12)
        #expect(media.targetDuration == 4)
        #expect(media.isFinished)
        #expect(!media.isEncrypted)
    }

    @Test func testEncryptedAndLivePlaylists() {
        let encrypted = "#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI=\"key.bin\"\n#EXTINF:6,\na.ts\n"
        guard case .media(let a) = HLS.parse(encrypted, base: base) else { Issue.record("not media"); return }
        #expect(a.isEncrypted)
        #expect(!a.isFinished) // no ENDLIST: a live stream
        let clear = "#EXTM3U\n#EXT-X-KEY:METHOD=NONE\n#EXTINF:6,\na.ts\n"
        guard case .media(let b) = HLS.parse(clear, base: base) else { Issue.record("not media"); return }
        #expect(!b.isEncrypted)
        #expect(HLS.parse("<html>", base: base) == nil)
    }

    @Test func testAttributes() {
        let line = #"#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aac,stereo",NAME="English",DEFAULT=YES"#
        #expect(HLS.attribute("TYPE", in: line) == "AUDIO")
        #expect(HLS.attribute("GROUP-ID", in: line) == "aac,stereo")
        #expect(HLS.attribute("DEFAULT", in: line) == "YES")
        #expect(HLS.attribute("URI", in: line) == nil)
    }

    // MARK: - Subtitles

    @Test func testParsesSRT() {
        let srt = "1\r\n00:00:01,500 --> 00:00:03,000\r\nHello\r\nthere\r\n\r\n2\r\n00:01:02,250 --> 01:00:00,000\r\n<i>Bye</i>\r\n"
        let cues = Subtitles.parse(srt)
        #expect(cues == [Subtitles.Cue(start: 1.5, end: 3, text: "Hello\nthere"),
                         Subtitles.Cue(start: 62.25, end: 3600, text: "<i>Bye</i>")])
    }

    @Test func testParsesVTT() {
        let vtt = "WEBVTT\n\nNOTE a comment\n\nintro\n00:05.000 --> 00:07.000 align:start position:10%\nHi\n"
        #expect(Subtitles.parse(vtt) == [Subtitles.Cue(start: 5, end: 7, text: "Hi")])
        #expect(Subtitles.parse("not subtitles").isEmpty)
    }

    // MARK: - Cookies for stream requests

    private func cookie(_ name: String, domain: String, path: String = "/", secure: Bool = false) -> HTTPCookie {
        var props: [HTTPCookiePropertyKey: Any] = [.name: name, .value: "v", .domain: domain, .path: path]
        if secure { props[.secure] = "TRUE" }
        return HTTPCookie(properties: props)!
    }

    @Test func testCookieHeaderMatchesDomainPathAndSecurity() {
        let cookies = [cookie("all", domain: ".example.com"), cookie("host", domain: "cdn.example.com"),
                       cookie("other", domain: "www.example.com"), cookie("deep", domain: ".example.com", path: "/private"),
                       cookie("secure", domain: ".example.com", secure: true)]
        let https = StreamDownloader.cookieHeader(for: URL(string: "https://cdn.example.com/video/a.ts")!, from: cookies)
        #expect(https == "all=v; host=v; secure=v")
        let http = StreamDownloader.cookieHeader(for: URL(string: "http://cdn.example.com/a.ts")!, from: cookies)
        #expect(http == "all=v; host=v")
        #expect(StreamDownloader.cookieHeader(for: URL(string: "https://elsewhere.com/")!, from: cookies) == nil)
    }

    @Test func testFilenameFromTitle() {
        #expect(StreamDownloader.filename("Trip: Day 1/2") == "Trip- Day 1-2")
        #expect(StreamDownloader.filename("  ") == "Video")
    }
}
