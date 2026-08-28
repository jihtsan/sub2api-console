import Foundation
import Sub2APIKit

enum DisplayFormat {
  static let unavailable = "-"

  static func currency(_ value: Double) -> String {
    value.formatted(
      .currency(code: "USD")
        .precision(.fractionLength(value.magnitude >= 100 ? 0 : 2))
    )
  }

  static func currency(_ value: Double?) -> String {
    value.map(currency) ?? unavailable
  }

  static func currencyOrUnlimited(_ value: Double?) -> String? {
    guard let value else { return nil }
    return value < 0 ? "不限" : currency(value)
  }

  static func currencyOrUnlimitedDisplay(_ value: Double?) -> String {
    currencyOrUnlimited(value) ?? unavailable
  }

  static func count(_ value: Int) -> String {
    if value >= 1_000_000 {
      return String(format: "%.1fM", Double(value) / 1_000_000)
    }
    if value >= 1_000 {
      return String(format: "%.1fK", Double(value) / 1_000)
    }
    return value.formatted()
  }

  static func count(_ value: Int?) -> String {
    value.map(count) ?? unavailable
  }

  static func rate(_ value: Double) -> String {
    if value >= 1_000_000 {
      return String(format: "%.1fM", value / 1_000_000)
    }
    if value >= 1_000 {
      return String(format: "%.1fK", value / 1_000)
    }
    return value.formatted(.number.precision(.fractionLength(value < 10 ? 1 : 0)))
  }

  static func rate(_ value: Double?) -> String {
    value.map(rate) ?? unavailable
  }

  static func duration(milliseconds: Double?) -> String {
    guard let milliseconds else { return unavailable }
    if milliseconds >= 1_000 {
      return String(format: "%.1fs", milliseconds / 1_000)
    }
    return "\(Int(milliseconds.rounded()))ms"
  }

  static func refreshInterval(_ interval: RefreshInterval) -> String {
    switch interval {
    case .oneMinute: "1 分钟"
    case .fiveMinutes: "5 分钟"
    case .fifteenMinutes: "15 分钟"
    case .thirtyMinutes: "30 分钟"
    }
  }

  static func metricName(_ metric: MenuBarMetric) -> String {
    switch metric {
    case .remaining: "余额 / 可用账户"
    case .todayCost: "今日消费"
    case .todayRequests: "今日请求"
    case .rpm: "RPM"
    case .health: "健康状态"
    case .statusOnly: "仅状态"
    }
  }

  static func percentage(used: Double?, limit: Double?) -> Double? {
    guard let used, let limit, limit > 0 else { return nil }
    return min(max(used / limit, 0), 1)
  }

  static func percentageText(_ value: Double) -> String {
    let clamped = min(max(value, 0), 100)
    let fractionLength = clamped >= 10 ? 0 : 1
    return "\(clamped.formatted(.number.precision(.fractionLength(fractionLength))))%"
  }
}
