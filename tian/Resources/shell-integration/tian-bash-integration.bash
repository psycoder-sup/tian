# tian shell integration for bash

# Install claude wrapper as a shell function so it takes priority
# over any PATH-resolved binary.
_TIAN_CLAUDE_WRAPPER=""
_tian_install_claude_wrapper() {
    local resources_dir="${TIAN_RESOURCES_DIR:-}"
    [[ -n "$resources_dir" ]] || return 0

    local wrapper_path="$resources_dir/claude"
    [[ -x "$wrapper_path" ]] || return 0

    _TIAN_CLAUDE_WRAPPER="$wrapper_path"
    unalias claude >/dev/null 2>&1 || true
    eval 'claude() { "$_TIAN_CLAUDE_WRAPPER" "$@"; }'
}
_tian_install_claude_wrapper

# Ensure Resources dir is at the front of PATH.
_tian_fix_path() {
    if [[ -n "${TIAN_RESOURCES_DIR:-}" && -d "$TIAN_RESOURCES_DIR" ]]; then
        local new_path=":${PATH}:"
        new_path="${new_path//:${TIAN_RESOURCES_DIR}:/:}"
        new_path="${new_path#:}"
        new_path="${new_path%:}"
        PATH="${TIAN_RESOURCES_DIR}:${new_path}"
    fi
}
_tian_fix_path
unset -f _tian_fix_path
