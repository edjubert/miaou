import AppKit
import XCTest
@testable import Miaou

final class DesktopPetSpeechTests: XCTestCase {
    private func record(_ sequence: Int, _ type: String, _ payload: [String: Any]) -> String {
        let object: [String: Any] = ["sequence": sequence, "type": type, "payload": payload]
        return String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
    }

    private func anchor(_ sequence: Int, _ ms: Int) -> String {
        record(sequence, "core_input", ["input": ["determinism": ["time_unix_ms": ms]]])
    }

    private func answer(_ sequence: Int, _ text: String, finish: String = "stop",
                        state: String = "succeeded", type: String = "completion_succeeded") -> String {
        record(sequence, "action_result", [
            "state": state,
            "result": ["type": type, "result": [
                "finish_reason": finish,
                "parts": [["type": "reasoning", "text": "Private reasoning"],
                          ["type": "text", "text": text]],
            ]],
        ])
    }

    private func home() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    @discardableResult
    private func write(_ home: URL, session: String, file: String = "0001", lines: [String]) throws -> URL {
        let directory = home.appendingPathComponent("logs/session/unified/\(session)/journal")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent(file + ".jsonl")
        try lines.joined(separator: "\n").write(to: path, atomically: true, encoding: .utf8)
        return path
    }

    private func message(_ session: String = "a", sequence: Int = 1) -> DesktopPetMessage {
        DesktopPetMessage(sessionID: session, title: "Session test",
                          text: "Les tests passent.", completedAt: 100, sequence: sequence)
    }

    func testReaderUsesOnlyCompletedTextFromActiveSessions() throws {
        let root = try home()
        try write(root, session: "a", lines: [
            anchor(1, 1_000), answer(2, "**Tests réussis.**"),
            answer(3, "Calling a tool", finish: "tool_calls"),
            answer(4, "Incomplete answer", finish: "length"),
            answer(5, "Failed answer", state: "failed"),
            answer(6, "Cancelled", type: "completion_failed"),
            #"{"sequence":7,"type":"action_result","payload":"unfinished"#,
        ])
        try write(root, session: "inactive", lines: [anchor(1, 9_000), answer(2, "Ignore this")])
        var reader = DesktopPetMessageReader()
        let result = try XCTUnwrap(reader.latestMessage(
            sessions: [ActiveSessionReport(id: "a", ageMs: 0, title: "Fix tests")], vibeHome: root
        ))
        XCTAssertEqual(result.text, "Tests réussis.")
        XCTAssertEqual(result.title, "Fix tests")
        XCTAssertEqual(result.sequence, 2)
        XCTAssertEqual(result.completedAt, 1)
        XCTAssertNil(reader.latestMessage(sessions: [], vibeHome: root))
    }

    func testNewestAnswerAcrossActiveSessionsUsesJournalTime() throws {
        let root = try home()
        try write(root, session: "a", lines: [anchor(90, 1_000), answer(100, "Older")])
        try write(root, session: "b", lines: [anchor(1, 2_000), answer(2, "Newer")])
        var reader = DesktopPetMessageReader()
        let sessions = [ActiveSessionReport(id: "a", ageMs: 0), ActiveSessionReport(id: "b", ageMs: 0)]
        XCTAssertEqual(reader.latestMessage(sessions: sessions, vibeHome: root)?.text, "Newer")
        XCTAssertEqual(reader.latestMessage(sessions: [sessions[0]], vibeHome: root)?.text, "Older")
    }

    func testSegmentsShareTimeAnchorsAndAnIncompleteNewFileKeepsTheLastAnswer() throws {
        let root = try home()
        try write(root, session: "a", file: "0001", lines: [anchor(1, 5_000)])
        try write(root, session: "a", file: "0002", lines: [answer(2, "Final answer")])
        try write(root, session: "a", file: "0003", lines: ["not JSON"])
        var reader = DesktopPetMessageReader()
        let result = reader.latestMessage(sessions: [ActiveSessionReport(id: "a", ageMs: 0)], vibeHome: root)
        XCTAssertEqual(result?.text, "Final answer")
        XCTAssertEqual(result?.completedAt, 5)
    }

