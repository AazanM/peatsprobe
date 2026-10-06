# PeatsProbe — SOUNDPEATS Control

A native macOS SwiftUI app for the SOUNDPEATS Q3 Pro, talking to the earbuds
over Bluetooth Classic RFCOMM. The window follows the *SoundPEATS Control*
design file: a device sidebar, seven sections, and a light/dark palette taken
from the design tokens.

## Build and run

```sh
xcodebuild -project PeatsProbe.xcodeproj -scheme PeatsProbe -configuration Debug -derivedDataPath .build-xcode build
open .build-xcode/Build/Products/Debug/PeatsProbe.app
```

`project.yml` is the source of truth for the Xcode project. After adding or
removing a source file, run `xcodegen generate`.

## The rule the app follows

A control is only presented as working once **this Mac has read the value back
off the earbuds**. Nothing is inferred from the model name or from another
SOUNDPEATS product.

* Every setting change is one explicit, user-triggered write.
* A write is **never** retried.
* A live read-back follows every write — including when the earbuds apply the
  change without acknowledging it (1.2 s fallback).
* A setting whose read has never returned a value shows as **Unproven** and its
  write control stays disabled.

## Verified on this Q3 Pro (firmware S12_20251213_v0.0.39)

Left / right / case battery · firmware · noise-control mode (Normal, Noise
Cancelling, Transparency) · Game Mode · Multipoint · Touch Lock · Prompt volume.

## Not proven on this firmware

ANC strength, Transparency level, Voice package, LDAC, LE Audio, touch mapping,
equaliser, find-earbud. These appear in the UI with an **Unproven** badge and a
read button; the write stays locked until a real value comes back. The
equaliser presets are a Mac-side library only — they are not written to the
earbuds.

## Working a feature out without an Android phone

Developer → **Opcode discovery** exists so an unknown setting can be reverse
engineered here rather than by capturing the vendor's phone app:

1. **Passive listen** — opens the control channel and writes *nothing*. Press a
   stem gesture or change a mode on the earbuds; whatever frame they push is
   decoded into the protocol log. This is the safest and usually the fastest
   way to learn an opcode and its encoding.
2. **Single packet** — writes one operator-composed frame exactly once and
   shows every reply, so one guess can be tested in isolation.
3. **Opcode sweep** — sends each request opcode in a range once with an empty
   payload and records which ones the firmware answers.

Answered opcodes collect in **Answered opcodes**, and the **Feature support**
table shows what this specific firmware has actually proven.

A sweep range can contain setting-changing opcodes — on this protocol a write
generally sits one number above its matching read — so sweep narrow ranges and
keep the earbuds where you can hear them.

## Mac-side features

Menu-bar battery and quick controls · low-battery notifications · keyboard
shortcuts · app-launch automation rules (a real `NSWorkspace` launch watcher
that applies one already-verified setting) · locally measured listening time ·
a local EQ preset library.

`Window → Legacy Diagnostics` still opens the original raw diagnostic surface.
