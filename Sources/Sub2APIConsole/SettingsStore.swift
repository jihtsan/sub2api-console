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
    static let dashboardMetrics = "dashboardMetrics"
    static let allowInsecureHTTP = "allowInsecureHTTP"
  }

  static let maxDashboardMetrics = 6
  static let defaultDashboardMetrics: [DashboardMetric] = [
    .todayCost,
    .todayRequests,
    .todayTokens,
    .averageDuration,
    .errorRate,
  ]

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

  @Published private(set) var dashboardMetrics: [DashboardMetric] {
    didSet { defaults.set(dashboardMetrics.map(\.rawValue), forKey: Key.dashboardMetrics) }
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
    let storedDashboardMetrics = defaults.stringArray(forKey: Key.dashboardMetrics)?
      .compactMap(DashboardMetric.init(rawValue:))
    dashboardMetrics = Self.normalizedDashboardMetrics(
      storedDashboardMetrics ?? Self.defaultDashboardMetrics
    )
    allowInsecureHTTP = defaults.bool(forKey: Key.allowInsecureHTTP)
  }

  func setDashboardMetric(_ metric: DashboardMetric, enabled: Bool) {
    var selection = dashboardMetrics
    if enabled {
      guard !selection.contains(metric), selection.count < Self.maxDashboardMetrics else { return }
      selection.append(metric)
    } else {
      selection.removeAll { $0 == metric }
    }
    dashboardMetrics = Self.normalizedDashboardMetrics(selection)
  }

  func applyDashboardMetrics(_ metrics: [DashboardMetric]) {
    dashboardMetrics = Self.normalizedDashboardMetrics(metrics)
  }

  private static func normalizedDashboardMetrics(_ metrics: [DashboardMetric]) -> [DashboardMetric] {
    var seen = Set<DashboardMetric>()
    return Array(
      metrics.filter { seen.insert($0).inserted }
        .prefix(maxDashboardMetrics)
    )
  }
}
