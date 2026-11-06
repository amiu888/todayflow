import Foundation

/// Public tutorial URLs used by the app menu and Settings. Keep these paths in
/// sync with `docs/tutorials/` in the repository.
public enum TutorialLinks {
    public static let index = URL(
        string: "https://github.com/amiu888/todayflow/tree/main/docs/tutorials"
    )!
    public static let gettingStarted = URL(
        string: "https://github.com/amiu888/todayflow/blob/main/docs/tutorials/01-getting-started.md"
    )!
    public static let contacts = URL(
        string: "https://github.com/amiu888/todayflow/blob/main/docs/tutorials/02-contacts.md"
    )!
    public static let jira = URL(
        string: "https://github.com/amiu888/todayflow/blob/main/docs/tutorials/03-jira.md"
    )!
    public static let localAI = URL(
        string: "https://github.com/amiu888/todayflow/blob/main/docs/tutorials/04-local-ai.md"
    )!
    public static let workflows = URL(
        string: "https://github.com/amiu888/todayflow/blob/main/docs/tutorials/05-workflows.md"
    )!
    public static let obsidian = URL(
        string: "https://github.com/amiu888/todayflow/blob/main/docs/tutorials/07-obsidian.md"
    )!
    public static let video = URL(
        string: "https://github.com/amiu888/todayflow/blob/main/docs/tutorials/video/todayflow-overview.mp4"
    )!
}
