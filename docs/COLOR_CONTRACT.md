# DIGNI SCANNER 1.0.1 — color contract

Brand/action: #DF002E with #FFFFFF text (5.01:1 or higher).
Deep brand: #A4002F. Dark canvas: #0D151A. Dark surface: #12242C.
Light canvas: #F7F7F8. Light surface: #FFFFFF.
Primary text: #232323 / #F7F7F7. Secondary text: #696969 / #B8B8B8.
Small action/navigation labels: #DF002E in light mode, white in dark mode.
Success: #087F4F / #45D697 on #E1F7E9 / #173B2C.
Warning: #805600 / #F4C15C on #FFF2D9 / #3D3017.
Error: #B3261E / #FFB4AB on #FCEAE8 / #4B211E.
Solid result circles use the darker semantic color with a white glyph in both themes.
Informational and pending states are neutral; green is reserved for confirmed success.
Third-party logos retain their identity.

V3 implementation lives in lib/v3/app.dart and is loaded by lib/main.dart.
The legacy lib/screens and lib/core files are not imported by the V3 entry point.
All Material color roles are explicit; automatic seed-derived accent colors are removed.
Attendee badges distinguish successful entry, cancelled entry and pending entry.
Rejected check-in history is evaluated before action=checkin, so rejection cannot appear green.

Validation:
- Inspect both light and dark Figma pages, including authentication, scanner, results,
  navigation, history, dashboards, components and the architecture page.
- Text target: 4.5:1; meaningful UI graphics target: 3:1.
- Run the manual Android workflow on v3-preview for Flutter analysis and QA APK.
- This color update does not configure a WordPress endpoint or change authentication.
- The existing manual workflow creates an internal preview APK, not a production release.
