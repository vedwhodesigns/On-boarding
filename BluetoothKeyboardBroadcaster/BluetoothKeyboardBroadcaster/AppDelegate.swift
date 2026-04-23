import Cocoa
import CoreBluetooth

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    var statusBarController: StatusBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusBarController = StatusBarController()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusBarController.bluetoothManager.stopBroadcasting()
    }
}
