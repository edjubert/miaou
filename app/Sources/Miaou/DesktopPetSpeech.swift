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
    private let title = NSTextField(labelWithString: "")
    private let message = NSTextField(wrappingLabelWithString: "")
    var tailX: CGFloat = 160 { didSet { if tailX != oldValue { needsDisplay = true } } }

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: Self.height))
        title.font = .systemFont(ofSize: 11, weight: .semibold)
        title.textColor = .secondaryLabelColor
        title.lineBreakMode = .byTruncatingTail
        message.font = .systemFont(ofSize: 13)
        message.textColor = .labelColor
        message.maximumNumberOfLines = 5
        message.lineBreakMode = .byWordWrapping
        message.cell?.truncatesLastVisibleLine = true
        addSubview(title)
        addSubview(message)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(_ value: DesktopPetMessage) {
        let heading = value.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = heading?.isEmpty == false ? heading! : L10n.t("desktopPet.speech.session")
        if title.stringValue != text { title.stringValue = text }
        if message.stringValue != value.text { message.stringValue = value.text }
    }

    override func layout() {
        super.layout()
        title.frame = CGRect(x: 16, y: bounds.height - 33, width: bounds.width - 32, height: 17)
        message.frame = CGRect(x: 16, y: 23, width: bounds.width - 32, height: bounds.height - 65)
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

    override func draw(_ dirtyRect: NSRect) {
        let body = bounds.insetBy(dx: 1, dy: 1)
        let bottom: CGFloat = 13
        let radius: CGFloat = 14
        let tail = min(max(tailX, body.minX + radius + 13), body.maxX - radius - 13)
        let path = NSBezierPath()
        path.move(to: CGPoint(x: body.minX + radius, y: bottom))
        path.line(to: CGPoint(x: tail - 12, y: bottom))
        path.line(to: CGPoint(x: tail, y: body.minY))
        path.line(to: CGPoint(x: tail + 12, y: bottom))
        path.line(to: CGPoint(x: body.maxX - radius, y: bottom))
        path.appendArc(withCenter: CGPoint(x: body.maxX - radius, y: bottom + radius),
                       radius: radius, startAngle: 270, endAngle: 360)
        path.line(to: CGPoint(x: body.maxX, y: body.maxY - radius))
        path.appendArc(withCenter: CGPoint(x: body.maxX - radius, y: body.maxY - radius),
                       radius: radius, startAngle: 0, endAngle: 90)
        path.line(to: CGPoint(x: body.minX + radius, y: body.maxY))
        path.appendArc(withCenter: CGPoint(x: body.minX + radius, y: body.maxY - radius),
                       radius: radius, startAngle: 90, endAngle: 180)
        path.line(to: CGPoint(x: body.minX, y: bottom + radius))
        path.appendArc(withCenter: CGPoint(x: body.minX + radius, y: bottom + radius),
                       radius: radius, startAngle: 180, endAngle: 270)
        path.close()
        NSColor.windowBackgroundColor.withAlphaComponent(0.96).setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}
