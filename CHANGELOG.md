# Changelog

## F0 — Platform ground truth

- Added read-only hardware diagnostics for bangkk.
- Dumping the real SoC id, active CPU governor, post-boot behavior, panel, thermal zones and charging interfaces before any tuning.
- No power, thermal, scheduler, display or charging behavior changed yet.

Run `tools/bangkk-platform-check.sh` on the device and keep its output as the reference for the next steps.
