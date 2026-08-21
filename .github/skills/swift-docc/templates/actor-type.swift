/// A thread-safe cache for storing image data in memory.
///
/// `ImageCache` manages memory pressure automatically and evicts the least recently used
/// images when the limit is reached. It is an actor to ensure strict concurrency safety.
///
/// ## Topics
///
/// ### Configuration
/// - ``limit``
/// - ``policy``
///
/// ### Accessing Data
/// - ``image(for:)``
/// - ``insert(_:for:)``
public actor ImageCache {

    /// The maximum number of bytes the cache can hold.
    ///
    /// If the cache exceeds this limit, it triggers a cleanup based on the ``policy``.
    public let limit: Int

    // Implementation...
}