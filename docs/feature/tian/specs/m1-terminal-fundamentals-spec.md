# SPEC: M1 -- Terminal Fundamentals

**Based on:** docs/feature/tian/tian-prd.md v1.4 (Milestone 1)
**Author:** CTO Agent
**Date:** 2026-03-24
**Version:** 1.0
**Status:** Draft

---

## 1. Overview

This spec covers Milestone 1 of tian: a single-window, single-pane GPU-accelerated terminal emulator for macOS. The deliverable is a functional terminal that spawns the user's default shell via POSIX PTY, parses VT escape sequences through libghostty-vt (C ABI), renders text on the GPU via Metal with a font atlas and instanced draw calls, handles keyboard input and text selection with copy/paste, provides a configurable scrollback buffer with smooth scrolling, renders Unicode correctly (including wide and combining characters), and supports a basic color scheme.

This milestone produces the foundation that all subsequent milestones (pane splitting, tabs, workspaces, persistence, configuration) build upon. The architecture must therefore be designed for extensibility even though M1 ships only a single pane in a single window.

**Functional requirements covered:** FR-11 through FR-21, FR-32 through FR-34.

**Tech stack:** Swift 6, SwiftUI (window chrome only), libghostty-vt (C ABI, linked as a static library), Metal (GPU rendering), Core Text (font rasterization), POSIX PTY APIs, macOS 26+.

---

## 2. High-Level Architecture

The system decomposes into five major layers, each running on its own dispatch context to avoid blocking:

| Layer | Responsibility | Thread/Queue | Key Types |
|-------|---------------|--------------|-----------|
| **App Shell** | SwiftUI window, menu bar, toolbar | Main thread | `TianApp`, `TerminalWindow`, `TerminalView` |
| **Terminal Core** | Owns libghostty-vt terminal instance, processes PTY output, encodes keyboard/mouse input | Dedicated serial queue (`terminal-core`) | `TerminalCore`, `GhosttyBridge` |
| **PTY I/O** | Spawns shell, reads/writes file descriptors | Dedicated I/O queue (`pty-io`) + DispatchSource for reads | `PTYProcess`, `PTYFileHandle` |
| **Renderer** | Metal rendering pipeline: font atlas, cell buffer, draw calls | Render thread (CAMetalLayer display link) | `TerminalRenderer`, `FontAtlas`, `CellBuffer`, `GridSnapshot` |
| **Selection** | Track selection state, hit-testing, clipboard | Main thread (UI-driven) | `SelectionState`, `SelectionRange` |

### Data Flow (steady-state)

1. **Shell produces output** -- PTY read source fires on pty-io queue, delivers raw bytes.
2. **VT parsing** -- Bytes are forwarded to `ghostty_terminal_vt_write()` on the terminal-core queue. libghostty-vt updates its internal terminal state (grid, cursor, styles, scrollback).
3. **Render state update** -- After VT write, `ghostty_render_state_update()` is called to sync the render state from the terminal. The dirty flag is checked.
4. **Snapshot extraction** -- If dirty, the renderer extracts a `GridSnapshot` (rows, cells, styles, cursor, colors) from the render state API while holding the terminal-core lock. This snapshot is an immutable value type.
5. **GPU rendering** -- On the render thread (driven by display link), the snapshot is consumed to build per-instance cell data, uploaded to Metal buffers, and drawn via instanced draw calls.
6. **Display** -- The CAMetalLayer presents the drawable.

### Data Flow (keyboard input)

1. **Key event** -- SwiftUI/NSEvent delivers key event on main thread.
2. **Encoding** -- `ghostty_key_encoder_encode()` converts the key event to a VT escape sequence on the terminal-core queue.
3. **PTY write** -- Encoded bytes are written to the PTY master file descriptor.
4. **Echo** -- The shell echoes characters back through the normal output path.

---

## 3. Project Structure

All source code lives under a single Xcode project. The directory layout follows a layer-based organization:

```
tian/
  tian.xcodeproj/
  tian/
    App/
      TianApp.swift                 -- @main, app lifecycle, menu bar
      TerminalWindow.swift           -- NSWindow subclass or SwiftUI WindowGroup
    Bridge/
      GhosttyBridge.swift            -- Swift wrapper around libghostty-vt C API
      GhosttyTypes.swift             -- Swift equivalents of C structs/enums
      libghostty_vt_bridging.h       -- Bridging header importing ghostty/vt.h
    Core/
      TerminalCore.swift             -- Owns terminal + render state, orchestrates I/O
      PTYProcess.swift               -- PTY fork/exec, file descriptor management
      PTYFileHandle.swift            -- DispatchSource-based async read/write
    Renderer/
      TerminalRenderer.swift         -- Metal rendering orchestrator
      FontAtlas.swift                -- Core Text rasterization, texture atlas packing
      CellBuffer.swift               -- Per-instance data buffer management
      GridSnapshot.swift             -- Immutable snapshot of terminal grid state
      Shaders.metal                  -- Vertex and fragment shaders
      ShaderTypes.h                  -- Shared C types between Swift and Metal
    Selection/
      SelectionState.swift           -- Selection tracking (anchor, extent, mode)
      SelectionRange.swift           -- Grid coordinate range, text extraction
    View/
      TerminalContentView.swift      -- NSViewRepresentable wrapping the Metal layer
      TerminalMetalView.swift        -- NSView subclass hosting CAMetalLayer
    Theme/
      ColorScheme.swift              -- Color palette definition (16 ANSI + bg/fg/cursor)
      DefaultThemes.swift            -- Built-in color schemes
    Utilities/
      Logger.swift                   -- os.Logger wrappers for subsystem logging
      PerformanceCounters.swift      -- Frame time, shell spawn latency tracking
  Resources/
    default.metallib                 -- Compiled Metal shaders (built by Xcode)
```

