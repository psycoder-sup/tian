---
name: tian zsh shell-integration bootstrap model
description: How tian composes its own zsh integration plus ghostty's on top of the user's rc files via a custom ZDOTDIR
type: project
---

Tian sets `ZDOTDIR=<bundle>/Resources/shell-integration/zsh` and preserves the user's original value as `TIAN_ORIGINAL_ZDOTDIR`. The custom zshenv in that dir:

1. Restores `ZDOTDIR` from `TIAN_ORIGINAL_ZDOTDIR` (falls back to unset).
2. Sources the user's own `${ZDOTDIR-$HOME}/.zshenv` inside a `{ } always { }` block.
3. In the `always` branch (interactive only): sources tian-zsh-integration.zsh (installs claude wrapper + PATH fix), then autoloads + invokes ghostty's `ghostty-integration` function from `$GHOSTTY_RESOURCES_DIR/shell-integration/zsh/ghostty-integration`.

**Why:** tian's ZDOTDIR injection would otherwise suppress ghostty's own `.zshenv` (which emits OSC 133 prompt markers), breaking `needs_confirm_quit`. The always-block ensures ghostty's integration still loads even if the user's `.zshenv` throws.

**How to apply:** When touching the zshenv/zshrc/zprofile/zlogin in `tian/Resources/shell-integration/zsh/`, preserve the invariant: ghostty-integration must be called after user rc files and only in interactive shells. The relative path `shell-integration/zsh/ghostty-integration` under `$GHOSTTY_RESOURCES_DIR` is a soft contract with upstream ghostty — if ghostty reorganizes, this silently no-ops.
