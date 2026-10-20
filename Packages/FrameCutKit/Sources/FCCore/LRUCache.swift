/// 小容量 LRU 缓存：满了淘汰最久未用的一项（容量小，线性查找即可）。
public struct LRUCache<Key: Hashable, Value> {
    public let capacity: Int
    private var entries: [Key: (value: Value, used: UInt64)] = [:]
    private var clock: UInt64 = 0

    public init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    public var count: Int { entries.count }

    public subscript(key: Key) -> Value? {
        mutating get {
            guard let e = entries[key] else { return nil }
            clock &+= 1
            entries[key] = (e.value, clock)
            return e.value
        }
        set {
            guard let newValue else {
                entries[key] = nil
                return
            }
            clock &+= 1
            if entries[key] == nil, entries.count >= capacity,
               let oldest = entries.min(by: { $0.value.used < $1.value.used })?.key {
                entries[oldest] = nil
            }
            entries[key] = (newValue, clock)
        }
    }

    public func contains(_ key: Key) -> Bool { entries[key] != nil }

    public mutating func removeAll() {
        entries.removeAll()
    }
}
