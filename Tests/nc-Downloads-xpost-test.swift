// notchcast-sources: Tinycast/Features/Downloads/Webpage/*.swift
// notchcast-sources: Tinycast/Features/Downloads/Model/*.swift
// notchcast-sources: Tinycast/Features/Downloads/Service/*.swift
// notchcast-sources: Tinycast/Platform/AppPaths.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
import Foundation

@main
@MainActor
struct DownloadsXPostTests {
    static var passes = 0
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() { passes += 1 } else { failures += 1; print("FAIL: \(message)") }
    }

    static let articleJSON = #"""
    {"tweet":{"id":"2118723940638138486","url":"https://x.com/ryangrowthh/status/2118723940638138486","created_timestamp":1793978126,
    "text":"https://x.com/i/article/2118504468342018048",
    "author":{"name":"Ryan","screen_name":"ryangrowthh"},
    "article":{"title":"𝕏 Copywriting Masterclass (Dense Guide)","content":{"blocks":[
    {"entityRanges":[],"inlineStyleRanges":[],
    "text":"Nail this, and you'll never struggle with 𝕏 growth ever again.  ","type":"unstyled"},
    {"entityRanges":[{"key":0,"length":1,"offset":0}],"inlineStyleRanges":[],
    "text":" ","type":"atomic"},
    {"entityRanges":[],"inlineStyleRanges":[],
    "text":"If you find this valuable at the end, follow me ","type":"ordered-list-item"},
    {"entityRanges":[],"inlineStyleRanges":[],
    "text":"Repost/Like this article so others can see it ","type":"ordered-list-item"},
    {"entityRanges":[],"inlineStyleRanges":[{"length":20,"offset":0,"style":"Bold"}],
    "text":"Today's masterclass:","type":"unstyled"},
    {"entityRanges":[],"inlineStyleRanges":[{"length":13,"offset":0,"style":"Bold"}],
    "text":"Fundamentals ","type":"unordered-list-item"},
    {"entityRanges":[],"inlineStyleRanges":[{"length":9,"offset":0,"style":"Bold"}],
    "text":"Hooks 101","type":"unordered-list-item"},
    {"entityRanges":[{"key":1,"length":1,"offset":0}],"inlineStyleRanges":[],
    "text":" ","type":"atomic"},
    {"entityRanges":[],"inlineStyleRanges":[{"length":1,"offset":0,"style":"Bold"}],
    "text":" Fundamentals","type":"header-two"},
    {"entityRanges":[{"key":5,"length":1,"offset":0}],"inlineStyleRanges":[],
    "text":" ","type":"atomic"},
    {"entityRanges":[{"key":7,"length":1,"offset":0}],"inlineStyleRanges":[],
    "text":" ","type":"atomic"},
    {"entityRanges":[],"inlineStyleRanges":[{"length":17,"offset":0,"style":"Bold"}],
    "text":"Use line breaks. Walls of text get skipped. ","type":"blockquote"},
    {"entityRanges":[{"key":9,"length":5,"offset":9}],"inlineStyleRanges":[{"length":4,"offset":0,"style":"Italic"}],
    "text":"Read the guide now","type":"unstyled"},
    {"entityRanges":[],"inlineStyleRanges":[],
    "text":"Kept text","type":"future-block"}],
    "entityMap":[{"key":"5","value":{"data":{"markdown":"```\n\nHooks by format\n\nShort posts   → The hook IS the post.\n```"},
    "type":"MARKDOWN"}},{"key":"1","value":{"data":{},"type":"DIVIDER"}},
    {"key":"0","value":{"data":{"caption":"deciding to go viral ","mediaItems":[{"localMediaId":"2",
    "mediaCategory":"DraftTweetImage","mediaId":"2118511904545218560"}]},"type":"MEDIA"}},
    {"key":"7","value":{"data":{"tweetId":"2109282873391956203"},"type":"TWEET"}},
    {"key":"9","value":{"data":{"url":"https://example.com/guide"},"type":"LINK"}}]},
    "media_entities":[{"media_id":"2118511904545218560",
    "media_info":{"original_img_url":"https://pbs.twimg.com/media/HWZ3WlLaoAACHkR.jpg"}}]}}}
    """#

    static let postJSON = #"""
    {"code":200,"tweet":{"id":"2118073132850299089","url":"https://x.com/przemekwilde/status/2118073132850299089","created_timestamp":1793822961,
    "author":{"name":"Przemysław Wilde","screen_name":"przemekwilde"},
    "text":"W jaki sposób ogarnąłem @OpenBot_ na VPS? Poniżej odpowiedź dla osób, które mnie o to pytają.",
    "media":{"all":[
    {"type":"photo","url":"https://pbs.twimg.com/media/HWTn1JgWwAEPr_9.jpg?name=orig"},
    {"type":"video","url":"https://video.twimg.com/clip.mp4"}]},
    "quote":{"text":"Quoted <post>\n\nSecond.\nThird.","url":"https://x.com/someone/status/1","author":{"name":"Someone"}}}}
    """#

    static func main() async throws {
        addresses()
        articles()
        posts()
        try await fetching()
        if let directory = ProcessInfo.processInfo.environment["TINYCAST_XPOST_LIVE_DIRECTORY"] {
            try await live(URL(filePath: directory, directoryHint: .isDirectory))
        }
        print("downloads-xpost: \(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func addresses() {
        for (value, api) in [
            ("https://x.com/aiedge_/article/2118005624479052232", "aiedge_/status/2118005624479052232"),
            ("https://x.com/przemekwilde/status/2118073132850299089?s=20", "przemekwilde/status/2118073132850299089"),
            ("https://twitter.com/Some_User/status/1/photo/1", "Some_User/status/1"),
            ("http://www.x.com/a/status/12", "a/status/12"),
            ("https://mobile.twitter.com/a/article/34", "a/status/34"),
            ("https://X.COM/a/status/5", "a/status/5"),
            ("https://x.com/I/status/20", "I/status/20")
        ] {
            expect(XPost.apiURL(URL(string: value)!)?.absoluteString == "https://api.fxtwitter.com/\(api)", "matches \(value)")
        }
        for value in ["https://x.com.evil.com/a/status/1", "https://evilx.com/a/status/1", "https://notx.com/a/status/1",
                      "https://x.co/a/status/1", "https://example.com/a/status/1", "https://evil.com/x.com/a/status/1",
                      "https://x.com@evil.com/a/status/1", "https://api.x.com/a/status/1", "ftp://x.com/a/status/1",
                      "https://x.com/a/likes/1", "https://x.com/a/status/abc", "https://x.com/a/status",
                      "https://x.com/home", "https://x.com/far_too_long_handle/status/1",
                      "https://x.com/i/article/2118504468342018048", "https://x.com/I/article/1"] {
            expect(XPost.apiURL(URL(string: value)!) == nil, "refuses \(value)")
        }
    }

    static func articles() {
        let source = URL(string: "https://x.com/ryangrowthh/article/2118723940638138486")!
        guard let article = try? XPost.article(Data(articleJSON.utf8), source: source) else {
            return expect(false, "article fixture parses")
        }
        let text = article.markdown(saved: Date(timeIntervalSince1970: 0))
        expect(article.title == "𝕏 Copywriting Masterclass (Dense Guide)" && article.author == "Ryan",
               "article title and author")
        expect(text.contains("source: \"https://x.com/ryangrowthh/article/2118723940638138486\"\npublished: 2026-11-06\n"),
               "front matter keeps the X link and post date")
        expect(text.contains("# 𝕏 Copywriting Masterclass (Dense Guide)\n\nNail this, and you'll never struggle"),
               "title then body")
        expect(text.contains("![deciding to go viral](<https://pbs.twimg.com/media/HWZ3WlLaoAACHkR.jpg>)"), "image as remote link")
        expect(text.contains("1. If you find this valuable at the end, follow me\n2. Repost/Like"), "ordered list")
        expect(text.contains("**Today's masterclass:**"), "bold paragraph")
        expect(text.contains("- **Fundamentals**\n- **Hooks 101**"), "unordered list with bold")
        expect(text.contains("\n---\n\n### Fundamentals\n"), "divider and plain heading")
        expect(text.contains("```\nHooks by format\n\nShort posts   → The hook IS the post.\n```"), "markdown block as code")
        expect(text.contains("[https://x.com/i/status/2109282873391956203](<https://x.com/i/status/2109282873391956203>)"),
               "embedded post as link")
        expect(text.contains("> **Use line breaks.** Walls of text get skipped."), "blockquote keeps bold spacing")
        expect(text.contains("*Read* the [guide](<https://example.com/guide>) now"), "italic and link ranges")
        expect(text.contains("\nKept text\n"), "unknown block keeps its text")
        expect(article.filename == "Ryan - 𝕏 Copywriting Masterclass (Dense Guide)", "article filename")
    }

    static func posts() {
        let source = URL(string: "https://x.com/przemekwilde/status/2118073132850299089")!
        guard let post = try? XPost.article(Data(postJSON.utf8), source: source) else {
            return expect(false, "post fixture parses")
        }
        let text = post.markdown(saved: .now)
        expect(post.author == "Przemysław Wilde", "post author is the display name")
        expect(post.title == "W jaki sposób ogarnąłem @OpenBot_ na VPS? Poniżej odpowiedź dla osób, które…",
               "post title is the first line cut at a word")
        expect(post.filename.hasPrefix("Przemysław Wilde - W jaki sposób ogarnąłem @OpenBot_ na VPS"), "post filename")
        expect(text.contains("published: 2026-11-04\n"), "post date")
        expect(text.contains("> Quoted \\<post\\>\n> \n") && text.contains("> Second.  \n> Third."),
               "quoted text keeps paragraphs and line breaks")
        expect(text.contains("![](<https://pbs.twimg.com/media/HWTn1JgWwAEPr_9.jpg?name=orig>)"), "photo link")
        expect(text.contains("[https://video.twimg.com/clip.mp4](<https://video.twimg.com/clip.mp4>)"), "video link")
        expect(text.contains("pytają.\n\n![](<https://pbs.twimg.com"), "full text then media")
        expect(text.contains("> [Someone](<https://x.com/someone/status/1>)"), "quoted post author link")
        let long = XPost.Tweet(id: "9", text: String(repeating: "a", count: 120), createdTimestamp: nil, author: nil,
                               article: nil, media: nil, quote: nil)
        expect(XPost.title(of: long) == String(repeating: "a", count: 80) + "…", "unbroken title capped at 80")
        let empty = XPost.Tweet(id: "9", text: " \n", createdTimestamp: nil, author: nil, article: nil, media: nil, quote: nil)
        expect(XPost.title(of: empty) == "Post 9", "media-only post still gets a title")
    }

    static func fetching() async throws {
        let source = URL(string: "https://x.com/przemekwilde/status/2118073132850299089")!
        let api = XPost.apiURL(source)!
        func respond(_ status: Int, _ body: String) -> XPost.Loader {
            { request in
                precondition(request.url == api && request.timeoutInterval == 20)
                return (Data(body.utf8), HTTPURLResponse(url: api, statusCode: status, httpVersion: nil, headerFields: nil)!)
            }
        }
        let post = try await XPost.fetch(source, from: api, load: respond(200, postJSON))
        expect(post.author == "Przemysław Wilde" && post.source == source, "fetch builds the post")
        let missing = "X returned no readable post for this link."
        for (status, body, expected) in [(404, "{}", missing), (200, #"{"code":404,"message":"NOT_FOUND"}"#, missing),
                                         (200, "not json", missing), (200, #"{"tweet":{}}"#, missing),
                                         (200, #"{"tweet":{"id":"1","article":{"title":"T","content":{}}}}"#, missing),
                                         (500, "{}", "X returned HTTP status 500 for this post.")] {
            do {
                _ = try await XPost.fetch(source, from: api, load: respond(status, body))
                expect(false, "fetch \(status) throws")
            } catch let error as XPost.Failure {
                expect(error.localizedDescription == expected, "fetch \(status) \(body): \(error.localizedDescription)")
            }
        }
    }

    static func live(_ directory: URL) async throws {
        let saver = WebpageSaver(destination: directory)
        for value in ["https://x.com/aiedge_/article/2118005624479052232", "https://x.com/thedankoe/article/2117664712532123680",
                      "https://x.com/ryangrowthh/article/2118723940638138486", "https://x.com/marfinxx/article/2118313633381745064",
                      "https://x.com/przemekwilde/status/2118073132850299089"] {
            let output = try await saver.save(URL(string: value)!)
            expect(FileManager.default.fileExists(atPath: output.path), "live saved \(value)")
            print("LIVE \(output.lastPathComponent)")
        }
    }
}
