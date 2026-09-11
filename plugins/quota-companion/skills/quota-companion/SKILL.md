---
name: quota-companion
description: Read the user's main Codex quota status, show the inline liquid-level card, or control the local Quota Companion macOS pet. Use for questions about remaining five-hour, weekly, or other Codex quota windows, and for requests to show, collapse, or configure the pet.
---

# Quota Companion

Use the bundled `quota-companion` MCP tools for quota status and desktop-pet controls.

## Status requests

1. Call `get_quota_status` once.
2. Report whether the result is `live`, `stale`, or `unavailable` before presenting percentages.
3. Name only the quota windows returned by the tool. Never invent a five-hour or weekly window when it is absent.
4. Lead with the limiting window, then list the remaining main Codex windows in duration order.
5. If data is stale, include the observation time and make clear that it is cached.

The tool is read-only. Do not offer to redeem reset credits, buy quota, change an account, or infer account identity.

## Companion controls

- Use `show_companion` to launch the macOS companion and temporarily show its detail panel beside the cat.
- Use `collapse_companion` to hide details while keeping the 72-by-80-point pixel cat visible.
- Use `open_companion_settings` for language, speech, launch-at-login, custom CLI path, or the local detail-card background. The built-in cat is the default; users can import local v1/v2 character packages.

If the app is not installed, return the tool's installation guidance without claiming the control succeeded.
