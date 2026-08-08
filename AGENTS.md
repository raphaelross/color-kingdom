# AGENTS.md

## Product Context
Color Kingdom is a children's coloring app for ages 3-8. The product is designed to start simple, feel playful, work offline once content is available, and grow into a content-rich app with premium offerings, parent controls, and AI-assisted generation.

## Target Users
- Children ages 3-8
- Parents and caregivers who manage access, purchases, and saved artwork

## Technology Stack
- Flutter for the mobile and web app
- Firebase for authentication, database, file storage, analytics, and notifications
- Riverpod for app state management
- go_router for declarative navigation
- Google Fonts and Material 3 for the current visual system

## Development Principles
- Favor feature-first architecture over large shared abstractions.
- Keep the app offline-first whenever content can be local or cached.
- Preserve existing behavior unless a change is explicitly intended.
- Avoid unnecessary dependencies.
- Do not make major architecture changes without first documenting them in the relevant ADR or feature spec.
- Update documentation whenever architecture, feature behavior, or route structure changes.

## Riverpod Usage
- Use Riverpod for app and feature state that benefits from explicit testable controllers.
- Keep state controllers focused on one feature boundary.
- Prefer immutable state objects and action-based updates.

## go_router Usage
- Use named routes for screen navigation.
- Keep route definitions centralized in the router module.
- Add placeholder routes early so future screens can be connected without restructuring the app.

## Firebase Usage
- Use Firebase only where persistent backend behavior is needed.
- Keep content delivery and user progress compatible with offline use where possible.
- Add Firebase services intentionally and document why each one is needed.

## Testing And Validation
- After changing app code, run `flutter analyze lib`.
- Run `flutter test` after changes that could affect behavior.
- Add or update tests for new feature logic whenever practical.
- Do not ship feature changes without validation.

## Code Quality Expectations
- Keep changes small, focused, and easy to review.
- Preserve existing functionality when implementing new behavior.
- Prefer readable, explicit code over clever abstractions.
- Keep feature code close to the feature it supports.

## Security Expectations
- Treat the app as child-facing and parent-managed.
- Do not assume network availability for core play experiences.
- Plan for safe defaults around AI generation, saved artwork, and user data.
- Do not expose sensitive data unnecessarily.

## Child-Friendly UX Principles
- Tap should produce immediate visible feedback.
- Controls should be large and obvious.
- Avoid cluttered screens and unnecessary modal dialogs.
- Use gentle colors, simple labels, and predictable interactions.
- Optimize for tablets and phones alike.
