# ADR-0004: Fallback Channel Policy

## Status

Accepted for MVP implementation.

## Decision

iPhone fallback is mandatory. iOS 26+ AlarmKit is the preferred fallback when authorized; otherwise the app degrades to local notifications, foreground audio, and explicit manual fallback prompts.

## Consequences

Every fallback channel attempt and fire result must be logged as `AlarmChannelLog`. v0.2 must not imply third-party Watch alarms have the same reliability as Apple system alarms.