    func testJournalAppendInvalidatesTheCacheAndPreservesThePreviousCompleteAnswer() throws {
        let root = try home()
        let path = try write(root, session: "a", lines: [anchor(1, 1_000), answer(2, "First")])
        let sessions = [ActiveSessionReport(id: "a", ageMs: 0)]
        var reader = DesktopPetMessageReader()
        XCTAssertEqual(reader.latestMessage(sessions: sessions, vibeHome: root)?.sequence, 2)
        let handle = try FileHandle(forWritingTo: path)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(("\n" + anchor(3, 2_000) + "\n" + answer(4, "Second") + "\n{").utf8))
        try handle.close()
        let result = reader.latestMessage(sessions: sessions, vibeHome: root)
        XCTAssertEqual(result?.text, "Second")
        XCTAssertEqual(result?.sequence, 4)
        XCTAssertEqual(result?.completedAt, 2)
    }

    func testUnreadableAndUnsafeSessionPathsProduceNoMessage() throws {
        var reader = DesktopPetMessageReader()
        let root = try home()
        let sessions = ["missing", "../other", "/", ".."].map { ActiveSessionReport(id: $0, ageMs: 0) }
        XCTAssertNil(reader.latestMessage(sessions: sessions, vibeHome: root))
    }

    func testExcerptRemovesMarkdownAndBoundsLongUnicodeText() {
        XCTAssertEqual(DesktopPetMessageReader.excerpt("""
        ## Terminé
        - **Tests réussis** : [voir le résultat](https://example.test).
        ```swift
        let result = true
        ```
        """), "Terminé Tests réussis : voir le résultat. let result = true")
        let text = DesktopPetMessageReader.excerpt(String(repeating: "🐈 résultat ", count: 100))
        XCTAssertLessThanOrEqual(text.count, 280)
        XCTAssertTrue(text.hasSuffix("…"))
    }

    func testFeatureMarkersYieldTheLabeledOutput() {
        let start = DesktopPetMessageReader.featureStart
        let end = DesktopPetMessageReader.featureEnd
        // Canonical double-underscore markers, as emitted by the harness.
        XCTAssertEqual(DesktopPetMessageReader.featureOutput("\(start)Mon nouveau titre\(end)"),
                       "Mon nouveau titre")
        // Any underscore count matches: bare and single-underscore variants.
        XCTAssertEqual(DesktopPetMessageReader.featureOutput("FEATURE_NAME_STARTMon titreFEATURE_NAME_END"),
                       "Mon titre")
        XCTAssertEqual(DesktopPetMessageReader.featureOutput("_FEATURE_NAME_START_Mon titre_FEATURE_NAME_END_"),
                       "Mon titre")
        XCTAssertEqual(DesktopPetMessageReader.featureOutput("\(start)\n<output>Mon titre</output>\n\(end)"),
                       "Mon titre")
        XCTAssertEqual(DesktopPetMessageReader.featureOutput("  \(start)  titre  \(end)  "),
                       "titre")
        // Markers wrapped in other tags: first START to last END, and longer
        // tags like __FEATURE_NAME_END_FOR_REAL__ never match.
        XCTAssertEqual(
            DesktopPetMessageReader.featureOutput(
                "__COMMIT_AND_EXPLAIN_PR_ERROR__wrong tag: no test__FEATURE_NAME_END_FOR_REAL__: " +
                "__FEATURE_NAME_START__PR #22 Last Message Check __FEATURE_NAME_END"),
            "PR #22 Last Message Check")
        // Not wrapped, empty, or only markers: no feature output.
        XCTAssertNil(DesktopPetMessageReader.featureOutput("titre sans marqueurs"))
        XCTAssertNil(DesktopPetMessageReader.featureOutput("\(start)\(end)"))
        XCTAssertNil(DesktopPetMessageReader.featureOutput("\(start)seulement le début"))
        XCTAssertNil(DesktopPetMessageReader.featureOutput("seulement la fin\(end)"))
        // displayText flags feature messages and yields the bare output;
        // normal messages go through the excerpt untouched.
        let feature = DesktopPetMessageReader.displayText("\(start)Mon nouveau titre\(end)")
        XCTAssertEqual(feature.text, "Mon nouveau titre")
        XCTAssertTrue(feature.feature)
        let normal = DesktopPetMessageReader.displayText("Bonjour le monde")
        XCTAssertEqual(normal.text, "Bonjour le monde")
        XCTAssertFalse(normal.feature)
    }

    func testFeatureCompletionIsFlaggedAndStrippedInTheReader() throws {
        let root = try home()
        try write(root, session: "a", lines: [
            anchor(1, 1_000),
            answer(2, "__FEATURE_NAME_START__Mon nouveau titre__FEATURE_NAME_END__"),
        ])
        var reader = DesktopPetMessageReader()
        let result = try XCTUnwrap(reader.latestMessage(
            sessions: [ActiveSessionReport(id: "a", ageMs: 0)], vibeHome: root))
        XCTAssertEqual(result.text, "Mon nouveau titre")
        XCTAssertTrue(result.feature)
    }

    func testFeatureMessageRendersSmallGrayLabelThenWhiteOutput() throws {
        let view = DesktopPetSpeechView()
        view.show(DesktopPetMessage(sessionID: "a", title: nil, text: "Mon nouveau titre",
                                   completedAt: 1, sequence: 1, feature: true))
        let field = try XCTUnwrap(view.subviews.compactMap { $0 as? NSTextField }.last)
        let attr = field.attributedStringValue
        // Label line, then a carriage return, then the output.
        let lines = attr.string.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].hasSuffix(":"))
        XCTAssertEqual(lines[1], "Mon nouveau titre")
        // The label is smaller and grayed; the body keeps the 13 pt white style.
        var labelFont: NSFont?
        var bodyFont: NSFont?
        var labelColor: NSColor?
        let full = NSRange(location: 0, length: attr.length)
        attr.enumerateAttribute(.font, in: full) { value, range, _ in
            guard let font = value as? NSFont else { return }
            if range.location == 0 { labelFont = font } else { bodyFont = font }
        }
        attr.enumerateAttribute(.foregroundColor, in: full) { value, range, _ in
            if range.location == 0, let color = value as? NSColor { labelColor = color }
        }
        XCTAssertEqual(try XCTUnwrap(labelFont).pointSize, 10)
        XCTAssertEqual(try XCTUnwrap(bodyFont).pointSize, 13)
        XCTAssertEqual(labelColor, .secondaryLabelColor)
        // A feature message hides the title line (it is just a title call).
        let titleField = try XCTUnwrap(view.subviews.compactMap { $0 as? NSTextField }.first)
        XCTAssertTrue(titleField.isHidden)
        XCTAssertEqual(titleField.font?.pointSize, 10)
        XCTAssertEqual(titleField.textColor, .secondaryLabelColor)
        // A normal message renders as plain body text, no label line, and
        // shows the "Vibe session" fallback title in the same small gray style.
        view.show(DesktopPetMessage(sessionID: "a", title: nil, text: "Bonjour",
                                   completedAt: 1, sequence: 2, feature: false))
        XCTAssertEqual(field.attributedStringValue.string, "Bonjour")
        XCTAssertFalse(titleField.isHidden)
        XCTAssertEqual(titleField.stringValue, L10n.t("desktopPet.speech.session"))
        XCTAssertEqual(titleField.font?.pointSize, 10)
    }

    func testMessageExpiresAtFiveSecondsAndRepeatedPollingDoesNotExtendIt() {
        var presentation = DesktopPetSpeechPresentation()
        presentation.receive(message(), at: 10)
        XCTAssertNotNil(presentation.visibleMessage(at: 14.999))
        presentation.receive(message(), at: 14)
        XCTAssertNil(presentation.visibleMessage(at: 15))
        presentation.receive(message(), at: 100)
        XCTAssertNil(presentation.visibleMessage(at: 100))
    }

    func testNewCompletionReplacesTheBubbleForAnotherFiveSeconds() {
        var presentation = DesktopPetSpeechPresentation()
        presentation.receive(message(), at: 10)
        presentation.receive(message(sequence: 2), at: 14)
        XCTAssertEqual(presentation.visibleMessage(at: 18.999)?.sequence, 2)
        XCTAssertNil(presentation.visibleMessage(at: 19))
    }

    func testEndingTheSessionDoesNotShortenTheFiveSecondBubble() {
        var sessions = DesktopPetSpeechSessions()
        var presentation = DesktopPetSpeechPresentation()
        _ = sessions.sessionsToRead(active: [ActiveSessionReport(id: "a", ageMs: 0)], at: 10)
        presentation.receive(message(), at: 10)
        _ = sessions.sessionsToRead(active: [], at: 12)
        XCTAssertNotNil(presentation.visibleMessage(at: 12))
        XCTAssertNotNil(presentation.visibleMessage(at: 14.999))
        XCTAssertNil(presentation.visibleMessage(at: 15))
    }

    func testDisablingTheOptionHidesWithoutReplayingOlderMessages() {
        var presentation = DesktopPetSpeechPresentation()
        presentation.receive(message(), at: 1)
        presentation.hide()
        presentation.receive(message(), at: 2)
        XCTAssertNil(presentation.visibleMessage(at: 2.1))
        presentation.receive(message("b"), at: 2)
        presentation.receive(message(), at: 3)
        XCTAssertEqual(presentation.visibleMessage(at: 3)?.sessionID, "b")
        presentation.hide()
        presentation.receive(message("b"), at: 4)
        XCTAssertNil(presentation.visibleMessage(at: 4))
    }

    func testFinalAnswerFlushedAfterSessionClosureIsStillShownForFiveSeconds() throws {
        let root = try home()
        try write(root, session: "a", lines: [anchor(1, 1_000)])
        var sessions = DesktopPetSpeechSessions()
        var reader = DesktopPetMessageReader()
        var presentation = DesktopPetSpeechPresentation()
        let active = [ActiveSessionReport(id: "a", ageMs: 0, title: "Ending Vibe")]
        XCTAssertTrue(reader.messages(sessions: sessions.sessionsToRead(active: active, at: 10),
                                      vibeHome: root).isEmpty)
        // The lease disappears before the completed answer reaches the journal.
        _ = sessions.sessionsToRead(active: [], at: 11)
        try write(root, session: "a", lines: [anchor(1, 1_000), answer(2, "Final answer")])
        let closing = sessions.sessionsToRead(active: [], at: 12)
        presentation.receive(reader.messages(sessions: closing, vibeHome: root), at: 12)
        XCTAssertEqual(presentation.visibleMessage(at: 16.999)?.text, "Final answer")
        XCTAssertNil(presentation.visibleMessage(at: 17))
    }

    func testClosingJournalReadsExpireAndDisablingClearsTrackedSessions() {
        var sessions = DesktopPetSpeechSessions()
        let active = [ActiveSessionReport(id: "a", ageMs: 0)]
        _ = sessions.sessionsToRead(active: active, at: 10)
        XCTAssertEqual(sessions.sessionsToRead(active: [], at: 19.999).map(\.id), ["a"])
        XCTAssertTrue(sessions.contains("a", at: 19.999))
        XCTAssertTrue(sessions.sessionsToRead(active: [], at: 20).isEmpty)
        XCTAssertFalse(sessions.contains("a", at: 20))
        _ = sessions.sessionsToRead(active: active, at: 21)
        sessions.reset()
        XCTAssertFalse(sessions.contains("a", at: 21))
    }

    func testAnAlreadyShownAnswerFromAnotherSessionCannotHideANewCompletion() throws {
        let root = try home()
        try write(root, session: "a", lines: [anchor(1, 1_000), answer(2, "Earlier answer")])
        try write(root, session: "b", lines: [anchor(1, 2_000), answer(2, "Other session")])
        let sessions = [ActiveSessionReport(id: "a", ageMs: 0), ActiveSessionReport(id: "b", ageMs: 0)]
        var reader = DesktopPetMessageReader()
        var presentation = DesktopPetSpeechPresentation()
        presentation.receive(reader.messages(sessions: sessions, vibeHome: root), at: 10)
        XCTAssertEqual(presentation.visibleMessage(at: 10)?.sessionID, "b")
        try write(root, session: "a", lines: [anchor(1, 1_000), answer(3, "New final answer")])
        presentation.receive(reader.messages(sessions: sessions, vibeHome: root), at: 12)
        XCTAssertEqual(presentation.visibleMessage(at: 12)?.text, "New final answer")
        presentation.receive(reader.messages(sessions: sessions, vibeHome: root), at: 16)
        XCTAssertNil(presentation.visibleMessage(at: 17))
    }

    func testBubbleStaysAboveAllPetSizesAndInsideBothScreenEdges() {
        let screen = CGRect(x: -800, y: 50, width: 800, height: 600)
        for size in DesktopPetSize.allCases {
            for pet in BarPet.allCases {
                let dimensions = size.dimensions(for: pet)
                for x in [screen.minX, screen.maxX - dimensions.width] {
                    let cat = CGRect(origin: CGPoint(x: x, y: 54), size: dimensions)
                    let bubble = DesktopPetSpeechView.frame(above: cat, within: screen)
                    XCTAssertTrue(screen.contains(bubble))
                    XCTAssertGreaterThan(bubble.minY, cat.maxY)
                    XCTAssertTrue((bubble.minX...bubble.maxX).contains(cat.midX))
                }
            }
        }
        let narrow = CGRect(x: 0, y: 0, width: 200, height: 100)
        XCTAssertTrue(narrow.contains(DesktopPetSpeechView.frame(above: .zero, within: narrow)))
    }

    func testBubbleRendersTextAndPointer() throws {
        let view = DesktopPetSpeechView()
        view.appearance = NSAppearance(named: .aqua)
        view.show(DesktopPetMessage(sessionID: "a", title: "Correction du widget",
                                   text: "Le widget et le chat sont restaurés. Les tests passent ; le réglage du verre est prêt.",
                                   completedAt: 1, sequence: 1))
        view.layoutSubtreeIfNeeded()
        for field in view.subviews.compactMap({ $0 as? NSTextField }) {
            XCTAssertTrue(view.bounds.contains(field.frame))
            XCTAssertTrue(try XCTUnwrap(field.font).fontDescriptor.symbolicTraits.contains(.monoSpace))
        }
        let glass = try XCTUnwrap(view.subviews.first)
        if #available(macOS 26.0, *) {
            XCTAssertTrue(glass is NSGlassEffectView)
        } else {
            XCTAssertTrue(glass is NSVisualEffectView)
        }
        let mask = try XCTUnwrap(glass.layer?.mask as? CAShapeLayer)
        XCTAssertTrue(try XCTUnwrap(mask.path).contains(CGPoint(x: 160, y: 4)))
        XCTAssertFalse(try XCTUnwrap(mask.path).contains(CGPoint(x: 4, y: 4)))
        view.tailX = 32
        view.layoutSubtreeIfNeeded()
        XCTAssertTrue(try XCTUnwrap(mask.path).contains(CGPoint(x: 36, y: 4)))
        XCTAssertFalse(try XCTUnwrap(mask.path).contains(CGPoint(x: 160, y: 4)))
        view.tailX = 160
        view.layoutSubtreeIfNeeded()
        view.show(message(), glassTransparency: 0.75)
        XCTAssertEqual(glass.alphaValue, 0.25)
        view.show(message(), glassTransparency: 1)
        XCTAssertTrue(glass.isHidden)
        XCTAssertFalse(view.subviews[1].isHidden)
        view.show(DesktopPetMessage(sessionID: "a", title: "Correction du widget",
                                   text: "Le widget et le chat sont restaurés. Les tests passent ; le réglage du verre est prêt.",
                                   completedAt: 1, sequence: 1))
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / view.bounds.width
        let topPixel = try XCTUnwrap(bitmap.colorAt(x: Int(164 * scale), y: Int(5 * scale))?
            .usingColorSpace(.deviceRGB))
        let bottomPixel = try XCTUnwrap(bitmap.colorAt(x: Int(164 * scale), y: Int(137 * scale))?
            .usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(topPixel.alphaComponent, 0.9)
        XCTAssertGreaterThan(bottomPixel.alphaComponent, 0.9)
        XCTAssertGreaterThan(topPixel.greenComponent, 0.8)
        XCTAssertGreaterThan(bottomPixel.redComponent, 0.8)
        XCTAssertLessThan(bottomPixel.greenComponent, 0.3)
        var wrappedText = false
        for y in Int(60 * scale)..<Int(110 * scale) {
            for x in Int(24 * scale)..<Int((view.bounds.width - 24) * scale) {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                   color.alphaComponent > 0.8 && color.redComponent < 0.6 {
                    wrappedText = true
                }
            }
        }
        XCTAssertTrue(wrappedText, "The message must render on more than one line.")
        if let path = ProcessInfo.processInfo.environment["MIAOU_SPEECH_PREVIEW"] {
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: path))
        }
    }

    func testBubbleDotsMatchTheCatDotMetrics() {
        let bubbleSize = CGSize(width: 320, height: DesktopPetSpeechView.height)
        for size in DesktopPetSize.allCases {
            for pet in BarPet.allCases {
                let dimensions = size.dimensions(for: pet)
                for scale in [CGFloat(0), 1, 2] {
                    let metrics = pet.dotMetrics(size: dimensions, scale: scale)
                    // The cat's own dots use the same cell and gap.
                    let catDots = pet == .chaton
                        ? Chaton.dotRects(frame: 0, size: dimensions, scale: scale)
                        : Chonk.dotRects(frame: 0, size: dimensions, scale: scale)
                    for dot in catDots {
                        XCTAssertEqual(dot.rect.width, metrics.cell - metrics.gap, accuracy: 0.001)
                    }
                    // The bubble's border dots use the same pitch and gap.
                    let shape = DesktopPetSpeechShape(size: bubbleSize, tailX: 160,
                                                      pitch: metrics.cell, gap: metrics.gap,
                                                      scale: scale)
                    XCTAssertFalse(shape.dots.isEmpty)
                    for dot in shape.dots {
                        XCTAssertEqual(dot.rect.width, metrics.cell - metrics.gap, accuracy: 0.001)
                        XCTAssertEqual(dot.rect.height, metrics.cell - metrics.gap, accuracy: 0.001)
                        XCTAssertTrue(CGRect(origin: .zero, size: bubbleSize).contains(dot.rect))
                    }
                }
            }
        }
    }
}
