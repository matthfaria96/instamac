// InstamacNotifier -- posts Instamac's notifications into the macOS Notification Center.
//
// The runtime process is an executable inside the bundle reached by execv, not a
// registered app bundle, and UNUserNotificationCenter needs one. This helper lives in
// Instamac.app/Contents/Helpers, has no Dock icon (LSUIElement) and carries the
// Instamac name and icon, so the banner reads "Instamac".
//
// Protocol (NSDistributedNotificationCenter, this user's session only):
//   runtime -> helper  dev.instamac.notifier.post    {key, title, body, thread}
//                      dev.instamac.notifier.remove  {key}
//   helper -> runtime  dev.instamac.notifier.ready   {}
//                      dev.instamac.notifier.clicked {key}
// A click while Instamac is not running opens it (the notification is then gone).
// The helper quits a minute after Instamac stops running.
import Cocoa
import UserNotifications

let kPost = Notification.Name("dev.instamac.notifier.post")
let kRemove = Notification.Name("dev.instamac.notifier.remove")
let kReady = Notification.Name("dev.instamac.notifier.ready")
let kClicked = Notification.Name("dev.instamac.notifier.clicked")
let kMainBundleId = "dev.instamac.app"

/// One line per event in ~/Library/Logs/macapk/notifier.log (the runtime's log folder).
func logLine(_ msg: String) {
    let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/macapk")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("notifier.log")
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(msg)\n"
    if let h = try? FileHandle(forWritingTo: url) {
        h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
    } else {
        try? line.write(to: url, atomically: true, encoding: .utf8)
    }
}

// UNUserNotificationCenter refuses an app without an Apple-issued signature on this
// macOS ("Notifications are not allowed for this application", no prompt; measured
// 2026-11-13 on 27.2 with an ad-hoc and a self-signed helper and a bare test app).
// NSUserNotificationCenter (deprecated, still delivered) needs no authorization, so it
// carries the notifications until the app is signed with a Developer ID.
final class Notifier: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate,
                      NSUserNotificationCenterDelegate {
    let center = UNUserNotificationCenter.current()
    let legacy = NSUserNotificationCenter.default
    let dnc = DistributedNotificationCenter.default()
    var idleSince: Date?
    var authorized = false

    func applicationDidFinishLaunching(_ note: Notification) {
        center.delegate = self
        legacy.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async { self.authorized = granted }
            logLine("authorization granted=\(granted) error=\(String(describing: error))"
                    + (granted ? "" : " -> NSUserNotificationCenter"))
        }
        dnc.addObserver(self, selector: #selector(post(_:)), name: kPost, object: nil,
                        suspensionBehavior: .deliverImmediately)
        dnc.addObserver(self, selector: #selector(remove(_:)), name: kRemove, object: nil,
                        suspensionBehavior: .deliverImmediately)
        dnc.postNotificationName(kReady, object: nil, userInfo: nil, deliverImmediately: true)
        Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in self?.checkIdle() }
    }

    private func mainAppRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: kMainBundleId).isEmpty
    }

    private func checkIdle() {
        if mainAppRunning() { idleSince = nil; return }
        if let since = idleSince {
            if Date().timeIntervalSince(since) > 60 { NSApp.terminate(nil) }
        } else {
            idleSince = Date()
        }
    }

    @objc func post(_ note: Notification) {
        guard let info = note.userInfo, let key = info["key"] as? String else { return }
        if !authorized {
            let n = NSUserNotification()
            n.identifier = key
            n.title = info["title"] as? String ?? ""
            n.informativeText = info["body"] as? String ?? ""
            n.soundName = NSUserNotificationDefaultSoundName
            n.userInfo = ["key": key]
            // A repost of a key replaces it, as the Android shade does.
            for old in legacy.deliveredNotifications where old.identifier == key {
                legacy.removeDeliveredNotification(old)
            }
            legacy.deliver(n)
            logLine("posted \(key) (legacy)")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = info["title"] as? String ?? ""
        content.body = info["body"] as? String ?? ""
        if let thread = info["thread"] as? String, !thread.isEmpty { content.threadIdentifier = thread }
        content.sound = .default
        content.userInfo = ["key": key]
        center.add(UNNotificationRequest(identifier: key, content: content, trigger: nil)) { error in
            logLine(error == nil ? "posted \(key)" : "post \(key) failed: \(String(describing: error))")
        }
    }

    @objc func remove(_ note: Notification) {
        guard let key = note.userInfo?["key"] as? String else { return }
        center.removeDeliveredNotifications(withIdentifiers: [key])
        center.removePendingNotificationRequests(withIdentifiers: [key])
        for n in legacy.deliveredNotifications where n.identifier == key {
            legacy.removeDeliveredNotification(n)
        }
    }

    private func clicked(_ key: String) {
        logLine("clicked \(key) main-running=\(mainAppRunning())")
        if mainAppRunning() {
            dnc.postNotificationName(kClicked, object: nil, userInfo: ["key": key], deliverImmediately: true)
        } else {
            // Contents/Helpers/InstamacNotifier.app -> the Instamac.app around it.
            let app = Bundle.main.bundleURL.deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    func userNotificationCenter(_ c: NSUserNotificationCenter, didActivate n: NSUserNotification) {
        clicked(n.userInfo?["key"] as? String ?? "")
        c.removeDeliveredNotification(n)
    }

    func userNotificationCenter(_ c: NSUserNotificationCenter, shouldPresent n: NSUserNotification) -> Bool {
        true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        clicked(response.notification.request.content.userInfo["key"] as? String ?? "")
        done()
    }

    // Instamac posts only when it is not in front; show it whatever this helper's state.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .list, .sound])
    }
}

let app = NSApplication.shared
let delegate = Notifier()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
