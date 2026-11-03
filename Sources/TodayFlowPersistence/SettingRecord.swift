import Foundation
import GRDB

/// Maps a `setting` row (key / value_json) for the app settings store.
struct SettingRecord {
    var key: String
    var valueJson: String

    init(row: Row) {
        key = row["key"] as String
        valueJson = row["value_json"] as String
    }
}
