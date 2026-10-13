# NeuroTrac Live (Mac)

> **A free, open follow-up tool for electrostimulation and EMG-biofeedback rehabilitation.**
> Unofficial · read-only · French 🇫🇷 and English 🇬🇧 interface and reports · [Version française](README.fr.md)

## Why this project
I am the parent of a child in neuromotor rehabilitation. We use a NeuroTrac MyoPlus Pro 4
(EMG, ETS, stimulation), but the device keeps no usable history: no progress curves, no report to show
the care team, no tracking of what we observe from one session to the next.
So I built, with the help of an AI (Claude), a Mac app that **reads** the device over Bluetooth
(read-only: it only sends the connection handshake, the PIN and a ping — never a setting) and stores everything
in a follow-up: automatically recorded sessions, thresholds in mA, EMG, tests, observations, electrode
placement photos and PDF reports.

This is a personal, experimental project. It is **not affiliated with the manufacturer**, it is **not a
medical device**, and nothing it shows is a diagnosis or a setting recommendation: everything must be
interpreted with the care team. "NeuroTrac" is a trademark of its owner and is only used here to say which
device the tool reads.

## Collaborate, suggest ideas
I am looking for feedback and help of all kinds:
- **Parents, physiotherapists, rehabilitation staff:** what would you miss in a follow-up? Which indicators,
  tests and report format would help in a consultation?
- **Developers:** SwiftUI, Bluetooth serial protocol, EMG signal processing, tests, portability
  (other Mac, Raspberry Pi, iPhone).
- **Users of other NeuroTrac devices** (MyoPlus, Bravo…): frame recordings to check that decoding also works for you.
- **Designers and game designers:** biofeedback games for children.
- **Translators:** the interface is French + English; other languages only need a dictionary
  (see `Sources/NeuroTracCore/Translations.swift`).

Open an *issue* for an idea, a question or a bug, or a *pull request*. Please **never** publish real health
data (session files, photos, PDFs): anonymize or invent.

### Ideas in progress (open for discussion)
- ETS trigger rate (stimulations obtained vs. possible cycles) and automatic conclusion;
- body map (muscles in 360°) to locate each measurement;
- biofeedback games on the TV, driven by EMG;
- video (camera, iPhone Continuity Camera) synchronized with EMG;
- reading the history stored inside the device (to be studied carefully);
- local summaries with an on-device model;
- iPhone app, or a Raspberry Pi server to browse the follow-up from home.

---

## Version 0.6 — bilingual (French / English)
The interface, messages and PDF reports are available in **French and English**. The language follows the
system language by default; change it in the left column (**Language: Auto / Français / English**).
Stored data stays in a canonical form (muscle and side names, CSV files, JSON), so files recorded in one
language open fine in the other. Free text you type is never translated. Program descriptions stored with a
session (rhythm, etc.) keep the language they were recorded in.

## What it does
Read-only live display of the NeuroTrac MyoPlus Pro 4 (EMG, stimulation, current program), plus the **follow-up**:
patient sheet, automatic session history, thresholds, progression, standardized EMG test, observations
(walking, foot), placement photos and PDF reports.
The app only ever sends to the device: HELO, the PIN code (1234 by default) and PING. No setting command.

## Requirements
- A Mac with macOS 13 or later and the Apple command line tools (`xcode-select --install`); Xcode is not required.
- A NeuroTrac MyoPlus Pro 4 paired in System Settings > Bluetooth (PIN 1234).

## Run
    git clone <this repository> && cd NeuroTracLive
    swift run

Choose "Bluetooth — Myo4Pro…", click Connect, wait for "Connected: reading in progress".

## Install as a real app (Dock / Applications)
    ./build_app.sh      # builds "NeuroTrac Live.app"
    ./update_app.sh     # rebuilds, keeps a copy of the old version, installs and relaunches
    ./update_app.sh --undo   # go back to the previous version

Your data is never touched by updates. First launch: right-click > Open; allow Bluetooth.

## Tabs
- **Live**: EMG, stimulation, program read from the device, **Record a threshold** box.
- **Sessions**: the history. Every program started on the device is recorded **automatically**
  (start when the program starts, end 8 s after it stops or on disconnection). Click a session to see its
  numbers and curves, fix muscle/side/note, add placement **photos**, create its **PDF report**.
  Automatic recordings shorter than 20 s are ignored.
- **Progression**: right vs. left curves over time (thresholds, max intensity, EMG, EMG test, observations,
  stimulation bursts, assessments), numeric trend, and a **follow-up PDF report** over 30 days, 90 days,
  6 months or the whole history.
- **Observations**: sheet to fill after a session (knee extension, foot lift, toes, leg, glutes scored 0–5
  right and left; goosebumps, sensations, steps, standing time…).
- **EMG test**: same protocol every time (10 s rest, then 3 contractions of 5 s separated by 10 s of rest, a beep
  at the start of each contraction). Result: rest, peak, mean, hold. Start an **EMG-only** program (no
  stimulation) on the device first. Below: pelvic floor assessments (B1/B2-type scores typed by hand).
- **Patient**: editable sheet (a fictional one is created at first launch).
- **Debug**: every packet received, byte by byte.

## Good to know
- The **muscle and side** in the left column are those assigned to the session that starts: change them
  **before** starting the program. They are remembered. You can fix them afterwards in the Sessions tab.
- **Threshold**: the app cannot guess when the foot moves. When you see the response, click "Record threshold":
  it takes the highest intensity received from the device in the last 5 seconds (or the value you type).
- **EMG "max"** is pulled by a few noisy values (up to 2000 µV in my test recording). To compare, use the
  **median** or the **95th percentile** (offered in Progression).
- **Stimulation bursts** = number of times the device sent current during the session (current resuming
  after at least 0.6 s of pause). In ETS this is the number of triggers obtained. A "obtained / possible"
  rate is not computed yet: it needs the exact ETS program (waiting for a real ETS recording).
- Anal probe: muscle "Anal sphincter (probe)" has no side; probe and reference electrode fields are saved with each session.

## Files (Documents/NeuroTracLive)
- `Suivi/`: `patient.json`, `seances.json`, `seuils.json`, `observations.json`, `tests_emg.json`,
  `evaluations.json`, `photos/`, `tests_bruts/`. Readable JSON; a `.bak` copy is kept at each write.
- `Rapports/`: the PDFs.
- session CSVs, `brut_….log`, `trames_….log`, `bibliotheque_programmes.json`.

(Folder and file names are in French for compatibility with existing data.)

## Tests
    swift test        # protocol, data, reports, translations (the UI is not covered)

## Reminders
Thresholds and EMG are follow-up measurements to be interpreted with a physiotherapist or doctor; a trend is
only meaningful with identical placement, program and device.
