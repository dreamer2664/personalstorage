# ADR 0001 - Flutter for the app shell and UI

**Status:** accepted

**Context.** The product needs a custom 60 fps graph canvas, frosted-glass surfaces, squircle shapes and a
heavy amount of numerical code, on iOS and Android, offline.

**Decision.** Flutter/Dart, with the domain logic in a pure-Dart package.

**Alternatives considered.** *React Native/Expo*: fast to start, but the graph canvas and blur-heavy UI would need
Skia/Reanimated bridges and JS-side numerics. *Native Swift + Kotlin*: best platform fidelity, double the code and
two implementations of the brain to keep in agreement. *Kotlin Multiplatform*: strong for shared logic, but UI would
still be two codebases.

**Consequences.** One codebase and one brain; `CustomPainter` gives direct control of the graph; Dart typed arrays
keep the force layout allocation-free; widgets/lock-screen surfaces still need small native pieces (Kotlin/Swift),
kept minimal and deep-link based. Flutter has no system-native glass materials, so the glass look is composed
(blur + fill + border) and budgeted (see DESIGN_SYSTEM.md).
