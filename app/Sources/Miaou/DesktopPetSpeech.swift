import AppKit

struct DesktopPetMessage: Equatable {
    let sessionID: String
    let title: String?
    let text: String
    let completedAt: TimeInterval
    let sequence: Int
}

/// A completion is shown once, for five seconds measured by the animation clock.
struct DesktopPetSpeechPresentation {
    static let duration: TimeInterval = 5
    private var seen: [String: Int] = [:]
    private var message: DesktopPetMessage?
    private var expiresAt: TimeInterval = 0

    mutating func receive(_ value: DesktopPetMessage?, at time: TimeInterval) {
        guard let value, value.sequence > (seen[value.sessionID] ?? -1) else { return }
        seen[value.sessionID] = value.sequence
        message = value
        expiresAt = time + Self.duration
    }

    mutating func visibleMessage(at time: TimeInterval, activeIDs: Set<String>) -> DesktopPetMessage? {
        guard let message else { return nil }
        guard time < expiresAt, activeIDs.contains(message.sessionID) else {
            self.message = nil
            return nil
        }
        return message
    }

    mutating func hide() { message = nil }
}

/// Reads only the active sessions' append-only journals. Content stays in memory.
struct DesktopPetMessageReader {
    private struct Completion {
        let sequence: Int
        let text: String
    }

    private struct Journal {
        let modified: Date
        let size: Int
        let completion: Completion?
        let anchors: [(sequence: Int, time: TimeInterval)]
    }

    private var cache: [URL: Journal] = [:]

    mutating func latestMessage(sessions: [ActiveSessionReport], vibeHome: URL) -> DesktopPetMessage? {
        var usedFiles: Set<URL> = []
        var messages: [DesktopPetMessage] = []
        for session in sessions {
            guard !session.id.isEmpty, !session.id.contains("/"),
                  session.id != ".", session.id != ".." else { continue }
            let directory = vibeHome.appendingPathComponent("logs/session/unified")
                .appendingPathComponent(session.id).appendingPathComponent("journal")
            let files = (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil
            ))?.filter { $0.pathExtension == "jsonl" }.sorted { $0.path < $1.path } ?? []
            var journals: [Journal] = []
            for file in files {
                usedFiles.insert(file)
                if let journal = read(file) { journals.append(journal) }
            }
            guard let latest = journals.filter({ $0.completion != nil })
                .max(by: { $0.completion!.sequence < $1.completion!.sequence }),
                  let completion = latest.completion else { continue }
            let time = journals.flatMap(\.anchors)
                .filter { $0.sequence <= completion.sequence }
                .max { $0.sequence < $1.sequence }?.time ?? latest.modified.timeIntervalSince1970
            messages.append(DesktopPetMessage(
                sessionID: session.id, title: session.title, text: completion.text,
                completedAt: time, sequence: completion.sequence
            ))
        }
        cache = cache.filter { usedFiles.contains($0.key) }
        return messages.max {
            if $0.completedAt != $1.completedAt { return $0.completedAt < $1.completedAt }
            return $0.sessionID < $1.sessionID
        }
    }

    private mutating func read(_ file: URL) -> Journal? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              let modified = attributes[.modificationDate] as? Date,
              let size = attributes[.size] as? Int else { return nil }
        if let cached = cache[file], cached.modified == modified, cached.size == size { return cached }
        guard let data = try? Data(contentsOf: file) else { return nil }
        var completion: Completion?
        var anchors: [(sequence: Int, time: TimeInterval)] = []
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            guard let record = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                  let sequence = record["sequence"] as? Int,
                  let payload = record["payload"] as? [String: Any] else { continue }
            if record["type"] as? String == "core_input",
               let input = payload["input"] as? [String: Any],
               let determinism = input["determinism"] as? [String: Any],
               let ms = determinism["time_unix_ms"] as? Double {
                anchors.append((sequence, ms / 1_000))
            }
            guard record["type"] as? String == "action_result",
                  payload["state"] as? String == "succeeded",
                  let result = payload["result"] as? [String: Any],
                  result["type"] as? String == "completion_succeeded",
                  let answer = result["result"] as? [String: Any],
                  answer["finish_reason"] as? String == "stop",
                  let parts = answer["parts"] as? [[String: Any]] else { continue }
            let text = parts.filter { $0["type"] as? String == "text" }
                .compactMap { $0["text"] as? String }.joined(separator: "\n")
            let excerpt = Self.excerpt(text)
            if !excerpt.isEmpty && sequence > (completion?.sequence ?? -1) {
                completion = Completion(sequence: sequence, text: excerpt)
            }
        }
        let journal = Journal(modified: modified, size: size, completion: completion, anchors: anchors)
        cache[file] = journal
        return journal
    }

    static func excerpt(_ text: String, limit: Int = 280) -> String {
        let lines = text.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }
            .map { $0.replacingOccurrences(of: #"^\s*(?:#{1,6}\s+|[-*+]\s+|>\s+)"#,
                                         with: "", options: .regularExpression) }
        var plain = lines.joined(separator: " ")
            .replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
        for marker in ["**", "__", "`"] { plain = plain.replacingOccurrences(of: marker, with: "") }
        plain = plain.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard plain.count > limit else { return plain }
        var shortened = String(plain.prefix(max(0, limit - 1)))
        if let space = shortened.lastIndex(of: " ") { shortened = String(shortened[..<space]) }
        return shortened + "…"
    }
}

