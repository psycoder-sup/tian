---
name: ghostty env_override ordering in Exec.zig
description: In embedded ghostty, per-surface env_vars (env_override) are applied AFTER shell_integration.setup(), so they win over ghostty's own ZDOTDIR/etc. injection
type: project
---

In ghostty's `src/termio/Exec.zig` (around lines 789-815), `shell_integration.setup()` runs first and sets things like `ZDOTDIR` to ghostty's own resources dir. Then the surface-level `env_override` map is applied via `env.put`, which clobbers anything setup() wrote.

**Why:** Ghostty treats env_override as the highest-priority source. This is deliberate for users who want to force specific env vars, but it means embedders that set ZDOTDIR themselves will silently disable ghostty's shell integration (OSC 133 prompt markers in particular).

**How to apply:** When reviewing tian code that passes env_vars to `ghostty_surface_config_t`, any key that overlaps with ghostty's shell_integration output (ZDOTDIR, ENV, GHOSTTY_BASH_INJECT, GHOSTTY_ZSH_ZDOTDIR, GHOSTTY_SHELL_FEATURES, etc.) should either be left alone OR the embedder must take responsibility for loading ghostty's integration itself. Symptom of breakage: `ghostty_surface_needs_confirm_quit()` always returns true because `cursorIsAtPrompt()` sees no OSC 133 markers.
