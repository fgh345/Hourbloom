extends RefCounted
## Authored 1.15-second poses retimed uniformly to a 0.6-second action.
const DURATION := 0.6
const TIME_SCALE := DURATION / 1.15
const IMPACT_TIME := 0.85 * TIME_SCALE
const BLEND_TIME := 0.10 * TIME_SCALE
const CONTACT_LOCAL := Vector3(0.015, 0.0, 0.869053)
const READY_TIME := 0.10 * TIME_SCALE
const RAISED_TIME := 0.50 * TIME_SCALE
const SWING_TIME := 0.73 * TIME_SCALE
const FOLLOW_TIME := 1.02 * TIME_SCALE
const READY_END := 0.20 * TIME_SCALE
const RAISED_END := 0.57 * TIME_SCALE
const CONTACT_END := 0.90 * TIME_SCALE
