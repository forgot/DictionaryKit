/// Represents errors that can occur during the payment processing flow.
///
/// Use this error type to handle failures when interacting with ``PaymentService``.
public enum PaymentError: Error {

    /// The payment method was declined by the provider.
    ///
    /// - Parameter reason: The localized reason provided by the bank.
    case declined(reason: String)

    /// The network connection was lost during the transaction.
    ///
    /// > Warning: Do not retry immediately; wait for a backoff period.
    case networkFailure

    /// The transaction amount exceeds the user's daily limit.
    ///
    /// | Limit Type | Maximum |
    /// |:-----------|:--------|
    /// | Standard   | $1,000  |
    /// | Premium    | $5,000  |
    case limitExceeded
}