/// Serial background reads never block animation or overlap each other.
final class DesktopPetSpeechSource {
    private let queue = DispatchQueue(label: "miaou.desktop-speech", qos: .utility)
    private var reader = DesktopPetMessageReader()
    private var reading = false

    func refresh(sessions: [ActiveSessionReport], receive: @escaping (DesktopPetMessage?) -> Void) {
        guard !sessions.isEmpty else { receive(nil); return }
        guard !reading else { return }
        reading = true
        let home = URL(fileURLWithPath: ProcessInfo.processInfo.environment["VIBE_HOME"]
                       ?? NSHomeDirectory() + "/.vibe")
        queue.async { [weak self] in
            guard let self else { return }
            let message = self.reader.latestMessage(sessions: sessions, vibeHome: home)
            DispatchQueue.main.async {
                self.reading = false
                receive(message)
            }
        }
    }
}

final class DesktopPetSpeechView: NSView {
    static let height: CGFloat = 142
    private let glass = DesktopPetGlass.makeView()
    private let mask = CAShapeLayer()
    private let outline = DesktopPetSpeechOutline()
    private let title = NSTextField(labelWithString: "")
    private let message = NSTextField(wrappingLabelWithString: "")
    private var shapeSize: CGSize = .zero
    private var shapeTail = -1
    var tailX: CGFloat = 160 { didSet { if tailX != oldValue { needsLayout = true } } }

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: Self.height))
        wantsLayer = true
        glass.frame = bounds
        glass.autoresizingMask = [.width, .height]
        glass.wantsLayer = true
        glass.layer?.mask = mask
        outline.frame = bounds
        outline.autoresizingMask = [.width, .height]
        title.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        title.textColor = .secondaryLabelColor
        title.lineBreakMode = .byTruncatingTail
        message.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        message.textColor = .labelColor
        message.maximumNumberOfLines = 5
        message.lineBreakMode = .byWordWrapping
        message.cell?.truncatesLastVisibleLine = true
        addSubview(glass)
        // The outline and text stay visible even at zero glass intensity.
        addSubview(outline)
        addSubview(title)
        addSubview(message)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(_ value: DesktopPetMessage, glassTransparency: Double = 0) {
        DesktopPetGlass.apply(transparency: glassTransparency, to: glass)
        let heading = value.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = heading?.isEmpty == false ? heading! : L10n.t("desktopPet.speech.session")
        if title.stringValue != text { title.stringValue = text }
        if message.stringValue != value.text { message.stringValue = value.text }
    }

    override func layout() {
        super.layout()
        title.frame = CGRect(x: 20, y: bounds.height - 33, width: bounds.width - 40, height: 17)
        message.frame = CGRect(x: 20, y: 30, width: bounds.width - 40, height: bounds.height - 68)
        let column = DesktopPetSpeechShape.tailColumn(for: bounds.size, at: tailX)
        guard shapeSize != bounds.size || shapeTail != column else { return }
        let shape = DesktopPetSpeechShape(size: bounds.size, tailX: tailX)
        shapeSize = bounds.size
        shapeTail = shape.tailColumn
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mask.frame = bounds
        mask.path = shape.glass
        CATransaction.commit()
        outline.dots = shape.dots
        outline.needsDisplay = true
    }

    static func frame(above cat: CGRect, within screen: CGRect) -> CGRect {
        let area = screen.insetBy(dx: min(8, screen.width / 4), dy: 0)
        let width = min(320, area.width)
        let height = min(Self.height, area.height)
        return CGRect(
            x: min(max(cat.midX - width / 2, area.minX), area.maxX - width),
            y: min(max(cat.maxY + 6, area.minY), area.maxY - height),
            width: width, height: height
        )
    }
}

