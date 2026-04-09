---
name: Project architecture
description: aterm is a SwiftUI macOS terminal emulator built with XcodeGen; Swift flat namespace means file moves don't require import changes; project.yml uses path glob with Vendor/** exclude
type: project
---

aterm uses XcodeGen (`project.yml`) to generate `aterm.xcodeproj`. The main target sources from `path: aterm` excluding only `Vendor/**`. Swift compiles all sources in a flat namespace so moving files between directories within `aterm/` requires no import changes.

**Why:** This is load-bearing for evaluating refactoring specs -- file moves are purely organizational with no compile-time impact beyond regenerating the Xcode project.

**How to apply:** When reviewing file-move or directory-rename specs, focus on documentation/config accuracy rather than import chain analysis.
