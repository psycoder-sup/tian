# tian shell integration for zsh
# Loaded by .zshenv for interactive shells.

# tian autostart: don't stall on interactive rc prompts.
# A pane that auto-launches TIAN_AUTOSTART_CMD (e.g. claude) must reach its first
# prompt with no human at the keyboard. The user's rc files may issue blocking
# confirmation prompts (oh-my-zsh dotenv "Source it?", compinit insecure-dirs, a
# powerlevel10k wizard, custom "[y/N]" reads). Single-key reads (read -q/-k) read
# straight from the terminal, so they hang forever with nobody typing — which
# stalls the autostart, leaving the pane sitting at a bare shell prompt.
#
# While the shell starts up, shadow `read`/`vared` so interactive confirmation
# prompts take their default immediately instead of blocking. Reads that are
# non-interactive (have a timeout, or are plain line/pipe reads) delegate to the
# real builtin untouched, so rc loops like `... | while read x` keep working. The
# shadows are removed on the first prompt — before the autostart command runs — so
# the live session (and claude) get normal `read` behaviour. This runs at source
# time (from .zshenv, before the user's .zshrc) so it is in place before any rc
# prompt fires.
autoload -Uz add-zsh-hook   # used by the autostart block and _tian_fix_path below

if [[ -n "${TIAN_AUTOSTART_CMD:-}" ]]; then
    read() {
        builtin emulate -L zsh
        local arg interactive=0 timed=0 skipnext=0
        for arg in "$@"; do
            if (( skipnext )); then skipnext=0; continue; fi
            case "$arg" in
                -*[qk]*)  interactive=1 ;;   # single-key / yes-no read of the tty
                -*t*)     timed=1 ;;         # has a timeout: self-resolves
                -d|-u)    skipnext=1 ;;       # delimiter/fd: consumes the next word
                [^-]*\?*) interactive=1 ;;   # `name?prompt` interactive line read
            esac
        done
        if (( interactive && ! timed )); then
            return 1   # take the prompt's default (no/empty); never block
        fi
        builtin read "$@"
    }

    vared() { :; }

    # Restore real `read`/`vared` on the first prompt. precmd runs before the
    # line-init autostart widget, so claude launches with normal behaviour. The
    # autostart widget unsets TIAN_AUTOSTART_CMD, so child shells never re-install.
    _tian_restore_reads() {
        add-zsh-hook -d precmd _tian_restore_reads
        builtin unfunction read vared 2>/dev/null
    }
    add-zsh-hook precmd _tian_restore_reads
fi

# Install claude wrapper as a shell function so it takes priority
# over any PATH-resolved binary. The wrapper injects --settings
# to enable tian's Claude Code hooks.
typeset -g _TIAN_CLAUDE_WRAPPER=""
_tian_install_claude_wrapper() {
    local resources_dir="${TIAN_RESOURCES_DIR:-}"
    [[ -n "$resources_dir" ]] || return 0

    local wrapper_path="$resources_dir/claude"
    [[ -x "$wrapper_path" ]] || return 0

    _TIAN_CLAUDE_WRAPPER="$wrapper_path"
    builtin unalias claude >/dev/null 2>&1 || true
    eval 'claude() { "$_TIAN_CLAUDE_WRAPPER" "$@"; }'
}
_tian_install_claude_wrapper

# Ensure Resources dir is at the front of PATH after all rc files
# have finished loading. Runs once on first prompt, then removes itself.
_tian_fix_path() {
    if [[ -n "${TIAN_RESOURCES_DIR:-}" && -d "$TIAN_RESOURCES_DIR" ]]; then
        local -a parts=("${(@s/:/)PATH}")
        parts=("${(@)parts:#$TIAN_RESOURCES_DIR}")
        PATH="${TIAN_RESOURCES_DIR}:${(j/:/)parts}"
    fi
    add-zsh-hook -d precmd _tian_fix_path
}

add-zsh-hook precmd _tian_fix_path

# tian autostart: run the section command (e.g. "claude") once, on the first
# interactive prompt — i.e. after all rc files AND any interactive startup
# prompts (oh-my-zsh dotenv "Source it?", auto-update "[Y/n]") have resolved.
# This replaces injecting "claude\n" as keystrokes, which raced with those
# prompts and got swallowed.
#
# We use a zle line-init widget + `accept-line` rather than a precmd hook so the
# command runs at the shell's top REPL level exactly as if typed and entered.
# Running a full-screen TUI like claude from inside precmd (mid prompt build)
# makes it exit immediately. The env var is unset before submitting so claude's
# child shells don't inherit it and re-launch recursively; line-init fires on
# every prompt but is a no-op once the var is gone.
#
# After the command finishes we `exit` the shell so the pane goes away instead of
# dropping back to a bare zsh prompt: an autostart pane exists to run its command,
# so when claude exits the pane (and its tab, if it's the last pane) should close.
# `exit` (no arg) carries claude's own exit status; the surface-exit then triggers
# the Swift close cascade (PaneViewModel: Claude panes close on any exit code).
_tian_autostart_widget() {
    if [[ -n "${TIAN_AUTOSTART_CMD:-}" ]]; then
        local _tian_cmd="$TIAN_AUTOSTART_CMD"
        builtin unset TIAN_AUTOSTART_CMD
        BUFFER="$_tian_cmd; builtin exit"
        builtin zle .accept-line
    fi
}

# Register the line-init widget from a one-shot precmd rather than at source
# time: when this file is sourced (from .zshenv) zle isn't ready, and ghostty's
# own deferred init rebuilds the line-init widget afterward — either way a
# source-time registration never fires. By the first precmd, zle exists and
# ghostty has run, and line-init fires later in the *same* prompt cycle, so the
# widget is active in time for the first prompt.
_tian_install_autostart() {
    add-zsh-hook -d precmd _tian_install_autostart
    autoload -Uz add-zle-hook-widget
    add-zle-hook-widget line-init _tian_autostart_widget
}
add-zsh-hook precmd _tian_install_autostart
