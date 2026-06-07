# SmartSleep Alarm Agent Rules

中文回答问题。

You are working on SmartSleep Alarm v0.2.

Rules:
- Implement v0.2 only. Do not add sleep reports, cloud sync, ML personalization, audio recording, Android, or medical features.
- Reliability beats intelligence. If uncertain, keep ringing.
- Smart Mode is Ready only after Watch arming and successful runtime session scheduling.
- Motion is the primary signal. HealthKit heart rate is optional enhancement only and must never trigger auto-silence alone.
- Every state transition, alarm channel event, sensor freshness event, gesture event, and outcome must be logged.
- Auto silence and re-sleep detection are P0-Experiment behind feature flags.
- No workout-session workaround to force high-frequency heart rate.
- Keep changes scoped. Add tests for pure Swift logic. Do not change unrelated files.
- For Apple API code, add a manual device-test note if behavior cannot be verified in Simulator.

