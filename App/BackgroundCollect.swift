import BackgroundTasks
import Foundation
import TrajetCore

/// Collecte automatique en arrière-plan : iOS la lance une fois par jour, de préférence la nuit,
/// quand l'iPhone a du réseau (et souvent quand il est en charge).
enum BackgroundCollect {
    static let identifier = "com.trajetmada.app.collect"

    /// À appeler au lancement de l'app, avant la fin du démarrage.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            handle(task)
        }
    }

    static func schedule(log: LogStore) {
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        let next = nextRun()
        request.earliestBeginDate = next
        do {
            try BGTaskScheduler.shared.submit(request)
            log.debug(.app, "Collecte automatique programmée à partir du \(Fmt.dayShort(Day(localDate: next))) à 5 h")
        } catch {
            log.warning(.app, "Collecte automatique non programmée : \(error.localizedDescription)")
        }
    }

    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    }

    /// Prochain 5 h du matin (heure de l'iPhone).
    static func nextRun(now: Date = Date()) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = 5
        let todayAtFive = calendar.date(from: components) ?? now
        if todayAtFive > now { return todayAtFive }
        return calendar.date(byAdding: .day, value: 1, to: todayAtFive) ?? now.addingTimeInterval(86_400)
    }

    private static func handle(_ task: BGTask) {
        let work = Task { @MainActor in
            let model = AppModel.shared
            model.log.info(.app, "Collecte automatique lancée par iOS")
            model.scheduleBackgroundCollection()
            let ok = await model.collectAll(trigger: .background)
            task.setTaskCompleted(success: ok)
        }
        // iOS reprend la main : on arrête proprement, les prix déjà relevés sont gardés.
        task.expirationHandler = {
            work.cancel()
        }
    }
}
