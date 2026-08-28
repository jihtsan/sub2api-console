import AppKit
import Sub2APIKit
import SwiftUI

struct MenuBarLabel: View {
  @ObservedObject var store: MonitorStore

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: store.statusSymbol)
      if let text = store.menuBarText {
        Text(text)
          .monospacedDigit()
      }
    }
    .onAppear { store.start() }
    .onReceive(
      NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
    ) { _ in
      store.refreshAfterWake()
    }
  }
}

struct MenuBarView: View {
  @ObservedObject var store: MonitorStore

  var body: some View {
    VStack(spacing: 0) {
      header
        .padding(16)

      Divider()

      Group {
        if let snapshot = store.snapshot {
          dashboard(snapshot)
        } else {
          emptyState
        }
      }
      .padding(16)

      if case .failed(let message) = store.state {
        Divider()
        StatusMessage(message: message, color: .red)
          .padding(12)
      } else if let warning = store.snapshot?.warning {
        Divider()
        StatusMessage(message: warning, color: .orange)
          .padding(12)
      }

      Divider()
      footer
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
    .frame(width: 348)
    .onAppear { store.setMenuPresented(true) }
    .onDisappear { store.setMenuPresented(false) }
  }

  private var header: some View {
    HStack(spacing: 10) {
      ZStack {
        RoundedRectangle(cornerRadius: 7)
          .fill(Color.accentColor.opacity(0.13))
        Image(systemName: "server.rack")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(Color.accentColor)
      }
      .frame(width: 34, height: 34)

      VStack(alignment: .leading, spacing: 2) {
        Text(store.serverHost)
          .font(.system(size: 13, weight: .semibold))
          .lineLimit(1)
        Text(store.snapshot?.displayName ?? "Sub2API Monitor")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer(minLength: 8)

      HStack(spacing: 5) {
        Circle()
          .fill(statusColor)
          .frame(width: 7, height: 7)
        Text(store.statusLabel)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder
  private func dashboard(_ snapshot: MonitorSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      Grid(horizontalSpacing: 14, verticalSpacing: 14) {
        GridRow {
          MetricCell(
            title: snapshot.isAPIKey ? "可用额度" : "余额",
            value: DisplayFormat.currency(snapshot.remaining),
            systemImage: "creditcard"
          )
          MetricCell(
            title: "今日消费",
            value: DisplayFormat.currency(snapshot.todayCost),
            systemImage: "arrow.up.right"
          )
          MetricCell(
            title: "今日请求",
            value: DisplayFormat.count(snapshot.todayRequests),
            systemImage: "arrow.left.arrow.right"
          )
        }

        GridRow {
          MetricCell(
            title: "RPM",
            value: DisplayFormat.rate(snapshot.rpm),
            systemImage: "speedometer"
          )
          MetricCell(
            title: "TPM",
            value: DisplayFormat.rate(snapshot.tpm),
            systemImage: "number"
          )
          MetricCell(
            title: "平均延迟",
            value: DisplayFormat.duration(milliseconds: snapshot.averageDurationMs),
            systemImage: "timer"
          )
        }
      }

      if let admin = snapshot.adminStats {
        Divider()
        adminSummary(admin)
      }

      HStack(spacing: 4) {
        Text("更新于")
        Text(snapshot.fetchedAt, style: .relative)
        Spacer()
        if snapshot.isAdmin {
          Text("管理员")
            .foregroundStyle(.secondary)
        } else if snapshot.isAPIKey {
          Text("API Key")
            .foregroundStyle(.secondary)
        }
      }
      .font(.caption2)
      .foregroundStyle(.tertiary)
    }
  }

  private func adminSummary(_ stats: AdminDashboardStats) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack {
        Label("系统", systemImage: "waveform.path.ecg")
          .font(.caption.weight(.semibold))
        Spacer()
        Text("\(stats.normalAccounts ?? 0) / \(stats.totalAccounts ?? 0) 账户可用")
          .font(.caption)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }

      HStack(spacing: 8) {
        HealthPill(title: "异常", value: stats.errorAccounts ?? 0, color: .red)
        HealthPill(title: "限流", value: stats.rateLimitAccounts ?? 0, color: .orange)
        HealthPill(title: "过载", value: stats.overloadAccounts ?? 0, color: .yellow)
        Spacer()
        Label("\(stats.activeUsers ?? 0)", systemImage: "person.2")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var emptyState: some View {
    VStack(spacing: 10) {
      if store.state == .connecting {
        ProgressView()
          .controlSize(.large)
          .frame(width: 28, height: 28)
      } else {
        Image(systemName: "network.slash")
          .font(.system(size: 25, weight: .light))
          .foregroundStyle(.secondary)
          .frame(width: 28, height: 28)
      }
      Text(store.state == .connecting ? "正在连接" : "尚未连接")
        .font(.headline)
      SettingsLink {
        Label("打开设置", systemImage: "gearshape")
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.small)
    }
    .frame(maxWidth: .infinity, minHeight: 112)
  }

  private var footer: some View {
    HStack(spacing: 4) {
      Button {
        Task { await store.refresh() }
      } label: {
        if store.isRefreshing {
          ProgressView()
            .controlSize(.small)
            .frame(width: 16, height: 16)
        } else {
          Image(systemName: "arrow.clockwise")
        }
      }
      .help("立即刷新")
      .disabled(store.isRefreshing || !store.isConfigured)

      Button {
        if let url = store.serverWebURL {
          NSWorkspace.shared.open(url)
        }
      } label: {
        Image(systemName: "safari")
      }
      .help("打开服务器控制台")
      .disabled(store.serverWebURL == nil)

      Spacer()

      SettingsLink {
        Image(systemName: "gearshape")
      }
      .help("设置")

      Button {
        NSApplication.shared.terminate(nil)
      } label: {
        Image(systemName: "power")
      }
      .help("退出")
    }
    .buttonStyle(.borderless)
    .controlSize(.large)
  }

  private var statusColor: Color {
    switch store.state {
    case .unconfigured: .secondary
    case .connecting: .orange
    case .connected: store.isHealthy ? .green : .orange
    case .failed: .red
    }
  }
}

private struct MetricCell: View {
  let title: String
  let value: String
  let systemImage: String

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Label(title, systemImage: systemImage)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      Text(value)
        .font(.system(size: 14, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct HealthPill: View {
  let title: String
  let value: Int
  let color: Color

  var body: some View {
    HStack(spacing: 4) {
      Circle()
        .fill(value == 0 ? Color.secondary.opacity(0.35) : color)
        .frame(width: 6, height: 6)
      Text("\(title) \(value)")
        .monospacedDigit()
    }
    .font(.caption2)
    .foregroundStyle(value == 0 ? .secondary : .primary)
  }
}

private struct StatusMessage: View {
  let message: String
  let color: Color

  var body: some View {
    HStack(alignment: .top, spacing: 7) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(color)
      Text(message)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }
  }
}
