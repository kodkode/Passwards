import Testing
@testable import PasswardsOrchestration

/// Smoke test that the new target builds and links. Real behavioral tests for
/// `filteredSorted` / `reconcileOverview` land once the extraction is done.
@Suite struct PlatformServicesSmokeTests {
    @Test func moduleLinks() {
        // A trivial in-memory conformance proves the protocol seams compile.
        final class NoopPasteboard: PasteboardService, @unchecked Sendable {
            func copy(_ value: String, concealed: Bool) {}
            func clearSecret() {}
        }
        let pb: any PasteboardService = NoopPasteboard()
        pb.copy("x", concealed: true)
        pb.clearSecret()
        #expect(Bool(true))
    }
}
