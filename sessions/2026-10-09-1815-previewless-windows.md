# Session: Keep previewless windows selectable

**Date:** 2026-10-09
**Branch:** v0.3.1
**Project:** Fathom
**Duration:** One implementation slice

## Summary
Mapped Hyprland clients can remain focusable without a Wayland preview handle. Previously the field excluded every such client.

## Work Completed
- Expose switchability from mapped and acceptsInput client metadata.
- Preserve verified switchable clients in the field when their preview handle is absent.
- Add logic coverage for searching and focusing a client after 24 hours away, and QML coverage for selecting a never-focused client on another workspace.

## Files Changed
Modified src/Fathom.qml, src/Recency.js, tests/logic.test.js, tests/qml/tst_fathom.qml, CHANGELOG.md. Created this session record and SCRATCHPAD.md.

## Decisions Made
Use Hyprland metadata for selection eligibility; retain existing preview and icon fallback behavior. Require explicit mapped and input-capable metadata for clients without handles. Do not alter bindings, window management, or compositor focus semantics.

## Testing Notes
Full bin/test against upstream 0.3.0: 47 Node logic tests, 62 offscreen QML tests, Lua bindings, static and manifest checks, qmllint and plugin validation passed. git diff --check passed. A real game disappearing after prolonged workspace absence has not yet been reproduced; automatic tests simulate missing preview handles and old recency.

## Next Steps
- Verify the installed build identity and user game behavior.
- Review upstream pull request; refine diagnosis if affected clients become unmapped or leave Hyprland's toplevel inventory.

## Notes
Tests use stub compositor metadata and capture handles. They demonstrate retained selection and focus requests, not game-engine lifecycle behavior.
