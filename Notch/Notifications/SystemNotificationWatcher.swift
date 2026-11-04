import AppKit
import Observation
import SQLite3

/// Relaie dans l'encoche les notifications reçues par macOS.
///
/// macOS n'offre pas d'API pour lire les notifications des autres apps : on lit la
/// base où le Centre de notifications les enregistre (format non documenté, il peut
/// changer avec une mise à jour de macOS — on échoue alors en silence).
/// Cette base est protégée : il faut l'accès complet au disque pour Notch.
@Observable
@MainActor
final class SystemNotificationWatcher {
    enum Access { case granted, denied }

    private static let databaseURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2/db")
    private static let onboardingKey = "systemNotificationsOnboardingShown"

    private(set) var access: Access = .denied

    private let alerts: AlertCenter
    private let settings: AppSettings
    private var db: OpaquePointer?
    private var lastRecordID: Int64 = 0
    private var timer: Timer?
    private var appNames: [String: String] = [:]

    init(alerts: AlertCenter, settings: AppSettings) {
        self.alerts = alerts
        self.settings = settings

        connect()
        if access == .denied { showOnboardingOnce() }

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Base

    private func connect() {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(Self.databaseURL.path, &handle, flags, nil) == SQLITE_OK,
              let maxID = Self.maxRecordID(handle) else {
            sqlite3_close(handle)
            access = .denied
            return
        }
        db = handle
        // On part de maintenant : pas de rafale avec l'historique au lancement.
        lastRecordID = maxID
        access = .granted
    }

    private var ticks = 0

    private func tick() {
        guard db != nil else {
            // Accès accordé entre-temps dans les Réglages ? On réessaie toutes les 5 s.
            ticks += 1
            if ticks % 5 == 0 { connect() }
            return
        }
        guard settings.mirrorSystemNotifications else {
            // Désactivé : on avance le curseur pour ne pas tout rejouer en réactivant.
            if let maxID = Self.maxRecordID(db) { lastRecordID = maxID }
            return
        }
        poll()
    }

    private func poll() {
        var statement: OpaquePointer?
        let sql = "SELECT rec_id, data FROM record WHERE rec_id > ? ORDER BY rec_id"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            // Base fermée ou format changé : on se reconnectera.
            sqlite3_close(db)
            db = nil
            access = .denied
            return
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, lastRecordID)

        while sqlite3_step(statement) == SQLITE_ROW {
            lastRecordID = max(lastRecordID, sqlite3_column_int64(statement, 0))
            guard let bytes = sqlite3_column_blob(statement, 1) else { continue }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 1)))
            if let alert = makeAlert(from: data) { alerts.post(alert) }
        }
    }

    private static func maxRecordID(_ db: OpaquePointer?) -> Int64? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT IFNULL(MAX(rec_id), 0) FROM record", -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return sqlite3_column_int64(statement, 0)
    }

    // MARK: - Décodage

    private func makeAlert(from data: Data) -> NotchAlert? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let bundleID = plist["app"] as? String,
              bundleID != Bundle.main.bundleIdentifier,
              let request = plist["req"] as? [String: Any]
        else { return nil }

        let title = (request["titl"] as? String)?.trimmed
        let subtitle = (request["subt"] as? String)?.trimmed
        let body = (request["body"] as? String)?.trimmed
        guard title?.isEmpty == false || body?.isEmpty == false else { return nil }

        let appName = name(of: bundleID)
        let text = [subtitle, body].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return NotchAlert(
            icon: .app(bundleID: bundleID),
            source: appName,
            title: title?.isEmpty == false ? title! : appName,
            body: text.isEmpty ? nil : text,
            action: .openApp(bundleID: bundleID)
        )
    }

    private func name(of bundleID: String) -> String {
        if let cached = appNames[bundleID] { return cached }
        let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
            ?? bundleID
        appNames[bundleID] = name
        return name
    }

    private func showOnboardingOnce() {
        guard !UserDefaults.standard.bool(forKey: Self.onboardingKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.onboardingKey)
        alerts.post(NotchAlert(
            icon: .symbol("bell.badge.fill", .red),
            source: "Notch",
            title: "Afficher tes notifications ici ?",
            body: "Clique pour autoriser Notch dans « Accès complet au disque ».",
            action: .run { [weak self] in self?.openPrivacySettings() }
        ))
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
