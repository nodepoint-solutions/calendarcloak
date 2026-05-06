# CalendarCloak

A macOS menu bar app that keeps your calendars in sync — without sharing your event details.

**Privacy-first.** Your calendar data never leaves your Mac. No account required, no cloud sync, no telemetry.

---

## Contents

- [Why](#why)
- [Privacy](#privacy)
- [Installation](#installation)
- [How it works](#how-it-works)
- [Settings](#settings)

---

## Why

If you have more than one calendar — a personal one and a work one, for example — your availability looks wrong to anyone checking either of them. Your work colleagues can't see you're busy at 3pm because that appointment is on your personal calendar. Your family can't see you're in a meeting because that's on your work calendar.

The usual workaround is to manually duplicate events across calendars, which is tedious and means sharing event titles and details you might not want to share.

CalendarCloak solves this by watching your selected calendars and creating anonymous **Busy** blocks in each one whenever you have an event in another. The blocks show only the time — no titles, locations, or descriptions are ever copied.

---

## Privacy

CalendarCloak is designed to keep your data on your device.

- **No account, no cloud.** CalendarCloak has no backend. Your events are read and written entirely on your Mac using the macOS Calendar framework — nothing is stored or synced anywhere else.
- **macOS native permissions.** On first launch, macOS will ask you to grant Calendar access using the standard system permission prompt. CalendarCloak can only read and write your calendars if you approve.
- **No titles, locations, or descriptions are ever copied.** Busy blocks contain only a start and end time.
- **Update checks are version-only.** CalendarCloak can check GitHub for new releases. This request contains nothing about you or your data — it is a plain version-number lookup. No identifiers are transmitted.

---

## Installation

Download the latest release from the [Releases](../../releases/latest) page.

Open the `.dmg`, drag **CalendarCloak** to your Applications folder, and launch it.

### macOS security prompt

CalendarCloak is not notarised. macOS may refuse to open it, or say the app is damaged. If that happens, run this in Terminal:

```bash
xattr -cr /Applications/CalendarCloak.app
```

Then try launching again. If macOS still blocks it, go to **System Settings → Privacy & Security** and click **Open Anyway**.

---

## How it works

On first launch, a setup wizard walks you through picking which calendars to keep in sync. You need at least two.

Once you've chosen, CalendarCloak shows a preview of the Busy blocks it would create for your upcoming events, so you can see exactly what will happen before committing. Click **Activate CalendarCloak** and it starts running in the background.

From then on, CalendarCloak watches for calendar changes and updates your Busy blocks automatically. It only looks at events you've accepted — declined or tentative invitations are ignored.

The app lives in your menu bar. It has no Dock icon and no windows open unless you need to change settings.

---

## Settings

Open Settings from the menu bar icon.

**Calendars** — add or remove calendars from the sync at any time. Removing a calendar also removes the Busy blocks it was providing to the others.

**Look-forward window** — how many days ahead CalendarCloak looks when creating blocks. The default covers a few weeks; you can extend it up to 90 days.

**Launch at login** — keeps CalendarCloak running in the background whenever you log in.

**Delete All Busy Events** — removes every Busy block from every calendar. Useful if you want to start fresh or stop using the app. If syncing is still active, the blocks will be recreated on the next calendar change.
