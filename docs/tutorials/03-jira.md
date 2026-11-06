# Jira: drag tickets into TodayFlow

TodayFlow accepts tickets from the Jira web board and issue pages in Chrome, Safari, and other browsers.

1. Open your Jira board or issue page.
2. Drag a ticket card into the Today panel, a tray window, or the capture sheet.
3. TodayFlow reads the issue URL and card text.
   - The task title becomes **`ABC-123 · Fix the login timeout`**.
   - If the browser only provides the URL, the title falls back to **`ABC-123`**.
4. Save the task. The Jira URL is attached, and the issue key, project, and summary are stored as metadata.

## Supported Jira links

- `https://company.atlassian.net/browse/ABC-123`
- `https://company.atlassian.net/jira/software/projects/ABC/boards/1?selectedIssue=ABC-123`
- Self-hosted Jira using `/browse/KEY-123`
- Plain-text or HTML drag payloads from the browser

## Tips

- Drag multiple tickets one at a time.
- Dropping a Jira link onto an existing task row attaches it to that task instead of creating a new one.
- Use the project filter to keep Jira follow-ups together.
