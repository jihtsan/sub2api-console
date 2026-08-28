import AppKit
import SwiftUI

private final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApplication.shared.setActivationPolicy(.accessory)
  }
}

@main
struct Sub2APIConsoleApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var settings: SettingsStore
  @StateObject private var monitor: MonitorStore

  init() {
    let settings = SettingsStore()
    _settings = StateObject(wrappedValue: settings)
    _monitor = StateObject(wrappedValue: MonitorStore(settings: settings))
  }

  var body: some Scene {
    MenuBarExtra {
      MenuBarView(store: monitor)
    } label: {
      MenuBarLabel(store: monitor)
    }
    .menuBarExtraStyle(.window)

    Settings {
      SettingsView(store: monitor)
    }
  }
}
