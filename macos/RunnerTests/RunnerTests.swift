import Cocoa
import FlutterMacOS
import XCTest

@testable import WSL_Manager

/// Covers the `wslmanager://` deep-link plumbing in `AppDelegate`.
///
/// Run with `flutter build macos --debug` followed by
/// `xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner
/// -configuration Debug`.
class RunnerTests: XCTestCase {
  private func url(_ s: String) -> URL { URL(string: s)! }

  private func launched(_ delegate: AppDelegate) {
    delegate.applicationDidFinishLaunching(
      Notification(name: NSApplication.didFinishLaunchingNotification))
  }

  /// The macOS build once failed because this method was declared without
  /// `override`. Pin that the delegate still answers the selector, so the
  /// channel that hands links to Dart is actually wired up on launch.
  func testDelegateHandlesDidFinishLaunching() {
    XCTAssertTrue(
      AppDelegate.instancesRespond(
        to: #selector(NSApplicationDelegate.applicationDidFinishLaunching(_:))))
  }

  func testLaunchWithoutAFlutterWindowIsANoOp() {
    let delegate = AppDelegate()
    XCTAssertNil(delegate.mainFlutterWindow)
    launched(delegate)
    XCTAssertNil(delegate.pendingLink)
  }

  func testLinkArrivingBeforeDartListensIsHeld() {
    let delegate = AppDelegate()
    delegate.application(NSApplication.shared, open: [url("wslmanager://activate?key=abc")])
    XCTAssertEqual(delegate.pendingLink, "wslmanager://activate?key=abc")
  }

  func testLinkIsStillHeldWhenLaunchFindsNoWindow() {
    let delegate = AppDelegate()
    delegate.application(NSApplication.shared, open: [url("wslmanager://activate?key=abc")])
    launched(delegate)
    XCTAssertEqual(delegate.pendingLink, "wslmanager://activate?key=abc",
                   "without a channel the link must survive launch for Dart to collect")
  }

  func testForeignSchemesAreIgnored() {
    let delegate = AppDelegate()
    delegate.application(NSApplication.shared, open: [url("https://wslmanager.com/buy")])
    XCTAssertNil(delegate.pendingLink)
  }

  func testOnlyTheWslmanagerLinkIsKeptFromAMixedBatch() {
    let delegate = AppDelegate()
    delegate.application(
      NSApplication.shared,
      open: [url("https://example.com/"), url("wslmanager://activate?key=k"), url("file:///tmp")])
    XCTAssertEqual(delegate.pendingLink, "wslmanager://activate?key=k")
  }
}
