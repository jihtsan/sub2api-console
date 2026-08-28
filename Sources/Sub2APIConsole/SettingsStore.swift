import Combine
import Foundation
import Sub2APIKit

@MainActor
final class SettingsStore: ObservableObject {
  private enum Key {
    static let serverAddress = "serverAddress"
    static let email = "email"
    static let authenticationMode = "authenticationMode"
    static let refreshInterval = "refreshInterval"
    static let menuBarMetric = "menuBarMetric"
    static let allowInsecureHTTP = "allowInsecureHTTP"
  }

  private let defaults: UserDefaults

  @Published var serverAddress: String {
    didSet { defaults.set(serverAddress, forKey: Key.serverAddress) }
  }

  @Published var email: String {
    didSet { defaults.set(email, forKey: Key.email) }
  }

  @Published var authenticationMode: AuthenticationMode {
    didSet { defaults.set(authenticationMode.rawValue, forKey: Key.authenticationMode) }
  }

  @Published var refreshInterval: RefreshInterval {
    didSet { defaults.set(refreshInterval.rawValue, forKey: Key.refreshInterval) }
  }

  @Published var menuBarMetric: MenuBarMetric {
    didSet { defaults.set(menuBarMetric.rawValue, forKey: Key.menuBarMetric) }
  }

  @Published var allowInsecureHTTP: Bool {
    didSet { defaults.set(allowInsecureHTTP, forKey: Key.allowInsecureHTTP) }
  }

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    serverAddress = defaults.string(forKey: Key.serverAddress) ?? ""
    email = defaults.string(forKey: Key.email) ?? ""
    let storedMode = defaults.string(forKey: Key.authenticationMode) ?? ""
    authenticationMode = AuthenticationMode(rawValue: storedMode) ?? .apiKey
    refreshInterval =
      RefreshInterval(
        rawValue: defaults.integer(forKey: Key.refreshInterval)
      ) ?? .oneMinute
    let storedMetric = defaults.string(forKey: Key.menuBarMetric) ?? ""
    menuBarMetric = MenuBarMetric(rawValue: storedMetric) ?? .remaining
    allowInsecureHTTP = defaults.bool(forKey: Key.allowInsecureHTTP)
  }
}