---

## 4. libghostty-vt Integration (C ABI Bridge)

### 4.1 Linking Strategy

libghostty-vt is linked as a **pre-built static library** (`libghostty_vt.a`). The library's C headers are imported via a bridging header. The library is zero-dependency (no libc required), which simplifies linking.

The bridging header (`libghostty_vt_bridging.h`) imports `<ghostty/vt.h>`, which transitively includes all sub-headers (terminal, render, screen, style, key, mouse, color, etc.).

### 4.2 GhosttyBridge -- Swift Wrapper

`GhosttyBridge` provides a Swift-idiomatic interface over the raw C API. It is **not** a general-purpose wrapper -- it exposes only the subset of libghostty-vt used by tian. Key design principles:

- All C pointer types are wrapped in Swift classes with RAII-style `deinit` calling the corresponding `ghostty_*_free()`.
- The `GhosttyAllocator` is configured to use Swift's default allocator (or a custom one for tracking allocations in debug builds).
- All `GhosttyResult` return values are checked and converted to Swift errors via a `GhosttyError` enum.
- Opaque handle types (`GhosttyTerminal`, `GhosttyRenderState`, etc.) are stored as `OpaquePointer` inside Swift wrapper classes.

### 4.3 Key Bridge Types

| C Type | Swift Wrapper | Lifecycle |
|--------|--------------|-----------|
| `GhosttyTerminal` | `Terminal` (nested in `GhosttyBridge`) | Created in `TerminalCore.init`, freed in `deinit` |
| `GhosttyRenderState` | `RenderState` | Created alongside Terminal, freed in `deinit` |
| `GhosttyRenderStateRowIterator` | `RowIterator` | Created per snapshot extraction, freed after iteration |
| `GhosttyRenderStateRowCells` | `CellIterator` | Created per row during snapshot, freed after row iteration |
| `GhosttyKeyEncoder` (from key/encoder.h) | `KeyEncoder` | Long-lived, one per TerminalCore |
| `GhosttyMouseEncoder` (from mouse/encoder.h) | `MouseEncoder` | Long-lived, one per TerminalCore |

### 4.4 Terminal Initialization

When a `TerminalCore` is created, the bridge performs the following sequence:

