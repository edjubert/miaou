import Foundation
import Darwin

/// Only display metrics cross into the sandboxed extension.
struct MiaouWidgetDay: Codable, Equatable {
    let day: String
    let tokens: Int
}

struct MiaouWidgetSnapshot: Codable, Equatable {
    var version = 1
    let updatedAt: Date
    let month: String
    let currency: String
    let language: String
    let monthCost: Double?
    let budgetCost: Double?
    let monthTokens: Int
    let todayCost: Double?
    let todayTokens: Int
    let todayRequests: Int
    let activityExpiresAt: Date?
    let daily: [MiaouWidgetDay]

    static let staleInterval: TimeInterval = 5 * 60

    func isCurrentMonth(at date: Date) -> Bool {
        Self.monthKey(date) == month
    }

    func isCurrentDay(at date: Date) -> Bool {
        Calendar.current.isDate(updatedAt, inSameDayAs: date)
    }

    func isStale(at date: Date) -> Bool {
        date.timeIntervalSince(updatedAt) >= Self.staleInterval
    }

    func isActive(at date: Date) -> Bool {
        isCurrentMonth(at: date) && !isStale(at: date) &&
            activityExpiresAt.map { $0 > date } == true
    }

    var budgetFraction: Double? {
        guard let used = monthCost, let budget = budgetCost, budget > 0 else { return nil }
        return used / budget
    }

    var remainingCost: Double? {
        guard let used = monthCost, let budget = budgetCost, budget > 0 else { return nil }
        return max(budget - used, 0)
    }

    var valid: Bool {
        version == 1 && month.range(of: #"^\d{4}-(0[1-9]|1[0-2])$"#,
                                    options: .regularExpression) != nil &&
            !currency.isEmpty && currency.count <= 16 &&
            ["system", "fr", "en"].contains(language) &&
            monthTokens >= 0 && todayTokens >= 0 && todayRequests >= 0 &&
            [monthCost, budgetCost, todayCost].allSatisfy {
                $0.map { $0.isFinite && $0 >= 0 } ?? true
            } && daily.count <= 14 && daily.allSatisfy { $0.tokens >= 0 }
    }

    static func monthKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }

    static var example: Self {
        let now = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return Self(updatedAt: now, month: monthKey(now), currency: "€", language: "system",
                    monthCost: 68.75, budgetCost: 255, monthTokens: 18_000_000,
                    todayCost: 3.42, todayTokens: 850_000, todayRequests: 24,
                    activityExpiresAt: now.addingTimeInterval(240),
                    daily: (0..<14).compactMap { offset in
                        guard let date = Calendar.current.date(byAdding: .day, value: offset - 13,
                                                              to: now) else { return nil }
                        return MiaouWidgetDay(day: formatter.string(from: date),
                                              tokens: (offset % 5 + 1) * 240_000)
                    })
    }
}

struct MiaouWidgetStorage {
    static let kind = "MiaouUsage"
    let directory: URL
    var snapshotURL: URL { directory.appendingPathComponent("usage.json") }

    static var shared: Self? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "MiaouAppGroup") as? String,
              !group.isEmpty, !group.contains("$("),
              let container = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: group) else { return nil }
        return Self(directory: container.appendingPathComponent("MiaouWidgets", isDirectory: true))
    }

    func read() -> MiaouWidgetSnapshot? {
        guard privatePath(directory, directory: true),
              privatePath(snapshotURL, directory: false),
              let size = try? snapshotURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 1_048_576, let data = try? Data(contentsOf: snapshotURL),
              let snapshot = try? JSONDecoder().decode(MiaouWidgetSnapshot.self, from: data),
              snapshot.valid else { return nil }
        return snapshot
    }

    func publish(_ snapshot: MiaouWidgetSnapshot) throws {
        guard snapshot.valid else { throw CocoaError(.fileWriteInvalidFileName) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        guard privatePath(directory, directory: true) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        let temporary = directory.appendingPathComponent(UUID().uuidString)
        let data = try JSONEncoder().encode(snapshot)
        guard FileManager.default.createFile(atPath: temporary.path, contents: data,
                                            attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard rename(temporary.path, snapshotURL.path) == 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private func privatePath(_ url: URL, directory: Bool) -> Bool {
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_uid == getuid(),
              info.st_mode & 0o077 == 0 else { return false }
        return info.st_mode & S_IFMT == (directory ? S_IFDIR : S_IFREG)
    }
}
