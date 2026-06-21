import Testing
import Foundation
@testable import PasswardsCore

/// Backward/forward decode compatibility for the model types — old encrypted
/// blobs and synced records must keep decoding, and unknown raw values must be
/// preserved instead of making an item fail to decode and vanish from the list.
@Suite("Model compatibility")
struct CompatTests {
    // Disambiguate from the Objective-C runtime's `Category` typedef.
    private typealias Category = PasswardsCore.Category

    private func json(_ value: some Encodable) throws -> Data {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        return try e.encode(value)
    }
    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try d.decode(type, from: data)
    }

    /// Wrapper so single-value enums are encoded inside a JSON object (avoids
    /// top-level-fragment encoding questions and mirrors how they appear in a
    /// real blob: as a field value).
    private struct Box<T: Codable & Equatable>: Codable, Equatable { var v: T }

    @Test("An icon-less ItemOverview blob (pre-icon fields) decodes with nil icons")
    func iconLessOverviewDecodes() throws {
        // Exactly the fields an overview had before iconSymbol/iconColor existed.
        let legacy = Data("""
        {"title":"GitHub","subtitle":"michael","urls":["https://github.com"],
         "tags":[],"isFavorite":false,"isArchived":false,"category":"login",
         "hasOTP":false,"watchtowerExclusions":[]}
        """.utf8)
        let overview = try decode(ItemOverview.self, legacy)
        #expect(overview.iconSymbol == nil)
        #expect(overview.iconColor == nil)
        #expect(overview.category == .login)
        #expect(overview.title == "GitHub")
        #expect(overview.strengthBucket == nil)
    }

    @Test("FieldKind round-trips, preserving unknown raw values")
    func fieldKindUnknownRoundTrips() throws {
        for kind: FieldKind in [.text, .concealed, .otp, .unknown("passkey"), .unknown("futureKind")] {
            #expect(try decode(Box<FieldKind>.self, json(Box(v: kind))).v == kind)
        }
    }

    @Test("An unknown category raw value decodes to .unknown instead of throwing")
    func unknownCategoryDecodes() throws {
        let data = Data(#"{"v":"passkeyVault"}"#.utf8)
        let decoded = try decode(Box<Category>.self, data).v
        #expect(decoded == .unknown("passkeyVault"))
        // ...and round-trips back to the same raw value (lossless).
        #expect(try decode(Box<Category>.self, json(Box(v: decoded))).v == .unknown("passkeyVault"))
    }

    @Test("Known categories still encode as the same bare string (wire format unchanged)")
    func knownCategoryWireFormatUnchanged() throws {
        #expect(try json(Box(v: Category.login)) == Data(#"{"v":"login"}"#.utf8))
        #expect(try json(Box(v: Category.sshKey)) == Data(#"{"v":"sshKey"}"#.utf8))
        #expect(Category.allCases.count == 22)
        #expect(!Category.allCases.contains(.unknown("x")))
        // Every known category round-trips.
        for category in Category.allCases {
            #expect(try decode(Box<Category>.self, json(Box(v: category))).v == category)
        }
    }

    @Test("An item carrying an unknown category survives decode (doesn't vanish)")
    func itemWithUnknownCategoryDecodes() throws {
        let overview = ItemOverview(title: "Future", category: .unknown("passkeyVault"))
        let restored = try decode(ItemOverview.self, json(overview))
        #expect(restored.category == .unknown("passkeyVault"))
        #expect(restored.title == "Future")
    }
}
