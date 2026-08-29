import AppKit
import Sub2APIKit
import SwiftUI

private enum MenuBarPanelLayout {
  static let width: CGFloat = 390
  static let height: CGFloat = 690
}

struct MenuBarLabel: View {
  @Environment(\.openSettings) private var openSettings
  @ObservedObject var store: MonitorStore
  @State private var hasHandledInitialPresentation = false

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: store.statusSymbol)
      if let text = store.menuBarText {
        Text(text)
          .monospacedDigit()
      }
    }
    .onAppear { handleAppearance() }
    .onReceive(
      NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
    ) { _ in
      store.refreshAfterWake()
    }
  }

  private func handleAppearance() {
    store.start()
    guard !hasHandledInitialPresentation else { return }
    hasHandledInitialPresentation = true
    guard !store.isConfigured else { return }

    // A menu bar app otherwise has no visible first-launch surface.
    Task { @MainActor in
      await Task.yield()
      openSettings()
      NSApplication.shared.activate(ignoringOtherApps: true)
    }
  }
}

struct MenuBarView: View {
  @ObservedObject var store: MonitorStore
  @State private var adminListTab: AdminListTab = .accounts
  @State private var apiKeySortOption: AdminAPIKeySortOption = .todayRequests
  @State private var apiKeySortDescending = true

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
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

      if case .failed(let message) = store.state {
        Divider()
        StatusMessage(message: message, color: .red)
          .padding(12)
      } else if let warning = store.snapshot?.warning {
        Divider()
        StatusMessage(message: warning, color: .orange)
          .padding(12)
      }

      if let actionError = store.accountActionError {
        Divider()
        StatusMessage(message: actionError, color: .red)
          .padding(12)
      }

      Divider()
      footer
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
    .frame(
      width: MenuBarPanelLayout.width,
      height: MenuBarPanelLayout.height,
      alignment: .top
    )
    .onAppear { store.setMenuPresented(true) }
    .onDisappear { store.setMenuPresented(false) }
    .onChange(of: store.snapshot?.supportsAdminAccountList) { _, supportsAdminList in
      if supportsAdminList != true {
        adminListTab = .accounts
      }
    }
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
            title: primaryMetricTitle(snapshot),
            value: primaryMetricValue(snapshot),
            systemImage: snapshot.isAdminAPIKey ? "person.2" : "creditcard"
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

      if case .apiKey(let apiKeySnapshot) = snapshot,
        !usageLimitRows(apiKeySnapshot.usage).isEmpty
      {
        Divider()
        usageLimits(apiKeySnapshot.usage)
      }

      if let admin = snapshot.adminStats {
        Divider()
        adminSummary(admin)
      }

      if snapshot.supportsAdminAccountList {
        Divider()
        adminResourceList(snapshot)
          .frame(maxHeight: .infinity, alignment: .top)
      }

