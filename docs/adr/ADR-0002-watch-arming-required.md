# ADR-0002: Watch Arming Required

## Status

Accepted for MVP implementation.

## Decision

iPhone alarm creation is not enough for Smart Mode Ready. The Watch must receive the config, pass readiness checks, and schedule the runtime session before either app can show Ready.

## Consequences

If the Watch is not armed, the UI must show Needs Watch Arming. If runtime scheduling fails, the system must show Fallback Only and keep the iPhone backup channel visible.

