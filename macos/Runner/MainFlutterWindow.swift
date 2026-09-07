import Cocoa
import FlutterMacOS
import macos_window_utils

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let windowFrame = self.frame

    // `flutter_acrylic` needs its own view controller between the window and
    // the Flutter view. Building it here is the setup macos_window_utils
    // documents, and the point is the ordering: left to initialise itself at
    // runtime the plugin picks `NSApp.windows.first` — not necessarily this
    // window — force-casts its content view controller to a
    // `FlutterViewController`, and swaps the window's content out from under
    // every plugin that was handed the Flutter view at registration. Doing it
    // before `RegisterGeneratedPlugins` means the hierarchy plugins record is
    // the one they keep (bostrot/ai-tasks#49).
    let windowUtilsViewController = MacOSWindowUtilsViewController()
    self.contentViewController = windowUtilsViewController
    self.setFrame(windowFrame, display: true)

    MainFlutterWindowManipulator.start(mainFlutterWindow: self)

    RegisterGeneratedPlugins(registry: windowUtilsViewController.flutterViewController)

    super.awakeFromNib()
  }
}
