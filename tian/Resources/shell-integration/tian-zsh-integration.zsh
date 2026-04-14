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
