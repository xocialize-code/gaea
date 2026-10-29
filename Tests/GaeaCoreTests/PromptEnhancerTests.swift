import GaeaProtocol
import PixelAgencyNormalizer
import Testing
@testable import GaeaCore

/// Gaea's copy of prompt-enhance-kit's decision (`PromptEnhancer.decision`, 0.7.0), over the facts a plugin lists: the
/// cases the kit's own tests pin.
@Suite struct PromptEnhancerTests {
    static func facts(_ policy: PluginManifest.PromptProfile.Policy, words: Int? = 60, structured: Bool = false) -> PluginManifest.PromptProfile {
        PluginManifest.PromptProfile(id: "p", version: 1, title: "P", models: ["m"], policy: policy, tasks: ["textToImage"],
                                     structured: false, suggestsSize: false, laysOutCanvas: false, large: false,
                                     passThroughStructured: structured, detailedAtWords: words)
    }

    @Test func autoFollowsThePolicyAndTheDetailedLength() {
        let short = "a fox in the snow"
        let long = Array(repeating: "word", count: 60).joined(separator: " ")
        #expect(GaeaPromptEnhancer.decision(short, facts: Self.facts(.recommended), task: .textToImage, always: false) == nil)
        #expect(GaeaPromptEnhancer.decision(long, facts: Self.facts(.recommended), task: .textToImage, always: false) == .passedThrough)
        #expect(GaeaPromptEnhancer.decision(short, facts: Self.facts(.optional), task: .textToImage, always: false) == .notRecommended)
        #expect(GaeaPromptEnhancer.decision(long, facts: Self.facts(.required), task: .textToImage, always: false) == nil)
    }

    @Test func alwaysStillRespectsTasksVisionAndStructuredPrompts() {
        #expect(GaeaPromptEnhancer.decision("x", facts: Self.facts(.optional), task: .textToImage, always: true) == nil)
        #expect(GaeaPromptEnhancer.decision("x", facts: Self.facts(.optional), task: .imageEdit, always: true) == .noInstruction)
        let json = #"{"subjects": []}"#
        #expect(GaeaPromptEnhancer.decision(json, facts: Self.facts(.recommended, structured: true), task: .textToImage,
                                            always: true) == .passedThrough)
        #expect(GaeaPromptEnhancer.decision(json, facts: Self.facts(.recommended), task: .textToImage, always: true) == nil)
    }

    @Test func wordsCountIdeographsTwoToAWord() {
        #expect(GaeaPromptEnhancer.wordCount("a red fox") == 3)
        #expect(GaeaPromptEnhancer.wordCount("一只红狐狸") == 3)
        #expect(GaeaPromptEnhancer.wordCount("a fox 狐狸") == 3)
    }
}
