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
        receive(value.map { [$0] } ?? [], at: time)
    }

    mutating func receive(_ values: [DesktopPetMessage], at time: TimeInterval) {
        let fresh = values.filter { $0.sequence > (seen[$0.sessionID] ?? -1) }
        guard let value = fresh.max(by: {
            if $0.completedAt != $1.completedAt { return $0.completedAt < $1.completedAt }
            return $0.sessionID < $1.sessionID
        }) else { return }
        // Consume the batch together so older answers cannot replay later.
        for answer in fresh { seen[answer.sessionID] = max(seen[answer.sessionID] ?? -1, answer.sequence) }
        message = value
        expiresAt = time + Self.duration
    }

    mutating func visibleMessage(at time: TimeInterval) -> DesktopPetMessage? {
        guard let message else { return nil }
        guard time < expiresAt else {
            self.message = nil
            return nil
        }
        return message
    }

    mutating func hide() { message = nil }
}

/// A closing session can flush its final answer just after releasing its lease.
struct DesktopPetSpeechSessions {
    static let closingGrace: TimeInterval = 10
    private struct Entry {
        let session: ActiveSessionReport
        let lastSeen: TimeInterval
    }
    private var tracked: [String: Entry] = [:]

    mutating func sessionsToRead(active: [ActiveSessionReport], at time: TimeInterval) -> [ActiveSessionReport] {
        for session in active { tracked[session.id] = Entry(session: session, lastSeen: time) }
        tracked = tracked.filter { time < $0.value.lastSeen + Self.closingGrace }
        return tracked.values.map(\.session).sorted { $0.id < $1.id }
    }

    func contains(_ sessionID: String, at time: TimeInterval) -> Bool {
        guard let entry = tracked[sessionID] else { return false }
        return time < entry.lastSeen + Self.closingGrace
    }

    mutating func reset() { tracked.removeAll() }
}

/// Reads only active or just-closed sessions' append-only journals. Content stays in memory.
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
        messages(sessions: sessions, vibeHome: vibeHome).max {
            if $0.completedAt != $1.completedAt { return $0.completedAt < $1.completedAt }
            return $0.sessionID < $1.sessionID
        }
    }

    mutating func messages(sessions: [ActiveSessionReport], vibeHome: URL) -> [DesktopPetMessage] {
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
        return messages
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

    func refresh(sessions: [ActiveSessionReport], receive: @escaping ([DesktopPetMessage]) -> Void) {
        guard !sessions.isEmpty else { receive([]); return }
        guard !reading else { return }
        reading = true
        let home = URL(fileURLWithPath: ProcessInfo.processInfo.environment["VIBE_HOME"]
                       ?? NSHomeDirectory() + "/.vibe")
        queue.async { [weak self] in
            guard let self else { return }
            let messages = self.reader.messages(sessions: sessions, vibeHome: home)
            DispatchQueue.main.async {
                self.reading = false
                receive(messages)
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
    private var shapePitch: CGFloat = -1
    /// Dot grid of the bubble, matching the cat's pixels.
    var dotPitch: CGFloat = 8 { didSet { if dotPitch != oldValue { needsLayout = true } } }
    var dotGap: CGFloat = 1.2 { didSet { if dotGap != oldValue { needsLayout = true } } }
    var backingScaleFactor: CGFloat = 0 { didSet { if backingScaleFactor != oldValue { needsLayout = true } } }
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
        let column = DesktopPetSpeechShape.tailColumn(for: bounds.size, at: tailX,
                                                       pitch: dotPitch, scale: backingScaleFactor)
        guard shapeSize != bounds.size || shapeTail != column || shapePitch != dotPitch else { return }
        let shape = DesktopPetSpeechShape(size: bounds.size, tailX: tailX,
                                          pitch: dotPitch, gap: dotGap,
                                          scale: backingScaleFactor)
        shapeSize = bounds.size
        shapeTail = shape.tailColumn
        shapePitch = dotPitch
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

/// Border dots use the same cell pitch and gap as the pet's dots, and the
/// same five color bands.
struct DesktopPetSpeechShape {
    let tailColumn: Int
    let glass: CGPath
    let dots: [(rect: CGRect, band: Int)]

    private static func columns(in size: CGSize, pitch: CGFloat) -> Int {
        max(11, Int(size.width / pitch))
    }

    private static func origin(of size: CGSize, columns: Int, rows: Int,
                               pitch: CGFloat, scale: CGFloat) -> CGPoint {
        var x = (size.width - CGFloat(columns) * pitch) / 2
        var y = (size.height - CGFloat(rows) * pitch) / 2
        if scale > 0 {
            x = round(x * scale) / scale
            y = round(y * scale) / scale
        }
        return CGPoint(x: x, y: y)
    }

    static func tailColumn(for size: CGSize, at x: CGFloat, pitch: CGFloat,
                           scale: CGFloat = 0) -> Int {
        let columns = columns(in: size, pitch: pitch)
        let originX = origin(of: size, columns: columns, rows: 8, pitch: pitch, scale: scale).x
        return min(max(Int(((x - originX) / pitch - 0.5).rounded()), 4), columns - 5)
    }

    init(size: CGSize, tailX: CGFloat, pitch: CGFloat, gap: CGFloat, scale: CGFloat = 0) {
        let columns = Self.columns(in: size, pitch: pitch)
        let rows = max(8, Int(size.height / pitch))
        let origin = Self.origin(of: size, columns: columns, rows: rows,
                                 pitch: pitch, scale: scale)
        let tail = Self.tailColumn(for: size, at: tailX, pitch: pitch, scale: scale)
        tailColumn = tail
        let spans = (0..<rows).map { row -> ClosedRange<Int> in
            if row < 2 { return (tail - row)...(tail + row) }
            let inset = max(0, 2 - min(row - 2, rows - 1 - row))
            return inset...(columns - 1 - inset)
        }
        let path = CGMutablePath()
        var border: [(rect: CGRect, band: Int)] = []
        for (row, span) in spans.enumerated() {
            let y = origin.y + CGFloat(row) * pitch
            path.addRect(CGRect(x: origin.x + CGFloat(span.lowerBound) * pitch,
                                y: y, width: CGFloat(span.count) * pitch,
                                height: pitch))
            for col in span {
                guard col == span.lowerBound || col == span.upperBound ||
                        row == 0 || row == rows - 1 ||
                        !spans[row - 1].contains(col) || !spans[row + 1].contains(col) else { continue }
                let cell = CGRect(x: origin.x + CGFloat(col) * pitch, y: y,
                                  width: pitch, height: pitch)
                border.append((cell.insetBy(dx: gap / 2, dy: gap / 2),
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
