import Foundation

/// Joins a device's own trays and tray rules with the account's when the
/// device pairs (or pulls everything again), so neither side's trays are lost.
///
/// After that first pull the whole list syncs as one row, newest wins, which
/// is what lets a deleted or renamed tray stay deleted or renamed.
///
/// Rules: the account's trays come first, in their order. A local tray with
/// the same id, or the same name, adds its tasks to that tray; any other local
/// tray is added after them. A task already in one of the account's trays
/// stays there (a task lives in one tray). Local rules are added after the
/// account's and follow their trays.
enum SyncedSettingsMerge {
    typealias Object = [String: Any]

    struct Result {
        /// The merged value, or nil when the account's value already has
        /// everything this device had.
        var value: String?
        /// Local tray id → the account's tray it joined.
        var trayIds: [String: String] = [:]
    }

    static func trays(local: String, account: String?) -> Result {
        guard let localList = parse(local), !localList.isEmpty else { return Result() }
        guard let account, let accountList = parse(account), !accountList.isEmpty else {
            return Result(value: account == nil ? nil : local)
        }
        var merged = byOrder(accountList)
        var claimed = Set<String>()
        for index in merged.indices {
            var seen = Set<String>()
            let items = (merged[index]["itemIds"] as? [String] ?? []).filter { !claimed.contains($0) && seen.insert($0).inserted }
            claimed.formUnion(items)
            if merged[index]["itemIds"] != nil { merged[index]["itemIds"] = items }
        }
        var trayIds: [String: String] = [:]
        var changed = false
        for tray in byOrder(localList) {
            let items = (tray["itemIds"] as? [String] ?? []).filter { !claimed.contains($0) }
            let match = merged.firstIndex { other in
                if let id = tray["id"] as? String, other["id"] as? String == id { return true }
                return name(other) != nil && name(other) == name(tray)
            }
            if let match {
                if let from = tray["id"] as? String, let to = merged[match]["id"] as? String, from != to {
                    trayIds[from] = to
                }
                guard !items.isEmpty else { continue }
                merged[match]["itemIds"] = (merged[match]["itemIds"] as? [String] ?? []) + items
            } else {
                var added = tray
                if tray["itemIds"] != nil { added["itemIds"] = items }
                merged.append(added)
            }
            claimed.formUnion(items)
            changed = true
        }
        guard changed else { return Result(trayIds: trayIds) }
        for index in merged.indices { merged[index]["sortOrder"] = index }
        return Result(value: serialize(merged), trayIds: trayIds)
    }

    /// Tray rules: the account's, then this device's others, pointed at the
    /// trays they joined.
    static func rules(local: String, account: String?, trayIds: [String: String]) -> String? {
        guard let localList = parse(local), !localList.isEmpty else { return nil }
        guard let account, let accountList = parse(account) else { return account == nil ? nil : local }
        let known = Set(accountList.compactMap { $0["id"] as? String })
        var merged = accountList
        for var rule in localList where !((rule["id"] as? String).map(known.contains) ?? false) {
            for field in ["sourceTrayId", "targetTrayId"] {
                if let id = rule[field] as? String, let to = trayIds[id] { rule[field] = to }
            }
            merged.append(rule)
        }
        return merged.count == accountList.count ? nil : serialize(merged)
    }

    // MARK: - JSON

    private static func parse(_ json: String) -> [Object]? {
        (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [Object]
    }

    private static func serialize(_ list: [Object]) -> String? {
        (try? JSONSerialization.data(withJSONObject: list, options: [.sortedKeys]))
            .map { String(decoding: $0, as: UTF8.self) }
    }

    /// By `sortOrder`, keeping list order for ties and missing values.
    private static func byOrder(_ list: [Object]) -> [Object] {
        list.enumerated()
            .sorted { ($0.element["sortOrder"] as? Int ?? Int.max, $0.offset) < ($1.element["sortOrder"] as? Int ?? Int.max, $1.offset) }
            .map(\.element)
    }

    private static func name(_ tray: Object) -> String? {
        (tray["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
