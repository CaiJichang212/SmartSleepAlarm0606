# ADR-0003: Motion First, Heart Rate Optional

## Status

Accepted for MVP implementation.

## Decision

Core Motion is the primary signal for awake candidate detection, auto silence, and gesture snooze. HealthKit heart rate can only add confidence when fresh and must never trigger auto silence alone.

## Consequences

When motion is stale or the Watch is not worn, Smart Mode disables auto silence and gesture snooze. HealthKit denial keeps motion-only Smart Mode available.

