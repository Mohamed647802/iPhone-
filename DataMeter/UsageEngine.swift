import Foundation
import Observation
import UIKit
import BackgroundTasks

struct AlertMessage: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
@Observable
final class UsageEngine {

    nonisolated static let bgTaskID = "com.example.datameter.refresh"
    private static let storeKey = "datameter.state.v1"

    enum Source: String, Codable, CaseIterable, Identifiable {
        case cellular, wifi, total
        var id: String { rawValue }
        var title: String {
            switch self {
            case .cellular: return "بيانات الجوال"
            case .wifi: return "واي فاي"
            case .total: return "الإجمالي (واي فاي + بيانات)"
            }
        }
    }

    enum DataUnit: String, Codable, CaseIterable, Identifiable {
        case mb, gb
        var id: String { rawValue }
        var title: String { self == .mb ? "MB" : "GB" }
        /// 1024-based. لو شركتك بتحسب 1000 غيّر الرقمين.
        var bytes: Double { self == .mb ? 1_048_576 : 1_073_741_824 }
    }

    struct Stored: Codable {
        var isRunning = false
        var wifiBytes: UInt64 = 0
        var cellBytes: UInt64 = 0
        var lastSnapshot: Snapshot = [:]
        var bootTime: TimeInterval = 0
        var startedAt: Date? = nil

        var quotaValue: Double = 1
        var quotaUnit: DataUnit = .gb
        var source: Source = .cellular
        var thresholdPercent: Double = 80

        var warnedThreshold = false
        var warnedFull = false
    }

    var state: Stored
    var pendingAlert: AlertMessage?

    @ObservationIgnored private var loopTask: Task<Void, Never>?

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storeKey),
           let saved = try? JSONDecoder().decode(Stored.self, from: data) {
            state = saved
        } else {
            state = Stored()
        }
    }

    // MARK: - Derived values

    var quotaBytes: Double { state.quotaValue * state.quotaUnit.bytes }

    var monitoredBytes: Double {
        switch state.source {
        case .cellular: return Double(state.cellBytes)
        case .wifi: return Double(state.wifiBytes)
        case .total: return Double(state.cellBytes + state.wifiBytes)
        }
    }

    var fraction: Double { quotaBytes > 0 ? monitoredBytes / quotaBytes : 0 }
    var remainingBytes: Double { max(0, quotaBytes - monitoredBytes) }

    // MARK: - Controls

    func start() {
        guard !state.isRunning else { return }
        state.lastSnapshot = NetworkCounters.read()
        state.bootTime = NetworkCounters.bootTime()
        state.isRunning = true
        if state.startedAt == nil { state.startedAt = .now }
        save()
        startLoop()
        scheduleBackgroundRefresh()
        Task { await NotificationManager.shared.requestAuthorization() }
    }

    func stop() {
        tick()
        state.isRunning = false
        save()
        loopTask?.cancel()
        loopTask = nil
    }

    func reset() {
        state.wifiBytes = 0
        state.cellBytes = 0
        state.warnedThreshold = false
        state.warnedFull = false
        state.startedAt = state.isRunning ? .now : nil
        if state.isRunning {
            state.lastSnapshot = NetworkCounters.read()
            state.bootTime = NetworkCounters.bootTime()
        }
        save()
    }

    /// تُستدعى بعد تعديل الإعدادات: نعيد تسليح التنبيهات.
    func settingsChanged() {
        state.warnedThreshold = false
        state.warnedFull = false
        if state.isRunning { tick() } else { save() }
    }

    // MARK: - Counting

    func tick() {
        guard state.isRunning else { return }
        let now = NetworkCounters.read()
        let boot = NetworkCounters.bootTime()

        // لو الجهاز اتعمله ريستارت، العدّادات بدأت من صفر.
        if abs(boot - state.bootTime) > 30 {
            state.lastSnapshot = [:]
            state.bootTime = boot
        }

        for (name, cur) in now {
            let old = state.lastSnapshot[name] ?? IfBytes(rx: 0, tx: 0)
            let d = NetworkCounters.delta(cur.rx, old.rx) + NetworkCounters.delta(cur.tx, old.tx)
            if name == "en0" { state.wifiBytes += d } else { state.cellBytes += d }
        }
        state.lastSnapshot = now
        checkAlerts()
        save()
    }

    private func checkAlerts() {
        guard state.quotaValue > 0 else { return }
        let f = fraction
        let used = ByteFormat.string(monitoredBytes)

        if f >= 1, !state.warnedFull {
            state.warnedFull = true
            state.warnedThreshold = true
            fire(title: "انتهت الكمية بالكامل",
                 body: "استهلكت \(used) من \(Self.trim(state.quotaValue)) \(state.quotaUnit.title) (\(state.source.title)).",
                 id: "full")
        } else if f >= state.thresholdPercent / 100, f < 1, !state.warnedThreshold {
            state.warnedThreshold = true
            fire(title: "وصلت إلى \(Int(state.thresholdPercent))% من الكمية",
                 body: "استهلكت \(used)، والمتبقي \(ByteFormat.string(remainingBytes)).",
                 id: "threshold")
        }
    }

    private func fire(title: String, body: String, id: String) {
        pendingAlert = AlertMessage(title: title, message: body)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        NotificationManager.shared.send(title: title, body: body, id: id)
    }

    // MARK: - Lifecycle

    private func startLoop() {
        loopTask?.cancel()
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.tick()
            }
        }
    }

    func didBecomeActive() {
        guard state.isRunning else { return }
        tick()          // يلحق أي استهلاك حصل والتطبيق في الخلفية
        startLoop()
    }

    func didEnterBackground() {
        tick()
        save()
        if state.isRunning { scheduleBackgroundRefresh() }
    }

    func refreshInBackground() {
        tick()
        if state.isRunning { scheduleBackgroundRefresh() }
    }

    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.bgTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func trim(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    func save() {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.storeKey)
        }
    }
}
