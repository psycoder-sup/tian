# tian shell integration for zsh
# Loaded by .zshenv for interactive shells.

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

autoload -Uz add-zsh-hook
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
_tian_autostart_widget() {
    if [[ -n "${TIAN_AUTOSTART_CMD:-}" ]]; then
        local _tian_cmd="$TIAN_AUTOSTART_CMD"
        builtin unset TIAN_AUTOSTART_CMD
        BUFFER="$_tian_cmd"
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
