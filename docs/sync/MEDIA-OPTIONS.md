# Media sync options

Suggested 2026-11-19 after attachment files started syncing (schema v10).
The owner chose **1, 2 and 6** to build; 3, 4 and 5 are saved for later.
1, 2 and 6 were built and deployed the same day (app 1.9.26, server schema v3).

| # | Option | Status |
|---|---|---|
| 1 | Clean up deleted files | **Built** |
| 2 | Download big files on demand | **Built** |
| 3 | Storage limit per Mac | Later |
| 4 | Back up media to a second disk | Later |
| 5 | Storage on the admin page | Later |
| 6 | Raise the file limit to 1 GB | **Built** |

## 1. Clean up deleted files

Removing an attachment used to leave its file on the NAS and in every Mac's
`Attachments/Synced/` folder.

- **Each Mac:** a downloaded copy is deleted once no live attachment on that
  Mac uses the same file. Only copies in `Synced/`; never a Finder original or
  a copy the Mac made itself.
- **The NAS:** each night, a file no live attachment of its user refers to is
  marked; after 30 days still unreferenced, it is deleted (the grace period
  keeps undo, restores and in-flight uploads safe).

## 2. Download big files on demand

- Files up to 10 MB (images, emails, most PDFs) download right away, so
  previews and Quick Look work offline.
- Bigger files (videos, archives) download the first time they are opened.
  Until then the attachment shows a download icon and its size.

## 3. Storage limit per Mac (later)

A setting such as "Keep downloaded files: All / Last 90 days / Up to 5 GB".
Older copies are removed when over the limit and fetched again when opened.
Worth it once the media library reaches gigabytes.

## 4. Back up media to a second disk (later)

The nightly `pg_dump` covers rows only. A nightly incremental copy (rsync) of
`blobs/` to the backup disk (next to the database dumps) would give files a second
disk. Files never change once stored, so each night copies only new ones.

## 5. Storage on the admin page (later)

Files and space used per user, and the largest files.

## 6. Raise the file limit to 1 GB

Was 200 MB. Uploads and downloads stream to and from disk on both the Mac and
the server, so a large video never has to fit in memory (the server container
is limited to 256 MB).
