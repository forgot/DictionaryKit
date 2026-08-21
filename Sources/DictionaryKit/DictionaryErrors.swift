import Foundation

/// Errors thrown by ``DictionaryService``.
///
/// The type conforms to `LocalizedError` as well as `CustomStringConvertible` so that
/// `error.localizedDescription` produces the same message as string interpolation.
/// Without the `LocalizedError` conformance, Foundation substitutes a generic
/// "The operation couldn't be completed" message for anything that crosses an
/// `Error` existential — which is how these errors reach most callers.
public enum DictionaryKitError: Error, CustomStringConvertible, LocalizedError, Sendable, Equatable
{
    case privateAPIsUnavailable
    case missingSymbol(String)
    case dictionaryUnavailable(String)
    case termNotFound(String)
    case dataUnavailable(String)

    public var description: String {
        switch self {
        case .privateAPIsUnavailable:
            return "Private DictionaryServices APIs are unavailable on this system."
        case .missingSymbol(let name):
            return "Missing DictionaryServices symbol: \(name)."
        case .dictionaryUnavailable(let name):
            return "Dictionary named \(name) is not available."
        case .termNotFound(let term):
            return "No entry found for term \(term)."
        case .dataUnavailable(let context):
            return "Dictionary data is unavailable: \(context)."
        }
    }

    public var errorDescription: String? { description }
}
