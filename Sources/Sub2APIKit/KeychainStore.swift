import Foundation
import Security

public protocol CredentialStoring: Sendable {
  func loadSession() throws -> StoredSession?
  func saveSession(_ session: StoredSession) throws
  func clearSession() throws
  func loadAPIKey() throws -> String?
  func saveAPIKey(_ apiKey: String) throws
  func clearAPIKey() throws
  func loadAdminAPIKey() throws -> String?
  func saveAdminAPIKey(_ apiKey: String) throws
  func clearAdminAPIKey() throws
  func clearAll() throws
}

public struct KeychainCredentialStore: CredentialStoring, Sendable {
  private enum Account {
    static let session = "panel-session"
    static let apiKey = "gateway-api-key"
    static let adminAPIKey = "admin-api-key"
  }

  private let service: String

  public init(service: String = "com.jihtsan.sub2api-monitor") {
    self.service = service
  }

  public func loadSession() throws -> StoredSession? {
    guard let data = try read(account: Account.session) else { return nil }
    do {
      return try JSONDecoder().decode(StoredSession.self, from: data)
    } catch {
      throw Sub2APIError.invalidResponse
    }
  }

  public func saveSession(_ session: StoredSession) throws {
    do {
      try write(JSONEncoder().encode(session), account: Account.session)
    } catch let error as Sub2APIError {
      throw error
    } catch {
      throw Sub2APIError.invalidResponse
    }
  }

  public func clearSession() throws {
    try delete(account: Account.session)
  }

  public func loadAPIKey() throws -> String? {
    guard let data = try read(account: Account.apiKey),
      let value = String(data: data, encoding: .utf8),
      !value.isEmpty
    else {
      return nil
    }
    return value
  }

  public func saveAPIKey(_ apiKey: String) throws {
    try write(Data(apiKey.utf8), account: Account.apiKey)
  }

  public func clearAPIKey() throws {
    try delete(account: Account.apiKey)
  }

  public func loadAdminAPIKey() throws -> String? {
    guard let data = try read(account: Account.adminAPIKey),
      let value = String(data: data, encoding: .utf8),
      !value.isEmpty
    else {
      return nil
    }
    return value
  }

  public func saveAdminAPIKey(_ apiKey: String) throws {
    try write(Data(apiKey.utf8), account: Account.adminAPIKey)
  }

  public func clearAdminAPIKey() throws {
    try delete(account: Account.adminAPIKey)
  }

  public func clearAll() throws {
    try clearSession()
    try clearAPIKey()
    try clearAdminAPIKey()
  }

  private func baseQuery(account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }

  private func read(account: String) throws -> Data? {
    var query = baseQuery(account: account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else {
      throw Sub2APIError.keychain(status: status)
    }
    guard let data = result as? Data else {
      throw Sub2APIError.invalidResponse
    }
    return data
  }

  private func write(_ data: Data, account: String) throws {
    let query = baseQuery(account: account)
    let update: [String: Any] = [kSecValueData as String: data]
    let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)

    if updateStatus == errSecItemNotFound {
      var insert = query
      insert[kSecValueData as String] = data
      let insertStatus = SecItemAdd(insert as CFDictionary, nil)
      guard insertStatus == errSecSuccess else {
        throw Sub2APIError.keychain(status: insertStatus)
      }
    } else if updateStatus != errSecSuccess {
      throw Sub2APIError.keychain(status: updateStatus)
    }
  }

  private func delete(account: String) throws {
    let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw Sub2APIError.keychain(status: status)
    }
  }
}
