---
name: quota-companion
description: Read the user's main Codex quota status, show the inline liquid-level card, or control the local Zhaoxi (朝夕) macOS companion. Use for questions about remaining five-hour, weekly, or other Codex quota windows, and for requests to show, collapse, or configure the companion.
---

# 朝夕 / Zhaoxi

Use the bundled `quota-companion` MCP tools for quota status and desktop-pet controls.

The project illustration is the blue-gown companion. It depicts synthetic quota data. The user's actual desktop appearance follows their selected local character; the illustration does not imply that the full character package is bundled in the release.

## Status requests

1. Call `get_quota_status` once.
2. Report whether the result is `live`, `stale`, or `unavailable` before presenting percentages.
3. Name only the quota windows returned by the tool. Never invent a five-hour or weekly window when it is absent.
4. Lead with the limiting window, then list the remaining main Codex windows in duration order.
5. If data is stale, include the observation time and make clear that it is cached.

The tool is read-only. Do not offer to redeem reset credits, buy quota, change an account, or infer account identity.

## Companion controls

- Use `show_companion` to launch Zhaoxi and temporarily show the detail panel beside the user's selected companion.
- Use `collapse_companion` to hide details while keeping the selected companion visible.
- Use `open_companion_settings` for language, speech, startup behavior, companion appearance, custom CLI path, or the local detail-card background. Users can create a local character from an image or import a v1/v2/v3/v4 package. Cloud speech and Reminders require the user to configure and authorize them in the app; these MCP tools do not expose credentials, voice cloning, or schedule editing.

If the app is not installed, return the tool's installation guidance without claiming the control succeeded.
