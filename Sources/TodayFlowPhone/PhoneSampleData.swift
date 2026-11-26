#if os(iOS)
import Foundation
import TodayFlowFeatures

/// Sample tasks for screenshots and first tests: launch with `-seedSample`.
/// The data itself is shared with the Mac (`SampleData`).
enum PhoneSampleData {
    @MainActor
    static func seedIfRequested(_ environment: PhoneEnvironment) async {
        await SampleData.seedIfRequested(workItems: environment.workItems, calendar: environment.workCalendar)
    }
}
#endif
