---
name: frontend-design-discipline
description: Audit-first preflight for substantial frontend/UI creation or redesign; use only when the task identifies a frontend/UI target or surface, the work is visual or interactive, and it creates a new surface or substantially redesigns an existing one.
---

# Frontend Design Discipline

Use this skill only when all three conditions are met: (1) the task identifies
a frontend/UI target or surface; (2) the work is visual or interactive; and (3)
the task creates a new surface or substantially redesigns an existing one. Do
not load it for minor adjustments, mechanical maintenance, or frontend work
that fails any condition. It adds a preflight to `frontend-philosophy`; it does
not prescribe a framework, component library, visual style, or design
vocabulary.

## Context

- State the user, task, content, constraints, and success criteria.
- Identify the supported input methods, viewport range, localization needs,
  and accessibility contexts that matter.

## Calibration

- Derive hierarchy, density, emphasis, and interaction cost from the context.
- Record intentional departures from existing patterns and why they are worth
  the maintenance cost.

## Preserve the system

- Inspect and reuse the existing tokens, components, primitives, content rules,
  and interaction conventions where they fit.
- Name any new primitive or token that the surface genuinely requires.

## Motion that is accessible and motivated

- Add motion only when it communicates state, hierarchy, continuity, or useful
  feedback.
- Provide an equivalent usable experience when motion is reduced or unavailable.
- Verify that motion does not trap focus, obscure content, or create avoidable
  cognitive or vestibular load.

## Complete states

- Account for loading, empty, partial, success, error, disabled, validation,
  permission, offline, and recovery states wherever they can occur.
- Make state changes observable to the relevant input and assistive technology.

## Responsiveness

- Define behavior across supported widths, zoom, text expansion, orientation,
  and input methods rather than only one viewport.
- Preserve task completion and readable structure when content grows.

## Audit first

- Audit semantics, keyboard flow, focus visibility, contrast, labels, errors,
  reduced motion, responsive behavior, and complete states before polishing.
- Prefer checks that observe the public user experience over implementation-only
  assertions.

## Preflight

- [ ] Context and success criteria are explicit.
- [ ] Existing system patterns and intentional deviations are recorded.
- [ ] Accessibility and input-method paths are covered.
- [ ] Motion is motivated and has a reduced-motion or no-motion equivalent.
- [ ] Complete states and recovery paths are represented.
- [ ] Responsive behavior survives content growth and viewport changes.
- [ ] Audit-first checks pass before visual polish is treated as complete.
