/// Fetches a user profile from the remote server.
///
/// This method performs a network request to retrieve the user's details.
/// It automatically handles token refresh if the session has expired.
///
/// ```swift
/// do {
///     let user = try await UserManager.shared.fetchProfile(id: "u-123")
///     print("Hello, \(user.name)")
/// } catch {
///     print("Failed to load: \(error)")
/// }
/// ```
///
/// > Note: This method is thread-safe and can be called from any actor context.
///
/// - Parameters:
///   - id: The unique identifier of the user.
///   - includeHistory: If `true`, includes the user's login history. Defaults to `false`.
/// - Returns: A populated ``UserProfile`` object.
/// - Throws: ``NetworkError/timeout`` if the server doesn't respond, or ``AuthError/unauthorized`` if the session is invalid.
public func fetchProfile(id: String, includeHistory: Bool = false) async throws -> UserProfile