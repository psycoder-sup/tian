# Auto Claude Session Restore Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Auto-resume Claude Code sessions on tian session restore by bundling a `claude` wrapper script and settings JSON in the app bundle.

**Architecture:** A shell script named `claude` in `Contents/MacOS/` intercepts the `claude` command, injects `--settings` pointing to a bundled JSON with a `SessionStart` hook, which calls `tian-cli pane set-restore-command` to register the restore command. On next launch, `PaneViewModel.fromState` replays it via `initialInput`.

**Tech Stack:** Shell script (bash), JSON, XcodeGen (`project.yml`)

---

### Task 1: Create the Claude wrapper shell script

**Files:**
- Create: `tian/Resources/claude`

- [ ] **Step 1: Create the Resources directory**

Run: `mkdir -p tian/Resources`

- [ ] **Step 2: Create the wrapper script**

Create `tian/Resources/claude`:

```bash
#!/bin/bash
# claude wrapper for tian — injects session restore hook when running inside tian.
# Bundled at Contents/MacOS/claude; the MacOS dir is on PATH via EnvironmentBuilder.

SELF_DIR="$(dirname "$0")"
REAL_CLAUDE=$(PATH="${PATH//$SELF_DIR:}" command -v claude)

if [ -z "$REAL_CLAUDE" ]; then
  echo "claude: command not found" >&2
  exit 127
fi

if [ -n "$TIAN_SOCKET" ]; then
  exec "$REAL_CLAUDE" --settings "$SELF_DIR/../Resources/tian-claude-settings.json" "$@"
else
  exec "$REAL_CLAUDE" "$@"
fi
```

- [ ] **Step 3: Make it executable**

Run: `chmod +x tian/Resources/claude`

- [ ] **Step 4: Verify the script is syntactically valid**

Run: `bash -n tian/Resources/claude && echo "OK"`
Expected: `OK`

- [ ] **Step 5: Commit**

```bash
git add tian/Resources/claude
git commit -m "feat(resources): add claude wrapper script for session restore"
```

---

### Task 2: Create the Claude Code settings JSON

**Files:**
- Create: `tian/Resources/tian-claude-settings.json`

- [ ] **Step 1: Create the settings file**

Create `tian/Resources/tian-claude-settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "type": "command",
        "command": "tian-cli pane set-restore-command --command 'claude --resume $SESSION_ID'"
      }
    ]
  }
}
```

- [ ] **Step 2: Validate the JSON is well-formed**

Run: `python3 -m json.tool tian/Resources/tian-claude-settings.json > /dev/null && echo "OK"`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add tian/Resources/tian-claude-settings.json
git commit -m "feat(resources): add Claude Code settings with SessionStart hook"
```

---

### Task 3: Add build scripts to bundle both files

**Files:**
- Modify: `project.yml:49-67`

- [ ] **Step 1: Add post-compile script to copy the claude wrapper**

In `project.yml`, add a new entry to the `postCompileScripts` array of the `tian` target, after the existing "Bundle Ghostty Resources" entry:

```yaml
      - script: |
          cp -f "$SRCROOT/tian/Resources/claude" "$BUILT_PRODUCTS_DIR/${PRODUCT_NAME}.app/Contents/MacOS/claude"
          chmod +x "$BUILT_PRODUCTS_DIR/${PRODUCT_NAME}.app/Contents/MacOS/claude"
        name: Bundle Claude Wrapper
        inputFiles:
          - $(SRCROOT)/tian/Resources/claude
        outputFiles:
          - $(BUILT_PRODUCTS_DIR)/$(PRODUCT_NAME).app/Contents/MacOS/claude
```

- [ ] **Step 2: Add post-compile script to copy the settings JSON**

Add another entry to `postCompileScripts`, after the wrapper script:

```yaml
      - script: cp -f "$SRCROOT/tian/Resources/tian-claude-settings.json" "$BUILT_PRODUCTS_DIR/${PRODUCT_NAME}.app/Contents/Resources/tian-claude-settings.json"
        name: Bundle Claude Settings
        inputFiles:
          - $(SRCROOT)/tian/Resources/tian-claude-settings.json
        outputFiles:
          - $(BUILT_PRODUCTS_DIR)/$(PRODUCT_NAME).app/Contents/Resources/tian-claude-settings.json
```

- [ ] **Step 3: Regenerate the Xcode project**

Run: `cd /Users/psycoder/00_Code/00_Personal_Project/tian && xcodegen generate`
Expected: `Generated project tian.xcodeproj`

- [ ] **Step 4: Build and verify both files appear in the app bundle**

Run: `xcodebuild build -scheme tian -destination 'platform=macOS' -derivedDataPath .build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

Then verify:
Run: `ls -la .build/Build/Products/Debug/tian-debug.app/Contents/MacOS/claude .build/Build/Products/Debug/tian-debug.app/Contents/Resources/tian-claude-settings.json`
Expected: Both files exist. `claude` should be executable.

- [ ] **Step 5: Verify the wrapper script works inside the bundle**

Run: `bash -n .build/Build/Products/Debug/tian-debug.app/Contents/MacOS/claude && echo "OK"`
Expected: `OK`

Run: `python3 -m json.tool .build/Build/Products/Debug/tian-debug.app/Contents/Resources/tian-claude-settings.json > /dev/null && echo "OK"`
Expected: `OK`

- [ ] **Step 6: Run existing tests to verify nothing broke**

Run: `xcodebuild test -scheme tian -destination 'platform=macOS' -derivedDataPath .build -skip-testing:tianUITests 2>&1 | tail -20`
Expected: All tests PASS

- [ ] **Step 7: Commit**

```bash
git add project.yml tian.xcodeproj
git commit -m "build: bundle claude wrapper and settings JSON in app bundle"
```