      HStack(spacing: 4) {
        Text("更新于")
        Text(snapshot.fetchedAt, style: .relative)
        Spacer()
        if snapshot.isAdminAPIKey {
          Text("管理员 Key")
            .foregroundStyle(.secondary)
        } else if snapshot.isAdmin {
          Text("管理员")
            .foregroundStyle(.secondary)
        } else if snapshot.isAPIKey {
          Text("API Key")
            .foregroundStyle(.secondary)
        }
        if let version = snapshot.serverVersion {
          Text(version)
            .foregroundStyle(.secondary)
        }
      }
      .font(.caption2)
      .foregroundStyle(.tertiary)
    }
    .frame(maxHeight: .infinity, alignment: .top)
  }

  private func primaryMetricTitle(_ snapshot: MonitorSnapshot) -> String {
    if snapshot.isAdminAPIKey { return "活跃用户" }
    return snapshot.isAPIKey ? "可用额度" : "余额"
  }

  private func primaryMetricValue(_ snapshot: MonitorSnapshot) -> String {
    if snapshot.isAdminAPIKey {
      return DisplayFormat.count(snapshot.adminStats?.activeUsers)
    }
    if snapshot.isAPIKey {
      return DisplayFormat.currencyOrUnlimitedDisplay(snapshot.remaining)
    }
    return DisplayFormat.currency(snapshot.remaining)
  }

  private func usageLimits(_ usage: APIKeyUsage) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack {
        Label("额度窗口", systemImage: "gauge.with.dots.needle.33percent")
          .font(.caption.weight(.semibold))
        Spacer()
        Text(apiKeyStatusName(usage.status, isOperational: usage.isOperational))
          .font(.caption)
          .foregroundStyle(usage.isOperational ? Color.secondary : Color.orange)
      }

      ForEach(usageLimitRows(usage)) { row in
        VStack(spacing: 4) {
          HStack {
            Text(row.title)
            Spacer()
            Text("\(DisplayFormat.currency(row.used)) / \(DisplayFormat.currency(row.limit))")
              .monospacedDigit()
          }
          .font(.caption2)
          .foregroundStyle(.secondary)

          ProgressView(value: row.progress)
            .tint(row.progress >= 1 ? .orange : .accentColor)
        }
      }
    }
  }

  private func usageLimitRows(_ usage: APIKeyUsage) -> [UsageLimitRow] {
    if let quota = usage.quota, let limit = quota.limit, limit > 0 {
      return [
        UsageLimitRow(
          id: "quota",
          title: "总额度",
          used: quota.used ?? max(0, limit - (quota.remaining ?? limit)),
          limit: limit
        )
      ] + rateLimitRows(usage.rateLimits)
    }

    let rateRows = rateLimitRows(usage.rateLimits)
    if !rateRows.isEmpty { return rateRows }

    guard let subscription = usage.subscription else { return [] }
    return [
      subscriptionLimitRow(
        id: "daily",
        title: "每日",
        used: subscription.dailyUsageUSD,
        limit: subscription.dailyLimitUSD
      ),
      subscriptionLimitRow(
        id: "weekly",
        title: "每周",
        used: subscription.weeklyUsageUSD,
        limit: subscription.weeklyLimitUSD
      ),
      subscriptionLimitRow(
        id: "monthly",
        title: "每月",
        used: subscription.monthlyUsageUSD,
        limit: subscription.monthlyLimitUSD
      ),
    ].compactMap { $0 }
  }

  private func rateLimitRows(_ limits: [APIKeyRateLimit]?) -> [UsageLimitRow] {
    (limits ?? []).compactMap { limit in
      guard let maximum = limit.limit, maximum > 0 else { return nil }
      return UsageLimitRow(
        id: "rate-\(limit.window)",
        title: limitWindowName(limit.window),
        used: limit.used ?? max(0, maximum - (limit.remaining ?? maximum)),
        limit: maximum
      )
    }
  }

  private func subscriptionLimitRow(
    id: String,
    title: String,
    used: Double?,
    limit: Double?
  ) -> UsageLimitRow? {
    guard let limit, limit > 0 else { return nil }
    return UsageLimitRow(id: id, title: title, used: used ?? 0, limit: limit)
  }

  private func limitWindowName(_ window: String) -> String {
    switch window {
    case "5h": "5 小时"
    case "1d": "每日"
    case "7d": "每周"
    default: window
    }
  }

  private func apiKeyStatusName(_ status: String?, isOperational: Bool) -> String {
    switch status?.lowercased() {
    case "active": "正常"
    case "expired": "已过期"
    case "quota_exhausted": "额度耗尽"
    case "disabled": "已停用"
    default: isOperational ? "正常" : "不可用"
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

  private func adminAccountList(_ accounts: [AdminAccountSnapshot]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Label("账号列表", systemImage: "person.3")
          .font(.caption.weight(.semibold))
        Spacer()
        Text("\(accounts.count) 个")
          .font(.caption)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }

      if accounts.isEmpty {
        Text("暂无账号数据")
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 10)
      } else {
        ScrollView {
          VStack(spacing: 0) {
            ForEach(accounts) { account in
              AdminAccountRow(account: account, store: store)
              if account.id != accounts.last?.id {
                Divider()
              }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        // A menu-bar popover gives an unconstrained vertical proposal. The
        // flexible viewport keeps list growth inside the fixed panel.
        .frame(maxHeight: .infinity)
      }
    }
    .frame(maxHeight: .infinity, alignment: .top)
  }

  private func adminResourceList(_ snapshot: MonitorSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Picker("管理员列表", selection: $adminListTab) {
        ForEach(AdminListTab.allCases) { tab in
          Text(tab.title).tag(tab)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .onChange(of: adminListTab) { _, tab in
        guard tab == .apiKeys else { return }
        Task { await store.refreshAdminAPIKeysIfNeeded() }
      }

      Group {
        switch adminListTab {
        case .accounts:
          adminAccountList(snapshot.adminAccounts)
        case .apiKeys:
          adminAPIKeyList()
        }
      }
      // Keep scroll and row layout state isolated between the two resources.
      .id(adminListTab)
      .frame(maxHeight: .infinity, alignment: .top)
    }
    .frame(maxHeight: .infinity, alignment: .top)
  }

  private func adminAPIKeyList() -> some View {
    let items = sortedAdminAPIKeys

    return VStack(alignment: .leading, spacing: 8) {
      HStack {
        Label("API 列表", systemImage: "key")
          .font(.caption.weight(.semibold))
        Spacer()
        if store.isLoadingAdminAPIKeys {
          ProgressView()
            .controlSize(.small)
        }
        Text("\(items.count) 个")
          .font(.caption)
          .foregroundStyle(.secondary)
          .monospacedDigit()
        Menu {
          ForEach(AdminAPIKeySortOption.allCases) { option in
            Button {
              selectAPIKeySort(option)
            } label: {
              Label(
                sortMenuTitle(for: option),
                systemImage: apiKeySortOption == option ? "checkmark" : option.systemImage
              )
            }
          }
          Divider()
          Button {
            apiKeySortDescending.toggle()
          } label: {
            Label(
              apiKeySortDescending ? "切换为升序" : "切换为降序",
              systemImage: apiKeySortDescending ? "arrow.up" : "arrow.down"
            )
          }
        } label: {
          Image(systemName: "arrow.up.arrow.down")
        }
        .menuStyle(.borderlessButton)
        .help("排序")
      }

      if let error = store.adminAPIKeysError, items.isEmpty {
        Label("API 列表加载失败：\(error)", systemImage: "exclamationmark.triangle")
          .font(.caption2)
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
      } else if store.isLoadingAdminAPIKeys, items.isEmpty {
        HStack(spacing: 7) {
          ProgressView()
            .controlSize(.small)
          Text("正在加载 API 列表…")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
      } else if items.isEmpty {
        Text("暂无 API Key")
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 10)
      } else {
        ScrollView {
          VStack(spacing: 0) {
            ForEach(items) { apiKey in
              AdminAPIKeyRow(apiKey: apiKey)
              if apiKey.id != items.last?.id {
                Divider()
              }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
      }

      if let warning = store.adminAPIKeysWarning {
        Label(warning, systemImage: "info.circle")
          .font(.caption2)
          .foregroundStyle(.orange)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxHeight: .infinity, alignment: .top)
  }

  private var sortedAdminAPIKeys: [AdminAPIKeyListItem] {
    store.adminAPIKeys.sorted { lhs, rhs in
      switch apiKeySortOption {
      case .todayRequests:
        if let order = requestCountComesBefore(
          lhs,
          rhs,
          descending: apiKeySortDescending
        ) {
          return order
        }
      case .name:
        if let order = textComesBefore(
          lhs.displayName,
          rhs.displayName,
          descending: apiKeySortDescending
        ) {
          return order
        }
      case .group:
        if let order = textComesBefore(
          lhs.groupName,
          rhs.groupName,
          descending: apiKeySortDescending
        ) {
          return order
        }
      }
      return apiKeyTieBreakComesBefore(lhs, rhs)
    }
  }

  private func requestCountComesBefore(
    _ lhs: AdminAPIKeyListItem,
    _ rhs: AdminAPIKeyListItem,
    descending: Bool
  ) -> Bool? {
    switch (lhs.todayRequests, rhs.todayRequests) {
    case (nil, nil):
      return nil
    case let (left?, right?):
      guard left != right else { return nil }
      return descending ? left > right : left < right
    case (nil, _):
      return false
    case (_, nil):
      return true
    }
  }

  private func textComesBefore(_ lhs: String, _ rhs: String, descending: Bool) -> Bool? {
    switch lhs.localizedStandardCompare(rhs) {
    case .orderedAscending:
      return !descending
    case .orderedDescending:
      return descending
    case .orderedSame:
      return nil
    }
  }

  private func apiKeyTieBreakComesBefore(
    _ lhs: AdminAPIKeyListItem,
    _ rhs: AdminAPIKeyListItem
  ) -> Bool {
    for (left, right) in [
      (lhs.displayName, rhs.displayName),
      (lhs.groupName, rhs.groupName),
      (lhs.ownerDisplayName, rhs.ownerDisplayName),
    ] {
      if let order = textComesBefore(left, right, descending: false) {
        return order
      }
    }
    return lhs.id < rhs.id
  }

  private func selectAPIKeySort(_ option: AdminAPIKeySortOption) {
    guard apiKeySortOption != option else { return }
    apiKeySortOption = option
    apiKeySortDescending = option == .todayRequests
  }

  private func sortMenuTitle(for option: AdminAPIKeySortOption) -> String {
    guard apiKeySortOption == option else { return option.title }
    return "\(option.title) · \(apiKeySortDescending ? "降序" : "升序")"
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

private struct AdminAPIKeyRow: View {
  let apiKey: AdminAPIKeyListItem

  var body: some View {
    HStack(alignment: .center, spacing: 8) {
      Circle()
        .fill(statusColor)
        .frame(width: 8, height: 8)

      VStack(alignment: .leading, spacing: 3) {
        Text(apiKey.displayName)
          .font(.caption.weight(.semibold))
          .lineLimit(1)
        Text("\(apiKey.groupName) · \(apiKey.ownerDisplayName)")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer(minLength: 8)

      VStack(alignment: .trailing, spacing: 2) {
        Text(DisplayFormat.count(apiKey.todayRequests))
          .font(.caption.weight(.semibold))
          .monospacedDigit()
        Text("今日调用")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 8)
    .help("仅显示 API 元数据，不显示密钥内容")
  }

  private var statusColor: Color {
    switch apiKey.status?.lowercased() {
    case "active": .green
    case "quota_exhausted": .orange
    case "expired", "disabled": .secondary
    default: .secondary
    }
  }
}

private struct AdminAccountRow: View {
  let account: AdminAccountSnapshot
  @ObservedObject var store: MonitorStore
  @State private var isResetConfirmationPresented = false

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(alignment: .top, spacing: 8) {
        Circle()
          .fill(status.color)
          .frame(width: 8, height: 8)
          .padding(.top, 4)

        VStack(alignment: .leading, spacing: 2) {
          Text(account.account.name)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
          Text("\(platformName) · \(status.title)")
            .font(.caption2)
            .foregroundStyle(status.color)
            .lineLimit(1)
            .help(account.account.errorMessage ?? "")
        }

        Spacer(minLength: 8)

        if let percent = account.sevenDayUsagePercent {
          Text(DisplayFormat.percentageText(percent))
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(percent >= 100 ? Color.orange : Color.primary)
        }
      }

      sevenDayUsage

      if let statusDetail {
        Label(statusDetail, systemImage: "clock")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }

      if account.account.isOpenAIOAuth && !account.account.isShadow {
        HStack(spacing: 6) {
          Button {
            Task { await store.refreshOpenAIQuota(account.id) }
          } label: {
            Label(resetCreditsTitle, systemImage: "arrow.clockwise.circle")
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .help("查询上游可用重置次数")

          Button {
            isResetConfirmationPresented = true
          } label: {
            Label("重置", systemImage: "arrow.uturn.backward.circle")
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .help("消耗一次上游重置次数")
          .disabled(availableResetCount == 0)

          if store.isAccountActionInProgress(account.id) {
            ProgressView()
              .controlSize(.small)
              .padding(.leading, 2)
          }

          Spacer(minLength: 0)
        }
        .disabled(store.isAccountActionInProgress(account.id))

        if let quotaError = store.openAIQuotaError(for: account.id) {
          Text("重置次数查询失败：\(quotaError)")
            .font(.caption2)
            .foregroundStyle(.red)
            .lineLimit(2)
        }
      } else if account.account.isShadow {
        Label("影子账号跟随母账号额度", systemImage: "arrow.triangle.branch")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
    }
    .padding(.vertical, 9)
    .confirmationDialog(
      "确认重置 OpenAI 账号？",
      isPresented: $isResetConfirmationPresented,
      titleVisibility: .visible
    ) {
      Button("重置", role: .destructive) {
        Task { await store.resetOpenAIQuota(account.id) }
      }
      Button("取消", role: .cancel) {}
    } message: {
      Text("将消耗“\(account.account.name)”的一个上游重置次数，并同步账号状态。")
    }
  }

  private var availableResetCount: Int {
    store.openAIQuota(for: account.id)?.availableResetCount ?? 0
  }

  private var resetCreditsTitle: String {
    guard store.openAIQuota(for: account.id) != nil else { return "重置次数" }
    return "重置次数 \(availableResetCount)"
  }

  @ViewBuilder
  private var sevenDayUsage: some View {
    if let percent = account.sevenDayUsagePercent {
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 5) {
          Label("7D 限额", systemImage: "chart.bar.xaxis")
          Spacer()
          resetDescription
        }
        .font(.caption2)
        .foregroundStyle(.secondary)

        ProgressView(value: min(max(percent / 100, 0), 1))
          .tint(percent >= 100 ? .orange : .accentColor)
      }
    } else {
      Text(account.usageError == nil ? "7D 限额暂无数据" : "7D 限额同步失败")
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .help(account.usageError ?? "服务器尚未返回 7D 用量")
    }
  }

  @ViewBuilder
  private var resetDescription: some View {
    if let date = sevenDayResetDate {
      VStack(alignment: .trailing, spacing: 1) {
        Text("约 \(relativeDateText(date))")
        Text("重置于 \(DisplayFormat.localDateTime(date))")
      }
      .multilineTextAlignment(.trailing)
      .lineLimit(1)
    }
  }

  private var sevenDayResetDate: Date? {
    if let date = parseDate(account.sevenDayResetAt) {
      return date
    }
    guard let seconds = account.sevenDayRemainingSeconds, seconds >= 0 else { return nil }
    let anchorDate = parseDate(account.usage?.updatedAt)
      ?? parseDate(account.account.extra?.codexUsageUpdatedAt)
      ?? parseDate(account.account.updatedAt)
      ?? Date()
    return anchorDate.addingTimeInterval(seconds)
  }

  private var status: AdminAccountStatus {
    let value = account.account
    if value.isRateLimited || liveOpenAIRateLimitReached { return .rateLimited }
    if value.isOverloaded { return .overloaded }
    if value.isTemporarilyUnschedulable { return .paused }
    if value.status?.lowercased() == "error"
      || !(value.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    {
      return .error
    }
    if ["inactive", "disabled", "expired"].contains(value.status?.lowercased()) {
      return .inactive
    }
    if value.schedulable == false { return .paused }
    return .normal
  }

  private var statusDetail: String? {
    switch status {
    case .rateLimited:
      if let date = account.account.rateLimitResetDate {
        return "预计 \(DisplayFormat.localDateTime(date)) 恢复（\(relativeDateText(date))）"
      }
      if let date = liveOpenAIRateLimitResetDate {
        return "预计 \(DisplayFormat.localDateTime(date)) 恢复（\(relativeDateText(date))）"
      }
      return "等待上游限流窗口恢复"
    case .overloaded:
      if let date = parseDate(account.account.overloadUntil) {
        return "过载预计 \(relativeDateText(date))恢复"
      }
      return "等待过载状态恢复"
    case .error:
      return account.account.errorMessage
    case .paused:
      return account.account.tempUnschedulableReason ?? "账号暂不可调度"
    case .normal:
      return nil
    case .inactive:
      return "账号已停用"
    }
  }

  private var liveOpenAIRateLimitReached: Bool {
    guard let rateLimit = store.openAIQuota(for: account.id)?.rateLimit else { return false }
    return rateLimit.limitReached || !rateLimit.allowed
  }

  private var liveOpenAIRateLimitResetDate: Date? {
    guard let usage = store.openAIQuota(for: account.id),
      let window = usage.rateLimit?.primaryWindow
    else { return nil }
    if window.resetAt > 0 {
      return Date(timeIntervalSince1970: window.resetAt)
    }
    guard window.resetAfterSeconds > 0 else { return nil }
    let anchorDate = usage.fetchedAt > 0
      ? Date(timeIntervalSince1970: usage.fetchedAt)
      : Date()
    return anchorDate.addingTimeInterval(window.resetAfterSeconds)
  }

  private var platformName: String {
    switch account.account.platform.lowercased() {
    case "anthropic": "Anthropic"
    case "openai": "OpenAI"
    case "gemini": "Gemini"
    case "antigravity": "Antigravity"
    case "grok": "Grok"
    case "kimi": "Kimi"
    case "zhipu": "智谱"
    case "deepseek": "DeepSeek"
    default: account.account.platform
    }
  }

  private func parseDate(_ rawValue: String?) -> Date? {
    guard let rawValue, !rawValue.isEmpty else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: rawValue)
      ?? {
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: rawValue)
      }()
  }

  private func durationText(_ seconds: Double) -> String {
    let totalSeconds = max(Int(seconds.rounded()), 0)
    let days = totalSeconds / 86_400
    let hours = (totalSeconds % 86_400) / 3_600
    let minutes = (totalSeconds % 3_600) / 60
    if days > 0 { return "\(days)天\(hours)小时" }
    if hours > 0 { return "\(hours)小时\(minutes)分钟" }
    return "\(max(minutes, 1))分钟"
  }

  private func relativeDateText(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: Date())
  }
}

private enum AdminListTab: String, CaseIterable, Identifiable {
  case accounts
  case apiKeys

  var id: String { rawValue }

  var title: String {
    switch self {
    case .accounts: "账号列表"
    case .apiKeys: "API 列表"
    }
  }
}

private enum AdminAPIKeySortOption: String, CaseIterable, Identifiable {
  case todayRequests
  case name
  case group

  var id: String { rawValue }

  var title: String {
    switch self {
    case .todayRequests: "今日调用量"
    case .name: "API 名称"
    case .group: "所属分组"
    }
  }

  var systemImage: String {
    switch self {
    case .todayRequests: "chart.bar"
    case .name: "textformat"
    case .group: "folder"
    }
  }
}

private enum AdminAccountStatus {
  case normal
  case rateLimited
  case overloaded
  case paused
  case error
  case inactive

  var title: String {
    switch self {
    case .normal: "正常"
    case .rateLimited: "限流中"
    case .overloaded: "过载"
    case .paused: "已暂停"
    case .error: "错误"
    case .inactive: "已停用"
    }
  }

  var color: Color {
    switch self {
    case .normal: .green
    case .rateLimited: .orange
    case .overloaded: .yellow
    case .paused: .secondary
    case .error: .red
    case .inactive: .secondary
    }
  }
}

private struct UsageLimitRow: Identifiable {
  let id: String
  let title: String
  let used: Double
  let limit: Double

  var progress: Double {
    DisplayFormat.percentage(used: used, limit: limit) ?? 0
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
