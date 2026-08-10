# Roadmap

## Completed Work
- Flutter app scaffold created and running on mobile, web, and desktop targets.
- Custom Color Kingdom theme added.
- Splash screen implemented with a timed transition to Home.
- Home screen implemented with reusable category cards.
- go_router navigation scaffolded with named routes.
- Basic placeholder screens created for unfinished sections.
- First coloring-engine baseline implemented.
- Sample Happy Cat coloring page data defined.
- Riverpod state controller implemented for coloring actions.
- CK-002.1 production coloring engine foundation completed.
- CK-002.2 real SVG coloring pipeline completed and validated on Windows.
- CK-002.3 local multi-page Animals catalog foundation implemented.
- CK-002.4 local save-and-resume coloring progress implemented.

## Current MVP Baseline
The app now has a usable local SVG coloring pipeline with multi-page catalog navigation for Animals and local per-page progress persistence.

## Remaining MVP Work
- Add more real coloring pages across additional categories using the existing SVG pipeline.
- Expand local catalog coverage while preserving repository-driven loading.
- Hook up Firebase authentication and persistence where needed.
- Add saved artwork storage and retrieval.
- Add parent-zone controls.
- Add integration-level runtime tests for multi-page workflows.

## CK-002.4 Acceptance Status
- Save and resume coloring progress by stable page ID.
- Restore progress after navigation away/back and controller recreation.
- Keep page sessions isolated across Happy Cat, Playful Puppy, Friendly Lion, and Cute Elephant.
- Keep persistence failures non-fatal to coloring interactions.
- Keep undo/redo history in-memory only across restarts.

## Next Product Phases
- Build a scalable content library.
- Add AI page generation.
- Add story coloring.
- Add subscriptions and in-app purchases.
- Prepare App Store and Google Play launch assets.
# Color Kingdom Roadmap

## Product Goal
Build a kid-friendly Flutter coloring app for ages 3-8 with a polished experience, expandable content library, premium AI generation, and parent controls.

## Current State
- Flutter app scaffolded
- Custom theme and splash screen in place
- Home screen uses reusable category cards
- go_router navigation scaffolded with named routes
- Firebase and core packages added to `pubspec.yaml`

## Phase 1: Core App Experience
Goal: make the app feel complete with stable navigation and content structure.

- Define app sections and route map
- Create shared content models
- Build category browsing and placeholder screens
- Add a consistent visual system across screens
- Wire simple state management with Riverpod

## Phase 2: Coloring Experience
Goal: let kids open a page and start coloring immediately.

- Build coloring canvas screen
- Add brush tools:
  - paint bucket
  - crayon
  - marker
  - colored pencil
  - paint brush
  - glitter brush
  - rainbow brush
  - magic sparkle brush
- Add undo / redo, zoom, and eraser
- Add color palettes:
  - standard
  - pastel
  - neon
  - metallic
  - skin tones

## Phase 3: Content System
Goal: support thousands of pages and easy future expansion.

- Add category metadata model
- Store page data in Firestore / Storage
- Support premium packs and featured collections
- Add story coloring flow
- Add favorites and saved artwork

## Phase 4: Parent Features
Goal: make the app safe and useful for families.

- Build parent zone
- Add screen time controls
- Add AI generation toggle
- Add saved artwork export / print
- Add child profile support later

## Phase 5: Firebase Integration
Goal: connect the app to backend services.

- Firebase Auth
- Firestore for content metadata and user progress
- Cloud Storage for artwork and assets
- Analytics for funnel tracking
- Push notifications for new content / events

## Phase 6: AI Features
Goal: enable premium image and story generation.

- AI prompt entry flow
- Generate black-and-white coloring pages
- Convert generated images into clean line art
- Generate story text for story coloring mode
- Add safety and moderation checks

## Phase 7: Monetization
Goal: support subscriptions and content packs.

- Free tier with limited pages and basic brushes
- Premium monthly subscription
- Extra content packs
- Restore purchases
- Child-safe purchase gate in parent zone

## Phase 8: Launch
Goal: ship to stores with a polished presence.

- App Store / Google Play prep
- Privacy policy and child safety review
- Marketing website
- Onboarding and screenshots
- Beta testing and analytics review

## Recommended Next Build Step
Expand local content coverage beyond Animals while keeping stable category/page IDs, repository-owned catalog filtering, and page-scoped session persistence semantics.
