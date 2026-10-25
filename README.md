# Fretbook

A minimal lesson-notes app for guitar teachers, made for iPad (iOS/iPadOS 17+).

- **Students**: each student gets their own page with level, weekly lesson slot, goals and contact info.
- **This Week**: your weekly schedule at a glance, with open homework for each student.
- **Lessons**: one card per lesson. Add notes in nine categories: Chord, Scale, Song, Technique, Rhythm, Riff/Tab, Theory, Homework and Note.
- **Music helpers**:
  - Chord diagrams drawn from shapes like `x32010`, with 20 common chords one tap away.
  - Strumming patterns like `D-DU-UDU`, shown as arrows with the beat counted underneath.
  - ASCII tab with an "insert empty staff" button.
  - Key and tempo (BPM) fields.
- **Filters**: tap a category chip on a student's page to see, for example, every chord they've learned.
- **Backups**: your data is one JSON file, visible in the Files app (On My iPad → Fretbook), with Export and Import in the sidebar's ••• menu.

You don't need a Mac or a paid Apple Developer account to build and install it.

---

## How it gets onto your iPad

```
Windows PC ── git push ──▶ GitHub Actions (free Mac) builds Fretbook.ipa
                                         │
                       download the .ipa ◀┘
                                         │
Sideloadly (Windows) signs it with your free Apple ID ──USB──▶ iPad
```

### One-time setup

1. **GitHub**: push this folder to a GitHub repo.
   - A public repo gets unlimited free build minutes.
   - A private repo also works, but macOS minutes count 10× against the 2,000 free minutes a month. That's roughly 40–50 builds a month.
2. **iTunes for Windows**: install the version from apple.com, **not** the Microsoft Store one. Sideloadly needs its USB drivers.
3. **Sideloadly**: install it from <https://sideloadly.io>.
4. **Apple ID**: any free Apple ID works. Using a separate one just for sideloading is a good idea.

### Each build

1. Push to `main`, or open the repo's **Actions** tab → **Build IPA** → **Run workflow**.
2. When it's green (about 3–5 min), open the run and download **Fretbook-ipa**. It's a zip, so unzip it to get `Fretbook.ipa`.
3. Connect the iPad by USB, open Sideloadly, drag in `Fretbook.ipa`, enter your Apple ID and press **Start**.
4. **First time only**, on the iPad:
   - Settings → General → VPN & Device Management → trust your Apple ID.
   - Settings → Privacy & Security → **Developer Mode** → on (the iPad restarts).

Installing a newer build the same way **updates the app and keeps your data**, as long as the bundle ID in `project.yml` never changes.

### The 7-day rule (free Apple ID)

Apps signed with a free Apple ID stop opening after **7 days**. Your notes are **not** lost. Just run Sideloadly again with the same `.ipa`, and it opens again with all your data.

To skip the PC, set up **SideStore** (<https://sidestore.io>). It refreshes the signature on the iPad itself.

Free accounts can have 3 sideloaded apps at a time.

---

## Project layout

| Path | What |
| --- | --- |
| `Fretbook/Models.swift` | Student, Lesson, NoteItem, note categories |
| `Fretbook/Store.swift` | Loading/saving the JSON file, import/export, first-launch example |
| `Fretbook/ContentView.swift` | Sidebar + navigation |
| `Fretbook/WeekView.swift` | Weekly schedule |
| `Fretbook/StudentPage.swift` | A student's page (homework, filters, lessons) |
| `Fretbook/LessonCard.swift` | One lesson and its notes |
| `Fretbook/NoteEditor.swift` | Add/edit a note, with chord/strum/tab tools |
| `Fretbook/MusicViews.swift` | Chord diagram, strum pattern, tab rendering |
| `project.yml` | XcodeGen spec (the Xcode project is generated on GitHub) |
| `.github/workflows/build.yml` | The cloud build |

If a build fails, open the failed run. Compiler errors are printed in the **Build (unsigned)** step, and the full log is attached as **build-log**.