1. Create a `GhosttyAllocator` struct (pointing to Swift malloc/free or the default null allocator for libghostty's built-in allocator).
2. Call `ghostty_terminal_new()` with `GhosttyTerminalOptions` specifying initial columns, rows, and max scrollback (default 10,000 lines per FR-14).
3. Call `ghostty_render_state_new()` to create the render state object.
4. Create a `KeyEncoder` via `ghostty_key_encoder_new()` and sync its options from the terminal via `ghostty_key_encoder_setopt_from_terminal()`.
5. Create a `MouseEncoder` similarly.

### 4.5 Processing Output

When bytes arrive from the PTY, they are passed to `ghostty_terminal_vt_write(terminal, buffer, length)`. This is the single entry point for all VT processing. libghostty-vt handles all escape sequence parsing, cursor movement, style application, scrollback management, alternate screen buffer, and terminal mode changes internally.

### 4.6 Extracting Render State

After a VT write, the bridge calls `ghostty_render_state_update(renderState, terminal)` to sync. It then queries `GHOSTTY_RENDER_STATE_DATA_DIRTY` to determine if re-rendering is needed:

- `DIRTY_FALSE` -- no visual change, skip rendering.
- `DIRTY_PARTIAL` -- some rows changed, can optimize (though M1 may full-redraw).
- `DIRTY_FULL` -- complete redraw needed.

To build a snapshot, the bridge iterates rows via `ghostty_render_state_row_iterator_new()`, and for each row iterates cells via `ghostty_render_state_row_cells_new()`. For each cell, it extracts: codepoint (or grapheme cluster via `ghostty_grid_ref_graphemes()`), style (fg/bg color, bold, italic, underline, strikethrough, inverse, wide character flag). The snapshot also captures cursor position, cursor style, cursor visibility, and the resolved color palette.

---

## 5. PTY Management

### 5.1 PTYProcess

`PTYProcess` encapsulates the fork/exec lifecycle for spawning a shell connected to a pseudo-terminal.

**Spawn sequence:**

1. Call `openpty()` to obtain master and slave file descriptors.
2. `fork()` to create a child process.
3. In the child process:
   - Call `setsid()` to create a new session.
   - Call `ioctl(slaveFD, TIOCSCTTY, 0)` to set the controlling terminal.
   - Duplicate slave FD to stdin, stdout, stderr via `dup2()`.
   - Close the master FD and the original slave FD.
   - Set environment variables: `TERM=xterm-256color`, `COLORTERM=truecolor`, `LANG` (inherit from parent), `COLUMNS` and `LINES` matching the initial terminal size.
   - Determine the user's default shell: read `SHELL` environment variable; fall back to `passwd` entry via `getpwuid(getuid())`.
   - `execvp()` the shell as a login shell (argv[0] prefixed with `-`).
4. In the parent process:
   - Close the slave FD.
   - Store the master FD and child PID.
   - Create a `PTYFileHandle` wrapping the master FD.

**Resize:**

When the pane dimensions change, `PTYProcess` calls `ioctl(masterFD, TIOCSWINSZ, &winsize)` with the new column and row counts, then sends `SIGWINCH` to the child process group. Concurrently, `ghostty_terminal_resize(terminal, newCols, newRows)` is called on the terminal-core queue so libghostty-vt reflows its internal state.

**Teardown:**

On pane close, `PTYProcess` sends `SIGHUP` to the child process group, closes the master FD, and waits for the child to exit via `waitpid()` with `WNOHANG` polling (or a dispatch source on the process).

### 5.2 PTYFileHandle

Wraps the master file descriptor with async I/O:

- **Read:** A `DispatchSource.makeReadSource()` on the master FD fires whenever data is available. The handler reads into a pre-allocated buffer (suggested size: 64 KB) via `read()` and delivers the bytes to `TerminalCore` for VT processing.
- **Write:** A simple `write()` call on the master FD. Since shell input is low-volume and low-latency, synchronous write on the terminal-core queue is acceptable for M1. If the write would block, buffer and retry via a write source (unlikely for keyboard input volumes).

### 5.3 Shell Exit Handling

A `DispatchSource.makeProcessSource()` monitors the child PID for exit. On exit:

- Read the exit status via `waitpid()`.
- If exit code is 0: the pane should close (FR-25 will be fully implemented in M7, but the detection mechanism is built in M1).
- If exit code is non-zero: retain the pane and display the exit code. For M1, a simple text overlay or appended line in the terminal is sufficient.

---

## 6. Metal Rendering Pipeline

### 6.1 Architecture Overview

The renderer follows Ghostty's proven multi-pass instanced rendering approach, adapted for Swift and the single-pane M1 scope:

| Pass | Purpose | Instance Type | Shader |
|------|---------|---------------|--------|
| 1. Background | Cell background colors | `CellBackground` | `cellBgVertex` / `cellBgFragment` |
| 2. Text | Glyph rendering from font atlas | `CellText` | `cellTextVertex` / `cellTextFragment` |
| 3. Cursor | Cursor rendering (block/underline/bar) | `CursorInstance` | `cursorVertex` / `cursorFragment` |
| 4. Selection | Selection highlight overlay | Reuses background pass with selection color | Same as pass 1 |

Passes are rendered back-to-front with appropriate alpha blending.

### 6.2 TerminalRenderer

`TerminalRenderer` owns the Metal device, command queue, pipeline states, and buffers. It is driven by a `CADisplayLink` (or `CVDisplayLink` on macOS) callback.

**Per-frame sequence:**

1. Check if a new `GridSnapshot` is available (atomic swap from the terminal-core queue).
2. If no new snapshot and no animation (e.g., cursor blink) is pending, skip the frame.
3. Build instance data arrays from the snapshot (background instances, text instances, cursor instance).
4. Upload instance data to Metal buffers (triple-buffered to avoid CPU/GPU contention).
5. Create a command buffer and render command encoder.
6. For each pass: set the pipeline state, bind the uniform buffer and instance buffer, issue `drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: N)`.
7. Present the drawable.

**Triple buffering:** Three sets of instance buffers are maintained, cycling via a semaphore with value 3. This prevents the CPU from writing to a buffer the GPU is still reading.

### 6.3 Uniform Buffer

A single uniform struct is shared across all shaders (passed as a constant buffer):

| Field | Type | Description |
|-------|------|-------------|
| `projectionMatrix` | `float4x4` | Orthographic projection mapping pixel coordinates to NDC |
| `screenSize` | `float2` | Render target size in pixels |
| `cellSize` | `float2` | Cell dimensions in pixels (width = glyph advance, height = line height) |
| `gridSize` | `uint2` | Terminal grid dimensions (columns, rows) |
| `gridPadding` | `float4` | Padding around the grid (top, right, bottom, left) |
| `cursorPos` | `uint2` | Cursor column and row |
| `cursorColor` | `float4` | Cursor color (RGBA) |
| `backgroundColor` | `float4` | Default background color |
| `cursorStyle` | `uint` | 0 = block, 1 = underline, 2 = bar |
| `cursorVisible` | `bool` | Whether cursor is currently visible (accounts for blink state) |

### 6.4 Instance Data Structures

**CellBackground** (8 bytes per instance):

| Field | Type | Description |
|-------|------|-------------|
| `gridPos` | `ushort2` | Column and row in the grid |
| `color` | `uchar4` | RGBA background color |

**CellText** (32 bytes per instance):

| Field | Type | Description |
|-------|------|-------------|
| `glyphPos` | `float2` | UV origin in the font atlas texture |
| `glyphSize` | `float2` | UV extent in the font atlas texture |
| `bearings` | `float2` | Horizontal and vertical bearing offsets |
| `glyphPixelSize` | `float2` | Glyph dimensions in pixels |
| `gridPos` | `ushort2` | Column and row in the grid |
| `color` | `uchar4` | RGBA foreground color |
| `flags` | `uint8` | Bit flags: bold, wide char, etc. |

**CursorInstance** (12 bytes):

| Field | Type | Description |
|-------|------|-------------|
| `gridPos` | `ushort2` | Column and row |
| `color` | `uchar4` | Cursor color RGBA |
| `style` | `uint8` | Block, underline, or bar |
| `cellWidth` | `uint8` | 1 for normal, 2 for wide character cells |

### 6.5 Shader Design

All shaders use a triangle strip of 4 vertices to form a quad. The vertex shader positions each quad based on the grid position and cell size from the uniform buffer, plus per-instance offsets (bearings for text). The fragment shader either samples the font atlas texture (text pass) or outputs a solid color (background/cursor pass).

**Text fragment shader:** Samples the grayscale font atlas at the interpolated UV coordinate. The sampled alpha value is multiplied by the instance's foreground color. For color emoji (future), a separate RGBA atlas texture would be sampled instead, selected by a flag in the instance data.

**Background fragment shader:** Outputs the instance's background color directly. Skips instances where the background color matches the default background (optimization to reduce overdraw).

**Cursor fragment shader:** Renders the cursor shape based on the style field:
- Block: full cell quad with the cursor color (optionally with alpha for unfocused/hollow).
- Underline: a thin rectangle at the bottom of the cell (height = 2 pixels or configurable).
- Bar: a thin rectangle at the left edge of the cell (width = 2 pixels or configurable).

### 6.6 Cursor Blinking

Cursor blink is driven by a timer on the renderer. When the terminal reports `cursor_blinking = true`, the renderer toggles the `cursorVisible` uniform on a 500ms interval (configurable). This does not require a new snapshot -- only the uniform buffer is updated, making blink frames extremely cheap.

---

## 7. Font Atlas

### 7.1 FontAtlas

`FontAtlas` manages the rasterization of glyphs into a GPU texture atlas using Core Text.

**Atlas layout:** A single MTLTexture (initial size 1024x1024, format `.r8Unorm` for grayscale glyphs). Glyphs are packed using a simple shelf-packing algorithm: rows of fixed height (line height), filled left-to-right. When a shelf is full, a new shelf starts below. When the texture is full, a new texture is allocated at double the size and existing glyphs are re-packed (this should be rare with typical terminal usage).

**Glyph cache:** A dictionary mapping `GlyphKey` (codepoint + style flags: bold, italic) to `GlyphInfo` (atlas position, size, bearings). Cache lookup is O(1).

**Rasterization pipeline:**

1. For a given codepoint and style, check the glyph cache. If found, return cached `GlyphInfo`.
2. If not cached: use `CTFontCreateWithName()` to get the font reference (cached). Apply bold/italic traits via `CTFontCreateCopyWithSymbolicTraits()`.
3. Create a `CTLine` from an attributed string containing the character.
4. Get glyph bounds via `CTLineGetBoundsWithOptions()`.
5. Create a CGContext backed by a temporary bitmap, draw the glyph via `CTLineDraw()`.
6. Copy the bitmap data into the atlas texture at the next available position via `MTLTexture.replace(region:...)`.
7. Store the `GlyphInfo` in the cache and return it.

**Cell size calculation:** On font change, rasterize a reference character (e.g., `M`) to determine cell width (advance width) and cell height (ascent + descent + leading). All grid arithmetic uses these fixed cell dimensions. Wide (CJK) characters occupy two cell widths.

### 7.2 Font Configuration

For M1, font family and size are hardcoded constants with the intent to make them configurable in M6. Suggested defaults:

- Font family: `"SF Mono"` (system monospace) or `"Menlo"` as fallback.
- Font size: 13.0 points.
- Line height multiplier: 1.2.

The `FontAtlas` accepts these as initialization parameters so they can be driven by configuration later.

---

## 8. Grid Snapshot

### 8.1 GridSnapshot

`GridSnapshot` is an immutable, self-contained value type that captures the visual state of the terminal at a point in time. It decouples the renderer from the terminal-core queue, allowing rendering to proceed without holding locks.

**Contents:**

| Field | Type | Description |
|-------|------|-------------|
| `columns` | `Int` | Grid width |
| `rows` | `Int` | Grid height |
| `cells` | `[SnapshotCell]` | Flat array of cells, row-major order (length = columns x rows) |
| `cursorPosition` | `GridPosition` (col, row) | Cursor location in viewport |
| `cursorStyle` | `CursorStyle` enum | Block, underline, bar |
| `cursorVisible` | `Bool` | Whether cursor should be drawn |
| `cursorBlinking` | `Bool` | Whether cursor should blink |
| `palette` | `ColorPalette` | 256-color palette + fg/bg/cursor colors |
| `dirtyState` | `DirtyState` enum | Full, partial, or none |

**SnapshotCell:**

| Field | Type | Description |
|-------|------|-------------|
| `codepoint` | `Unicode.Scalar` | Primary codepoint (0 for empty cell) |
| `graphemeExtension` | `[Unicode.Scalar]?` | Additional codepoints for combining characters (nil if none) |
| `style` | `CellStyle` | Foreground color, background color, bold, italic, underline, strikethrough, inverse, faint, wide flag |
| `wideFlag` | `CellWide` enum | Narrow, wide, spacerTail, spacerHead |

### 8.2 Snapshot Extraction

Snapshot extraction runs on the terminal-core queue (serialized with VT writes). The process:

1. Call `ghostty_render_state_update(renderState, terminal)`.
2. Query dirty state. If `DIRTY_FALSE`, reuse previous snapshot (or signal no-update to renderer).
3. Query cols, rows, cursor data, palette via `ghostty_render_state_get()` and `ghostty_render_state_colors_get()`.
4. Create a row iterator. For each row, create a cell iterator. For each cell, extract codepoint, wide flag, style ID, and resolved fg/bg colors. If the cell has a grapheme cluster, extract additional codepoints via `ghostty_render_state_row_cells_get()` with `GRAPHEMES_BUF`.
5. Pack into a `GridSnapshot` and publish to the renderer via an atomic reference swap (e.g., `OSAllocatedUnfairLock`-protected property, or a lock-free single-producer/single-consumer handoff).
6. Mark the render state as clean via `ghostty_render_state_set()` with `GHOSTTY_RENDER_STATE_OPTION_DIRTY`.

---

## 9. Text Selection

### 9.1 SelectionState

`SelectionState` tracks an active text selection across the terminal grid.

**Selection modes:**

| Mode | Trigger | Unit |
|------|---------|------|
| Character | Single click + drag, or Shift+Arrow | Individual cells |
| Word | Double-click (+ optional drag) | Word boundaries (whitespace/punctuation delimited) |
| Line | Triple-click (+ optional drag) | Entire rows |

**State fields:**

| Field | Type | Description |
|-------|------|-------------|
| `anchor` | `GridPosition?` | Where selection started (nil = no selection) |
| `extent` | `GridPosition?` | Where selection currently ends |
| `mode` | `SelectionMode` | Character, word, or line |
| `isActive` | `Bool` | Whether a drag is in progress |

### 9.2 Hit Testing

Mouse coordinates (in pixels) are converted to grid positions using: `col = floor((x - gridPadding.left) / cellWidth)`, `row = floor((y - gridPadding.top) / cellHeight)`. Clamped to valid grid bounds.

For Shift+Arrow keyboard selection, the extent moves by one cell in the arrow direction (or by word/line boundaries if combined with Option/Cmd modifiers).

### 9.3 Selection Rendering

Selected cells are rendered with inverted colors (swap foreground and background) or with a translucent highlight overlay. The approach for M1: during the background pass, cells within the selection range use the selection highlight color instead of their normal background. During the text pass, foreground color is swapped to the normal background color for selected cells. This matches standard terminal selection behavior.

### 9.4 Copy (Cmd+C)

When the user presses Cmd+C with an active selection:

1. Iterate the grid snapshot cells within the selection range (top-left to bottom-right, row by row).
2. For each cell, append its codepoint (and grapheme extension if present) to a String.
3. At the end of each row within the selection (unless the row is wrapped), append a newline.
4. Write the resulting string to `NSPasteboard.general` using `setString(_:forType: .string)`.
5. Optionally clear the selection after copy (configurable behavior for M6; M1 clears it).

### 9.5 Paste (Cmd+V)

When the user presses Cmd+V:

1. Read from `NSPasteboard.general` via `string(forType: .string)`.
2. If the terminal has bracketed paste mode enabled (tracked by libghostty-vt), wrap the text in `\e[200~` ... `\e[201~` escape sequences.
3. Write the (possibly bracketed) bytes to the PTY master FD.

Paste safety validation can use `ghostty_paste_is_safe()` from libghostty-vt to check for potentially dangerous sequences in pasted text.

---

## 10. Scrollback and Smooth Scrolling

### 10.1 Scrollback Buffer

libghostty-vt manages the scrollback buffer internally. The `max_scrollback` parameter in `GhosttyTerminalOptions` controls the limit (default: 10,000 lines per FR-14). When lines scroll off the top of the viewport, libghostty-vt moves them into its internal scrollback storage. No separate scrollback data structure is needed on the Swift side.

### 10.2 Viewport Scrolling

The terminal viewport is controlled via `ghostty_terminal_scroll_viewport()`:

- `GHOSTTY_SCROLL_VIEWPORT_DELTA(n)` -- scroll by n lines (negative = up, positive = down).
- `GHOSTTY_SCROLL_VIEWPORT_TOP` -- jump to top of scrollback.
- `GHOSTTY_SCROLL_VIEWPORT_BOTTOM` -- jump to bottom (live terminal output).

### 10.3 Smooth Scrolling

To achieve 60fps smooth scrolling (FR-15), scroll events from the trackpad or scroll wheel are handled as follows:

1. **Trackpad/scroll wheel events** deliver continuous pixel deltas via `NSEvent.scrollingDeltaY`.
2. Convert pixel delta to fractional line offset: `lineDelta = pixelDelta / cellHeight`.
3. Accumulate the fractional offset. When the accumulated offset crosses a whole line boundary, call `ghostty_terminal_scroll_viewport()` with `DELTA` of the integer part and retain the fractional remainder.
4. Between whole-line scrolls, the renderer applies a sub-line pixel offset to the grid rendering. This is done by adjusting the Y component of the grid origin in the uniform buffer's projection matrix (or a dedicated `scrollPixelOffset` uniform field).
5. This produces per-pixel smooth scrolling while libghostty-vt's viewport advances in whole-line increments.

**Momentum scrolling:** macOS provides momentum events natively via the trackpad. These arrive as additional scroll events with `momentumPhase != .none`. No special handling is needed -- the same accumulation logic applies.

### 10.4 Scroll Position Indicator

The renderer can display a scrollbar or scroll position indicator using the `GhosttyTerminalScrollbar` struct returned by querying `GHOSTTY_TERMINAL_DATA_SCROLLBAR`: total lines, current offset, and viewport length. For M1, a minimal overlay scrollbar (similar to macOS native) is sufficient. It appears on scroll and fades after inactivity.

---

## 11. Unicode Rendering

### 11.1 Multi-byte Characters

libghostty-vt handles all UTF-8 decoding internally. By the time cells reach the snapshot, each cell contains a Unicode scalar value (codepoint). Multi-byte UTF-8 sequences are already decoded.

### 11.2 Combining Characters

Cells with combining characters (e.g., `e` + combining acute accent) are represented as a base codepoint plus a grapheme extension array. The font atlas rasterizes the complete grapheme cluster as a single glyph image by passing the full character sequence to Core Text's `CTLine`. This ensures correct rendering of combining marks, including those that alter the base glyph's shape.

### 11.3 Wide (CJK) Characters

Wide characters occupy two cells. libghostty-vt marks the first cell as `GHOSTTY_CELL_WIDE_WIDE` and the second as `GHOSTTY_CELL_WIDE_SPACER_TAIL`. The renderer:

- For the wide cell: uses a glyph entry that spans 2x cell width. The `CellText` instance's `glyphPixelSize.x` is `2 * cellWidth` (or the actual glyph width if narrower), and the shader stretches the quad accordingly.
- For the spacer tail cell: skips rendering (no background or text instance emitted, since the wide cell's quad already covers it).

### 11.4 Emoji

For M1, emoji rendering uses Core Text's built-in emoji font (Apple Color Emoji). Emoji glyphs are rasterized into a separate RGBA atlas texture (format `.bgra8Unorm`) rather than the grayscale text atlas. The text shader selects between the grayscale and color atlas based on a flag in the `CellText` instance data.

---

## 12. Color Scheme Support

### 12.1 ColorPalette

A `ColorPalette` struct holds the complete color state for a terminal:

| Field | Type | Description |
|-------|------|-------------|
| `foreground` | `SIMD4<UInt8>` | Default foreground (RGBA) |
| `background` | `SIMD4<UInt8>` | Default background (RGBA) |
| `cursor` | `SIMD4<UInt8>` | Cursor color |
| `selection` | `SIMD4<UInt8>` | Selection highlight color |
| `ansi` | `[SIMD4<UInt8>]` (16 entries) | Standard 8 colors + 8 bright variants |
| `palette256` | `[SIMD4<UInt8>]` (240 entries) | Extended 256-color palette (indices 16-255) |

### 12.2 Color Resolution

When building the `GridSnapshot`, cell colors are resolved from the libghostty-vt style as follows:

- `GHOSTTY_STYLE_COLOR_NONE` -- use the palette's default foreground or background.
- `GHOSTTY_STYLE_COLOR_PALETTE` -- index into the 256-color palette.
- `GHOSTTY_STYLE_COLOR_RGB` -- use the RGB value directly (true color, FR-13).

If the cell has the `inverse` style flag set, foreground and background colors are swapped after resolution.

If the cell has the `faint` style flag, the foreground color's RGB components are halved (or blended toward the background).

### 12.3 Built-in Themes

M1 ships with at least two built-in themes:

- **Dark** (default): A standard dark terminal theme (dark background, light text, standard ANSI colors similar to Ghostty's defaults).
- **Light**: Inverted for light-background preference.

Themes are defined as static `ColorPalette` instances in `DefaultThemes.swift`. The active theme is selected at startup. M6 will add runtime switching and TOML-based custom themes.

---

## 13. Keyboard Input Handling

### 13.1 Event Capture

Keyboard events are captured via `NSView`'s `keyDown(with:)`, `keyUp(with:)`, and `flagsChanged(with:)` overrides on `TerminalMetalView`. SwiftUI does not provide sufficient low-level keyboard access for terminal input, so the Metal view must be an `NSView` subclass that becomes first responder.

The `interpretKeyEvents(_:)` / `insertText(_:)` / `doCommand(by:)` NSTextInputClient pipeline is used for text input to support IME (Input Method Editor) for CJK text entry. For non-IME key events, the raw key code and modifier flags are used.

### 13.2 Key Encoding

Key events are translated to VT escape sequences via libghostty-vt's key encoder:

1. Create a `GhosttyKeyEvent` via `ghostty_key_event_new()` with the key code, action (press/release/repeat), and modifier flags (shift, ctrl, alt/option, super/cmd).
2. Sync encoder options from the terminal state via `ghostty_key_encoder_setopt_from_terminal()` (to respect current keyboard protocol mode, e.g., Kitty keyboard protocol).
3. Call `ghostty_key_encoder_encode()` to produce the escape sequence bytes.
4. Write the encoded bytes to the PTY master FD.
5. Free the key event via `ghostty_key_event_free()`.

### 13.3 macOS Key Handling Specifics

- **Option as Meta:** Option key should function as Meta (Alt) for terminal applications. This means `NSEvent.characters` (which may produce special characters like ``) should be ignored in favor of the raw key code + modifier approach.
- **Cmd shortcuts:** Cmd+C (copy), Cmd+V (paste), and other Cmd-based shortcuts are intercepted before being sent to the terminal. These are handled as application commands, not terminal input.
- **Dead keys and compose sequences:** Handled by the NSTextInputClient pipeline.

---

## 14. View Layer

### 14.1 TerminalMetalView (NSView subclass)

This is the core view that hosts the `CAMetalLayer` and handles input. Responsibilities:

- Hosts a `CAMetalLayer` as its backing layer (`wantsLayer = true`, `makeBackingLayer()` returns a `CAMetalLayer`).
- Configures the Metal layer: pixel format `.bgra8Unorm_srgb`, framebuffer-only, display sync enabled.
- Implements `NSTextInputClient` for IME support.
- Overrides `keyDown`, `keyUp`, `flagsChanged`, `mouseDown`, `mouseDragged`, `mouseUp`, `scrollWheel`, `rightMouseDown`.
- Becomes first responder and accepts first responder status.
- On `viewDidMoveToWindow`, obtains the screen's backing scale factor and configures the Metal layer's `contentsScale`.
- On resize (`setFrameSize` or `layout`), recalculates grid dimensions (columns = floor(width / cellWidth), rows = floor(height / cellHeight)), calls `PTYProcess.resize()` and `ghostty_terminal_resize()`, and updates the renderer's uniform buffer.

### 14.2 TerminalContentView (NSViewRepresentable)

A SwiftUI bridge that wraps `TerminalMetalView` for embedding in the SwiftUI window hierarchy. Minimal -- just creates the NSView and passes the `TerminalCore` reference.

### 14.3 TerminalWindow

The SwiftUI `WindowGroup` (or `Window` scene) that defines the app's main window. For M1 this is a single window containing a single `TerminalContentView`. The window has no tab bar, no space bar, no workspace indicator -- those are added in M3/M4.

The window's title displays the shell's current working directory or a static title like "tian" for M1.

---

## 15. TerminalCore -- Orchestrator

`TerminalCore` is the central coordinator that owns the PTY process, the libghostty-vt bridge objects, and mediates between input, output, and rendering.

**Lifecycle:**

1. **Init:** Creates the `GhosttyBridge.Terminal`, `GhosttyBridge.RenderState`, `GhosttyBridge.KeyEncoder`, and `GhosttyBridge.MouseEncoder`. Spawns a `PTYProcess` with the user's default shell. Sets up the PTY read source to deliver bytes for VT processing.
2. **Steady state:** Receives PTY output, processes through VT, extracts snapshots for the renderer. Receives keyboard/mouse input, encodes, writes to PTY.
3. **Deinit:** Sends SIGHUP to the shell process, closes the PTY, frees all libghostty-vt resources.

**Threading model:**

All libghostty-vt API calls are serialized on the `terminal-core` DispatchQueue. The PTY read source delivers data to this queue. Keyboard/mouse input from the main thread is dispatched to this queue for encoding. Snapshot extraction also runs on this queue, with the resulting snapshot handed off to the render thread via a thread-safe handoff mechanism.

---

## 16. Performance Instrumentation

Per the PRD's internal observability requirements, M1 instruments:

| Signal | Measurement Point | Storage |
|--------|-------------------|---------|
| Frame render time (ms) | Time from command buffer creation to drawable presentation callback | Rolling average in `PerformanceCounters` |
| Shell spawn latency (ms) | Time from `PTYProcess.spawn()` call to first byte read from PTY | Single measurement logged at spawn |
| Memory per pane (bytes) | Resident memory of the process (as a proxy for single-pane M1) | Sampled periodically |
| Snapshot extraction time (us) | Time to iterate render state and build `GridSnapshot` | Rolling average |
| Glyph cache hit rate (%) | Cache hits / (hits + misses) in `FontAtlas` | Counter |

These are logged via `os.Logger` at the `.debug` level and optionally displayed in a debug overlay (toggled via a hidden keyboard shortcut, e.g., Cmd+Shift+F12).

---

## 17. Error Handling Strategy

| Error Scenario | Detection | Response |
|----------------|-----------|----------|
| Shell fails to spawn (execvp fails) | Child process exits immediately with error | Display error message in the terminal view area with the failed command and errno description |
| PTY allocation fails (openpty returns -1) | Return value check | Show an alert dialog; the pane cannot function without a PTY |
| libghostty-vt returns error from any API call | `GhosttyResult` check in `GhosttyBridge` | Log the error. For terminal_new failure, the pane cannot start. For render_state errors, skip the frame. |
| Font atlas texture allocation fails | MTLDevice.makeTexture returns nil | Fall back to a smaller texture size; if still failing, log critical error |
| Metal device not available | `MTLCreateSystemDefaultDevice()` returns nil | Fatal -- show alert and exit (GPU rendering is a hard requirement) |
| PTY read returns 0 bytes (EOF) | read() return value | Shell has exited; trigger exit handling flow |
| PTY read returns -1 (error) | errno check | If EAGAIN, retry. If EIO, treat as shell exit. Otherwise log and close. |
| Write to PTY fails | write() return value | Log warning. If EPIPE, shell has exited. |

---

## 18. Implementation Phases

M1 is broken into four sub-phases, each independently testable:

### Phase 1A: PTY + Raw Terminal (estimated: 3-5 days)

**Goal:** Shell spawns and you can type commands and see raw output (no GPU rendering yet).

- Set up Xcode project with Swift 6, macOS 26+ deployment target.
- Implement `PTYProcess` and `PTYFileHandle`.
- Implement basic `TerminalCore` that spawns a shell and echoes output to Console.log.
- Create a temporary `NSTextView`-based terminal view for validation (replaced in 1B).
- Verify: can type `ls`, see output, `cat /etc/passwd` works, Ctrl+C sends SIGINT.

### Phase 1B: libghostty-vt Integration (estimated: 3-5 days)

**Goal:** VT parsing works; terminal state is correct.

- Integrate libghostty-vt static library and bridging header.
- Implement `GhosttyBridge` with Terminal, RenderState, KeyEncoder wrappers.
- Wire PTY output through `ghostty_terminal_vt_write()`.
- Wire keyboard input through the key encoder.
- Implement `GridSnapshot` extraction from render state.
- Verify: run `htop`, `vim`, `less` -- validate cursor positioning, colors, alternate screen via debug logging of grid state.

### Phase 1C: Metal Rendering (estimated: 5-7 days)

**Goal:** GPU-rendered terminal with font atlas.

- Implement `FontAtlas` with Core Text rasterization and shelf packing.
- Implement Metal shaders (background, text, cursor passes).
- Implement `TerminalRenderer` with triple-buffered instanced rendering.
- Implement `TerminalMetalView` with CAMetalLayer.
- Wire `GridSnapshot` to renderer.
- Implement cursor rendering (block, underline, bar) with blink.
- Verify: run `htop`, `vim`, colorful prompts -- visually correct output at 60fps.

### Phase 1D: Selection, Scrolling, Polish (estimated: 3-5 days)

**Goal:** Complete M1 feature set.

- Implement smooth scrolling (pixel-offset accumulation, trackpad momentum).
- Implement text selection (click-drag, double-click word, triple-click line).
- Implement Cmd+C copy and Cmd+V paste (with bracketed paste support).
- Implement basic color scheme support (dark/light built-in themes).
- Implement Unicode edge cases (wide characters, combining characters, emoji).
- Implement resize handling (SIGWINCH, terminal resize, grid recalculation).
- Implement performance counters and debug overlay.
- Verify: scroll through `find /` output smoothly, select and copy text, paste into shell, resize window, display CJK text and emoji correctly.

---

## 19. Technical Risks and Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| libghostty-vt API instability (documented as unstable) | Breaking changes require bridge rewrites | High | Pin to a specific release tag. Wrap all C API access through `GhosttyBridge` so changes are isolated to one file. Keep the bridge surface minimal. |
| libghostty-vt build/link issues (Zig-compiled library linked into Swift project) | Blocks all terminal functionality | Medium | Use the pre-built release artifacts. Validate linking in Phase 1B before investing in rendering. Have a fallback plan to use a simpler VT parser (e.g., SwiftTerm's parser) if libghostty-vt proves unworkable, though this is a last resort. |
| Font atlas performance (frequent cache misses with diverse Unicode) | Frame drops during atlas updates | Low | Allocate a large initial atlas (1024x1024). Pre-warm the cache with ASCII printable range on startup. Atlas updates are incremental (only new glyphs trigger texture writes). |
| Sub-line smooth scrolling complexity | Rendering artifacts at fractional scroll positions | Medium | Start with whole-line scrolling in Phase 1C, add pixel-offset smoothing in Phase 1D. If artifacts persist, fall back to whole-line scrolling (still usable, just not as smooth). |
| NSTextInputClient complexity for IME | Broken CJK input | Medium | Implement basic `insertText(_:)` first (covers non-IME input). Add full marked text handling iteratively. Test with Japanese/Chinese input methods. |
| Metal rendering correctness (color space, blending) | Incorrect colors or blending artifacts | Medium | Use `bgra8Unorm_srgb` pixel format for correct sRGB handling. Test with true-color test scripts (e.g., `awk` 24-bit color gradient). |
| Snapshot extraction latency blocking VT processing | Input lag when terminal is producing heavy output | Low | Profile extraction time. If it exceeds 1ms, consider: (a) partial snapshots (only dirty rows), (b) rate-limiting snapshot extraction to every 16ms, (c) double-buffering the render state. |

---

## 20. Open Technical Questions

| # | Question | Context | Impact if Unresolved |
|---|----------|---------|---------------------|
| 1 | Which libghostty-vt release/commit to target? | The library is in active development with an unstable API. Need to pick a specific version to build against. | Cannot begin Phase 1B without a concrete binary and headers. |
| 2 | Does libghostty-vt provide selection/selection-text-extraction APIs, or must tian implement selection entirely? | The render state API exposes cell data, but selection tracking (anchor/extent, word detection) may or may not be in the library. | If not provided, tian must implement word boundary detection and selection coordinate tracking (specced above as a mitigation). |
| 3 | What is the default font and color scheme? | PRD Open Question 7 asks this. M1 needs a concrete answer to ship. | Use SF Mono 13pt and a standard dark theme as provisional defaults. Revisit before M1 ships. |
| 4 | How does libghostty-vt expose the 256-color palette and true-color values? | The render state cell API has `BG_COLOR` and `FG_COLOR` data types, but the exact format (palette index vs resolved RGB) affects color resolution logic. | Must inspect actual header definitions to confirm. Specced both paths above. |
| 5 | Should Option key be Meta by default, or should it retain macOS special character behavior? | Both behaviors are common in macOS terminals. Ghostty defaults to Option-as-Meta. | Default to Option-as-Meta (matching Ghostty). Make configurable in M6. |
| 6 | Pre-built libghostty-vt binary availability for arm64 macOS | Need to confirm the library ships pre-built for Apple Silicon, or if we need to build from source (requires Zig toolchain). | If no pre-built binary, add Zig build step to the project or use a build script. |

---

## Appendix A: Key Type Definitions

### GridPosition

| Field | Type | Description |
|-------|------|-------------|
| `col` | `Int` | Zero-based column index |
| `row` | `Int` | Zero-based row index (0 = top of viewport) |

### CellStyle

| Field | Type | Description |
|-------|------|-------------|
| `foreground` | `SIMD4<UInt8>` | Resolved RGBA foreground color |
| `background` | `SIMD4<UInt8>` | Resolved RGBA background color |
| `underlineColor` | `SIMD4<UInt8>?` | Underline color if explicitly set |
| `bold` | `Bool` | Bold attribute |
| `italic` | `Bool` | Italic attribute |
| `faint` | `Bool` | Dim/faint attribute |
| `underline` | `UnderlineStyle` | None, single, double, curly, dotted, dashed |
| `strikethrough` | `Bool` | Strikethrough attribute |
| `inverse` | `Bool` | Inverse video (resolved before color assignment) |
| `invisible` | `Bool` | Hidden text |

### CursorStyle (enum)

- `block`
- `underline`
- `bar`

### CellWide (enum)

- `narrow`
- `wide`
- `spacerTail`
- `spacerHead`

### SelectionMode (enum)

- `character`
- `word`
- `line`

### DirtyState (enum)

- `none`
- `partial`
- `full`

### GlyphKey

| Field | Type | Description |
|-------|------|-------------|
| `codepoints` | `[Unicode.Scalar]` | Full grapheme cluster |
| `bold` | `Bool` | Bold variant |
| `italic` | `Bool` | Italic variant |

### GlyphInfo

| Field | Type | Description |
|-------|------|-------------|
| `atlasX` | `Float` | X position in atlas (UV) |
| `atlasY` | `Float` | Y position in atlas (UV) |
| `width` | `Float` | Glyph width in atlas (UV) |
| `height` | `Float` | Glyph height in atlas (UV) |
| `pixelWidth` | `Float` | Glyph width in pixels |
| `pixelHeight` | `Float` | Glyph height in pixels |
| `bearingX` | `Float` | Horizontal bearing in pixels |
| `bearingY` | `Float` | Vertical bearing in pixels |
| `isColorGlyph` | `Bool` | Whether this glyph is in the color (RGBA) atlas |
