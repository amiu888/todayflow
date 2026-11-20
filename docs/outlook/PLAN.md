# Outlook integration plan

Status: plan only. Nothing is built until the owner says go.

## What already works

You can drag Outlook emails, `.msg` files, contacts and `ms-outlook://` links
into TodayFlow, and each becomes a task with a smart title.

## How it connects

TodayFlow talks to **Microsoft Graph**, Microsoft's official API for Outlook,
straight from the Mac app. The sign-in token stays in this Mac's keychain, so
the NAS server never sees mail. Only the tasks you create sync, the same as
any other task.

## Phases

1. **Sign in (read-only).** A new Settings ▸ Outlook tab with Sign in / Sign
   out, the account name, and an Outlook badge next to Server and Obsidian.
2. **Flagged emails become tasks.** An email you flag shows up in the Inbox
   within a minute, with a smart title (change and ticket numbers, a cleaned
   subject, and what the app has learned from your corrections). Each task
   links back to the email. Optional: completing the task clears the flag
   in Outlook (needs write access, behind its own switch).
3. **Calendar on Today.** Today's meetings appear as a strip in the Today view,
   with "Prep task" and "Follow-up" actions on each meeting.
4. *(Optional)* **Microsoft To Do two-way.** When the same task changes on
   both sides, the newest change wins.
5. *(Later)* **"Send to TodayFlow" add-in.** A button inside Outlook that sends
   an email to the TodayFlow server, so it also works from the web and phone.

First round: phases 1, 2 and 3.

## Phase 1 in detail

### One-time setup (done once by the owner)

- Register an app at entra.microsoft.com ▸ App registrations:
  - Supported accounts: *any organization's directory and personal accounts*.
  - Platform: *Mobile and desktop*, with redirect URI `todayflow://oauth`.
  - No client secret. A desktop app is a "public client", and its client ID
    is not a secret.
- Put the client ID in the ignored file `Config/outlook.env`. The build script
  copies it into `Info.plist`. No account details or tenant IDs go in source.

### Signing in

1. Settings ▸ Outlook ▸ **Sign in with Microsoft**.
2. TodayFlow opens Microsoft's own sign-in page in a secure system browser
   sheet (`ASWebAuthenticationSession`). Company SSO, MFA and passkeys all work
   there, and TodayFlow never sees your password.
3. Microsoft shows a consent screen listing what TodayFlow may read:
   - your profile (`User.Read`)
   - your mail, read-only (`Mail.Read`)
   - your calendar, read-only (`Calendars.Read`)
   - staying signed in (`offline_access`)

   Phase 1 asks for the mail and calendar permissions up front. That way, if
   the company blocks them, we find out now and not after building phases 2
   and 3.
4. Microsoft sends back a one-time code. TodayFlow exchanges it for tokens
   using PKCE (a random secret made for each sign-in, so a stolen code is
   useless).
5. TodayFlow calls `GET /me` and shows **Signed in as Alex (alex@example.com)**.

### Staying signed in

- The access token lasts about 1 hour and is kept only in memory.
- The refresh token goes in the keychain as `outlook_refresh_token`, and
  TodayFlow renews the access token silently.
- If Microsoft revokes it (password change, admin policy, roughly 90 days
  without use), the badge turns red: "Sign in again".
- **Sign Out** deletes the keychain item. Nothing else is stored.

### What you see

- **Not signed in:** one line on what the integration does, plus the
  Sign in button.
- **Signed in:** account name and email, the permissions granted, the last
  check time, and a Sign Out button.
- **Outlook badge** (only once signed in): green means connected, red means
  "sign in again" or "blocked by your organization", with the same popover as
  the other badges.
- **Errors in plain words**, for example:
  - "Your organization needs an admin to approve TodayFlow" (AADSTS65001 or
    90094), with the fallback options listed below.
  - "This Mac must be managed by your company to sign in" (Conditional
    Access). In that case we switch to Microsoft's MSAL library, which uses
    Company Portal single sign-on.

### Code

- New module `TodayFlowOutlook`:
  - `OutlookAuth`: PKCE, code exchange, refresh, and mapping errors to plain
    words.
  - `GraphClient` over a `GraphTransport` protocol, so tests can use a fake.
- `OutlookController` in the Mac target (`@Observable`, like `SyncController`).
- `OutlookSettingsSection` in TodayFlowFeatures, and an Outlook case in the
  sync badges.
- No new dependencies unless Conditional Access forces MSAL.

### Tests

- Unit tests: PKCE values, building the authorize URL, code exchange, refresh,
  revoked token, and the admin-approval error, all against a fake transport.
- Snapshot tests of the three settings states and the badge.
- An opt-in live test against a real account (environment variable, as with
  `LiveServerTests`).

## Fallback if the company blocks Graph

- **Calendar:** add the work account to macOS Calendar, and TodayFlow reads it
  with EventKit.
- **Flagged email:** this works through AppleScript only in *Legacy* Outlook.
  New Outlook for Mac can't be scripted.
- **Drag and drop** keeps working either way.
