import Foundation

public struct ServerEndpoint: Sendable, Equatable {
  public let webBaseURL: URL
  public let apiBaseURL: URL
  public let gatewayBaseURL: URL

  public init(_ rawAddress: String) throws {
    let address = rawAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    guard var components = URLComponents(string: address),
      let scheme = components.scheme?.lowercased(),
      ["http", "https"].contains(scheme),
      components.host?.isEmpty == false,
      components.query == nil,
      components.fragment == nil
    else {
      throw Sub2APIError.invalidServerAddress
    }

    guard components.user == nil, components.password == nil else {
      throw Sub2APIError.insecureCredentialsInURL
    }

    components.scheme = scheme
    let basePath = Self.normalizedBasePath(components.path)

    components.path = basePath.isEmpty ? "/" : basePath
    guard let webBaseURL = components.url else {
      throw Sub2APIError.invalidServerAddress
    }

    components.path = Self.join(basePath, "api/v1")
    guard let apiBaseURL = components.url else {
      throw Sub2APIError.invalidServerAddress
    }

    components.path = Self.join(basePath, "v1")
    guard let gatewayBaseURL = components.url else {
      throw Sub2APIError.invalidServerAddress
    }

    self.webBaseURL = webBaseURL
    self.apiBaseURL = apiBaseURL
    self.gatewayBaseURL = gatewayBaseURL
  }

  public var isSecure: Bool { apiBaseURL.scheme == "https" }

  public var isLoopback: Bool {
    guard let host = apiBaseURL.host?.lowercased() else { return false }
    return host == "localhost" || host == "127.0.0.1" || host == "::1"
  }

  public var usesAcceptableTransport: Bool { isSecure || isLoopback }

  public func url(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
    try apiURL(path: path, queryItems: queryItems)
  }

  public func apiURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
    try Self.appending(path: path, queryItems: queryItems, to: apiBaseURL)
  }

  public func gatewayURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
    try Self.appending(path: path, queryItems: queryItems, to: gatewayBaseURL)
  }

  private static func normalizedBasePath(_ input: String) -> String {
    var path = input
    while path.count > 1 && path.hasSuffix("/") {
      path.removeLast()
    }
    if path == "/" { path = "" }

    let apiSuffix = "/api/v1"
    if path.lowercased().hasSuffix(apiSuffix) {
      path.removeLast(apiSuffix.count)
    }
    while path.count > 1 && path.hasSuffix("/") {
      path.removeLast()
    }
    return path == "/" ? "" : path
  }

  private static func join(_ basePath: String, _ component: String) -> String {
    let cleanComponent = component.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return basePath.isEmpty ? "/\(cleanComponent)" : "\(basePath)/\(cleanComponent)"
  }

  private static func appending(
    path: String,
    queryItems: [URLQueryItem],
    to baseURL: URL
  ) throws -> URL {
    let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let endpointURL = cleanPath.isEmpty ? baseURL : baseURL.appending(path: cleanPath)
    guard !queryItems.isEmpty else { return endpointURL }

    guard var components = URLComponents(url: endpointURL, resolvingAgainstBaseURL: false) else {
      throw Sub2APIError.invalidServerAddress
    }
    components.queryItems = queryItems
    guard let result = components.url else {
      throw Sub2APIError.invalidServerAddress
    }
    return result
  }
}
