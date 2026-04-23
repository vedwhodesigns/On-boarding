import Cocoa
import CoreBluetooth

class AppDelegate: NSObject, NSApplicationDelegate {

    var statusBarController: StatusBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock and application switcher
        NSApp.setActivationPolicy(.accessory)
        statusBarController = StatusBarController()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusBarController.bluetoothManager.stopBroadcasting()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