/// Square dots use the same 85%-filled cells and five color bands as the pet.
private struct DesktopPetSpeechShape {
    static let pitch: CGFloat = 8
    let tailColumn: Int
    let glass: CGPath
    let dots: [(rect: CGRect, band: Int)]

    static func tailColumn(for size: CGSize, at x: CGFloat) -> Int {
        let columns = max(11, Int(size.width / pitch))
        let originX = (size.width - CGFloat(columns) * pitch) / 2
        return min(max(Int(((x - originX) / pitch - 0.5).rounded()), 4), columns - 5)
    }

    init(size: CGSize, tailX: CGFloat) {
        let columns = max(11, Int(size.width / Self.pitch))
        let rows = max(8, Int(size.height / Self.pitch))
        let origin = CGPoint(x: (size.width - CGFloat(columns) * Self.pitch) / 2,
                             y: (size.height - CGFloat(rows) * Self.pitch) / 2)
        let tail = Self.tailColumn(for: size, at: tailX)
        tailColumn = tail
        let spans = (0..<rows).map { row -> ClosedRange<Int> in
            if row < 2 { return (tail - row)...(tail + row) }
            let inset = max(0, 2 - min(row - 2, rows - 1 - row))
            return inset...(columns - 1 - inset)
        }
        let path = CGMutablePath()
        var border: [(rect: CGRect, band: Int)] = []
        for (row, span) in spans.enumerated() {
            let y = origin.y + CGFloat(row) * Self.pitch
            path.addRect(CGRect(x: origin.x + CGFloat(span.lowerBound) * Self.pitch,
                                y: y, width: CGFloat(span.count) * Self.pitch,
                                height: Self.pitch))
            for col in span {
                guard col == span.lowerBound || col == span.upperBound ||
                        row == 0 || row == rows - 1 ||
                        !spans[row - 1].contains(col) || !spans[row + 1].contains(col) else { continue }
                let cell = CGRect(x: origin.x + CGFloat(col) * Self.pitch, y: y,
                                  width: Self.pitch, height: Self.pitch)
                border.append((cell.insetBy(dx: Self.pitch * 0.075, dy: Self.pitch * 0.075),
                               min(4, (rows - 1 - row) * 5 / rows)))
            }
        }
        glass = path
        dots = border
    }
}

private final class DesktopPetSpeechOutline: NSView {
    var dots: [(rect: CGRect, band: Int)] = []
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setShouldAntialias(false)
        for dot in dots {
            context.setFillColor(MistralLogo.brand[dot.band].cgColor)
            context.fill(dot.rect)
        }
    }
}
