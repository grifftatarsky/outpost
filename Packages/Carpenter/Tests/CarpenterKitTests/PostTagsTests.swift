import Foundation
import Testing

@testable import CarpenterKit
@testable import CarpenterUI

@Suite struct PostTagsTests {
    @Test("A tag is found where a person would see one")
    func basics() {
        #expect(PostTags.tags(in: "expectations for #Doomsday are managed") == ["Doomsday"])
        #expect(PostTags.tags(in: "#lead and #trail") == ["lead", "trail"])
        #expect(PostTags.tags(in: "(#parens), #comma, end #stop.") == ["parens", "comma", "stop"])
    }

    @Test("Not everything with a hash is a tag")
    func boundaries() {
        #expect(PostTags.tags(in: "issue#4 is out").isEmpty)
        #expect(PostTags.tags(in: "just a # alone").isEmpty)
        #expect(PostTags.tags(in: "wait ##what").isEmpty)
    }

    @Test("Tags are distinct by case-insensitive identity, keeping the author's casing")
    func distinctness() {
        #expect(PostTags.tags(in: "#Doomsday then #doomsday then #DOOMSDAY") == ["Doomsday"])
        #expect(PostTags.text("all in on #DOOMSDAY", has: "doomsday"))
    }

    @Test("The index points every tag at every post that carries it, and only those")
    func indexing() {
        let posts = [
            post(1, "#Doomsday hopes"),
            post(2, "no tags here"),
            post(3, "double up #Doomsday #animationsupremacy"),
        ]
        let index = PostTags.index(of: posts)
        #expect(index["doomsday"] == [posts[0].id, posts[2].id])
        #expect(index["animationsupremacy"] == [posts[2].id])
        #expect(index.count == 2)
    }

    private func post(_ seed: UInt8, _ body: String) -> OutpostPost {
        OutpostPost(
            id: PostID(entry: EntryHash(rawValue: Data(repeating: seed, count: 32))),
            author: Member(id: Identity.generate().id, displayName: "A"),
            body: body, postedAt: .now, commentCount: 0)
    }
}

@MainActor
@Suite struct DemoOutpostTests {
    @Test("The scripted feed is coherent: distinct ids, newest first, threads that add up")
    func coherent() {
        let posts = CarpenterUI.DemoOutpost.posts()
        #expect(Set(posts.map(\.id)).count == posts.count)
        let dates = posts.map(\.postedAt)
        #expect(dates == dates.sorted(by: >))
        for post in posts {
            #expect(post.commentCount == post.previewComments.count)
        }
    }

    @Test("The argument happens under the tag, so the filter finds the whole thing")
    func tagged() {
        let posts = CarpenterUI.DemoOutpost.posts()
        let tagged = posts.filter { PostTags.text($0.body, has: "doomsday") }
        #expect(tagged.count == posts.count, "every post is part of the #Doomsday conversation")
    }
}
