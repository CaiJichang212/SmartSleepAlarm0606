# SmartSleep v0.2 Next Integration Plan Index

The original single integration plan has been split after review. Do not execute this file as an implementation plan.

Execute these plans in order:

1. `docs/superpowers/plans/2026-06-07-smartsleep-v02-app-state-and-logging.md`
2. `docs/superpowers/plans/2026-06-07-smartsleep-v02-device-integration-spikes.md`

Split rationale:

- App state, logging, export, and feature flags can be proven with core tests and Simulator builds.
- `WCSession`, Watch runtime sessions, notification reliability, AlarmKit or critical-alert entitlement behavior, Watch haptic/audio, and overnight behavior require paired real devices and QA matrix evidence.
- Apple framework adapters must sit behind protocols with fake implementations before real adapters are wired into app models.
