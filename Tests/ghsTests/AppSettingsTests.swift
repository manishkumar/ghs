import Foundation
import Testing
@testable import ghs

/// These exercise the setters that crashed the app. Clamping used to live in
/// `didSet` and assign to its own property, which recurses forever under
/// `@Observable`. A regression crashes the test runner rather than failing an
/// assertion — signal enough.
@Suite struct AppSettingsTests {
    private func makeSettings() -> AppSettings {
        AppSettings(defaults: UserDefaults(suiteName: "ghs.tests.\(UUID().uuidString)")!)
    }

    @Test func acceptsEveryIntervalOfferedInSettings() {
        let settings = makeSettings()
        for interval in [60.0, 120.0, 300.0, 900.0] {
            settings.pollInterval = interval
            #expect(settings.pollInterval == interval)
        }
    }

    @Test func clampsIntervalToTheMinimum() {
        let settings = makeSettings()
        settings.pollInterval = 5
        #expect(settings.pollInterval == AppSettings.minimumInterval)
    }

    @Test func persistsInterval() {
        let defaults = UserDefaults(suiteName: "ghs.tests.\(UUID().uuidString)")!
        AppSettings(defaults: defaults).pollInterval = 900
        #expect(AppSettings(defaults: defaults).pollInterval == 900)
    }

    @Test func repeatedAssignmentDoesNotRecurse() {
        let settings = makeSettings()
        for _ in 0..<500 {
            settings.pollInterval = 900
            settings.urgentAfterDays = 14
        }
        #expect(settings.pollInterval == 900)
        #expect(settings.urgentAfterDays == 14)
    }

    @Test func clampsUrgencyAtBothEnds() {
        let settings = makeSettings()
        settings.urgentAfterDays = 0
        #expect(settings.urgentAfterDays == 1)
        settings.urgentAfterDays = 10_000
        #expect(settings.urgentAfterDays == 365)
    }

    @Test func reposRoundTripThroughDefaults() {
        let defaults = UserDefaults(suiteName: "ghs.tests.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        #expect(settings.addRepo("cli/cli"))
        #expect(settings.addRepo("https://github.com/sharkdp/bat"))
        #expect(AppSettings(defaults: defaults).repos.map(\.nameWithOwner) == ["cli/cli", "sharkdp/bat"])
    }

    @Test func ignoresDuplicatesAndRejectsJunk() {
        let settings = makeSettings()
        #expect(settings.addRepo("cli/cli"))
        #expect(settings.addRepo("cli/cli"))
        #expect(settings.repos.count == 1)
        #expect(!settings.addRepo("not-a-repo"))
        #expect(!settings.addRepo(""))
    }

    @Test func includesUnreviewedByDefaultAndPersistsTheChoice() {
        let defaults = UserDefaults(suiteName: "ghs.tests.\(UUID().uuidString)")!
        #expect(AppSettings(defaults: defaults).includeUnreviewed)
        AppSettings(defaults: defaults).includeUnreviewed = false
        #expect(!AppSettings(defaults: defaults).includeUnreviewed)
    }

    @Test func removesRepos() {
        let settings = makeSettings()
        settings.addRepo("cli/cli")
        settings.addRepo("sharkdp/bat")
        settings.removeRepos(["cli/cli"])
        #expect(settings.repos.map(\.nameWithOwner) == ["sharkdp/bat"])
    }
}
