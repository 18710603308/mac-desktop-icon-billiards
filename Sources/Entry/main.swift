import AppKit
import BilliardsApp

// One game at a time; the lock dies with the process.
let lockDescriptor = open((NSTemporaryDirectory() as NSString)
    .appendingPathComponent("DesktopIconBilliards.lock"), O_CREAT | O_RDWR, 0o644)
if lockDescriptor < 0 || flock(lockDescriptor, LOCK_EX | LOCK_NB) != 0 {
    exit(0)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()