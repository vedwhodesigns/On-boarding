import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {

    var statusBarController: StatusBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusBarController = StatusBarController()

        // Show the first-launch tutorial (no-op if already seen)
        OnboardingWindowController.showIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusBarController.bluetoothManager.stopBroadcasting()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
