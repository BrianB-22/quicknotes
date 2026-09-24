# macOS 27 Application Design Specification
Version: 1.0  
Target: macOS 27+ visual design, with graceful compatibility for earlier supported macOS versions  
Primary frameworks: SwiftUI and AppKit

## 1. Purpose

This document defines a reusable visual and interaction standard for macOS applications designed for macOS 27.

The objective is to create applications that feel native to current macOS without overusing transparency, blur, custom glass, or decorative effects.

Core principle:

> **Navigation floats. Content rests. Controls use the system.**

Liquid Glass is a functional hierarchy layer, not a universal window background. Use it primarily for navigation, controls, toolbars, sidebars, and selected floating interface elements. Keep information-dense or reading-focused content visually stable.

---

## 2. Design Priorities

In order of importance:

1. **Legibility**
2. **Native macOS behavior**
3. **Clear visual hierarchy**
4. **Accessibility**
5. **Consistency**
6. **Content density appropriate for desktop use**
7. **Visual polish**

Never sacrifice readability or predictable interaction merely to increase translucency.

---

## 3. Platform Strategy

### 3.1 Prefer system components

Use standard SwiftUI or AppKit controls whenever practical.

Preferred examples:

- `NavigationSplitView`
- `List`
- `Form`
- `Table`
- `ScrollView`
- `TextField`
- `Button`
- `Toggle`
- `Picker`
- `Menu`
- `Toolbar`
- `NSSplitView`
- `NSToolbar`
- `NSPopover`

System controls automatically inherit current macOS appearance changes, accessibility behavior, contrast handling, tinting, and Liquid Glass treatment.

### 3.2 Do not recreate native controls

Avoid custom versions of:

- toolbar buttons
- segmented controls
- search fields
- sidebar rows
- disclosure controls
- checkboxes
- text fields
- menus

unless a product requirement cannot be achieved using system controls.

### 3.3 Build with the latest SDK

Evaluate the application on the latest macOS SDK before adding custom visual effects. Current Apple components may already provide the intended appearance automatically.

---

## 4. Window Architecture

A typical desktop or menu-bar utility should visually separate these layers:

```text
┌───────────────────────────────────────────────────────┐
│ Toolbar / Header                       GLASS / SYSTEM  │
├──────────────────┬────────────────────────────────────┤
│                  │                                    │
│ Sidebar          │ Main Content                       │
│ GLASS / SYSTEM   │ STABLE CONTENT SURFACE             │
│                  │                                    │
│                  │                                    │
├──────────────────┴────────────────────────────────────┤
│ Optional utility/status bar             SYSTEM/GLASS  │
└───────────────────────────────────────────────────────┘
```

The exact layout may vary, but the visual hierarchy should remain recognizable.

---

## 5. Liquid Glass Rules

### 5.1 Use glass for functional chrome

Liquid Glass is appropriate for:

- toolbars
- navigation
- sidebars
- floating controls
- inspectors
- contextual controls
- compact utility bars
- popover chrome
- selected custom interactive controls

### 5.2 Do not use glass everywhere

Do not make every pane, card, editor, row, or content region translucent.

Avoid:

- stacked translucent cards
- multiple overlapping glass layers
- glass behind long-form text
- glass behind dense tables
- glass behind editable documents
- decorative glass with no interaction purpose

### 5.3 Prefer automatic system glass

If a native control already adopts Liquid Glass, do not add another custom glass layer behind it.

### 5.4 Custom glass is exceptional

Use explicit glass APIs only when building a custom element that genuinely functions like native navigation or a floating control.

Examples:

```swift
.glassEffect()
```

or AppKit equivalents such as `NSGlassEffectView`, where appropriate for the deployment target.

Do not apply explicit glass effects simply to make an application look "more macOS 27."

### 5.5 Interactive glass effects

macOS 27 supports additional interactive response for appropriate glass controls. Use these effects only for interactive elements such as buttons or control containers.

A little goes a long way.

---

## 6. Background Specification

### 6.1 Root application background

Do **not** automatically place an opaque color over the entire root view.

Avoid this pattern unless the complete window truly requires a uniform opaque surface:

```swift
.background(Color(NSColor.windowBackgroundColor))
```

on the outermost application container.

A root opaque background can prevent system chrome, popovers, sidebars, and other materials from adopting the intended platform appearance.

### 6.2 Main content background

Information-heavy content should use a stable semantic surface.

Preferred SwiftUI approach:

```swift
.background(.windowBackground)
```

Use this for:

- document content
- note editors
- calendar grids
- settings detail panes
- data tables
- long-form text
- dashboards where readability is more important than transparency

`windowBackground` is preferred over hard-coded RGB values because it follows macOS appearance behavior.

### 6.3 Transparent content

Transparent content is acceptable when:

- the content is sparse
- readability remains excellent
- the view is primarily navigational
- the background contributes useful hierarchy

Do not rely on wallpaper visibility as a core content design feature.

---

## 7. Sidebar Specification

Use the native macOS sidebar treatment.

Preferred:

```swift
List {
    ...
}
.listStyle(.sidebar)
```

Guidelines:

- Allow the sidebar to inherit system material.
- Do not place an opaque rectangle behind the sidebar.
- Use standard row selection.
- Use semantic accent/tint colors.
- Prefer SF Symbols for row icons.
- Keep icon coloration restrained.
- Use system spacing before custom spacing.

macOS 27 extends sidebars to window edges and updates selection emphasis automatically when standard components are used.

---

## 8. Toolbar and Header Specification

Toolbars should remain visually lightweight.

### MUST

- Use native toolbar APIs when possible.
- Use SF Symbols for common actions.
- Use standard button styles.
- Maintain predictable macOS action placement.
- Allow system background effects to render naturally.

### SHOULD NOT

- draw a custom solid toolbar background
- add an additional material behind `NSToolbar`
- use excessive accent color
- place every action inside a bordered button
- create oversized mobile-style controls

### Floating titles

Where the title is visually free-floating, allow the system scroll-edge behavior to manage the transition between content and title-bar chrome.

---

## 9. Main Content Specification

Main content should appear visually quieter than navigation chrome.

Recommended treatment:

```swift
ContentView()
    .background(.windowBackground)
```

Suitable content includes:

- text editing
- calendars
- forms
- tables
- document previews
- logs
- code
- structured information

The content surface should not compete with controls for attention.

---

## 10. Text Editors

Text editors require predictable contrast.

For AppKit-backed editors:

```swift
textView.drawsBackground = false
scrollView.drawsBackground = false
```

is acceptable **only if the containing content pane itself provides a stable semantic background**.

Recommended structure:

```swift
EditorView()
    .background(.windowBackground)
```

This allows the text view to visually integrate with the pane without exposing arbitrary wallpaper directly behind text.

### Editor requirements

- high text contrast
- standard selection behavior
- standard insertion cursor
- native scrolling
- standard keyboard shortcuts
- native context menus
- readable line spacing
- no decorative glass directly behind long-form text

---

## 11. Popovers and Menu-Bar Utilities

For `NSPopover` applications:

### Recommended

- Let the popover shell use the system appearance.
- Avoid an opaque root-level background.
- Apply semantic backgrounds only to content regions that need visual stability.
- Use native sidebars, lists, controls, separators, and buttons.

Example architecture:

```text
Popover shell             Native material
    Header                Native material
    Sidebar               Native sidebar material
    Content pane          windowBackground
    Footer controls       Native/system material
```

This produces a native macOS appearance while maintaining readability.

---

## 12. Cards and Containers

Use cards sparingly on macOS.

Desktop layouts generally do not require every content section to sit inside a rounded rectangle.

Use a card only when it communicates meaningful grouping.

Preferred grouping hierarchy:

1. spacing
2. alignment
3. section heading
4. divider
5. subtle container
6. card only when necessary

Avoid "dashboard card soup."

---

## 13. Corners and Shape

Use system-defined shapes whenever available.

macOS 27 introduces improved support for container-concentric corner geometry.

When a custom view sits near a window or container corner, its corner geometry should visually correspond to the enclosing container rather than using an unrelated arbitrary radius.

Avoid declaring one global radius such as `12` or `16` for every UI element.

---

## 14. Separators and Borders

Use semantic separators.

SwiftUI:

```swift
Divider()
```

or semantic separator styling where appropriate.

Avoid manually defining separator colors such as:

```swift
Color.gray.opacity(0.25)
```

unless required by a specific visual design.

### Borders

Do not use borders merely because transparency makes boundaries unclear. First reconsider the hierarchy and background treatment.

macOS 27 also supports user preferences that can increase border visibility. Custom controls should remain understandable when those settings are active.

---

## 15. Color

### Use color for meaning

Appropriate uses:

- selection
- current state
- warnings
- errors
- status
- branding accents
- data visualization

Avoid large areas of arbitrary saturated color behind standard macOS controls.

### Accent color

Use the application's accent color rather than manually coloring every selected component.

Prefer:

```swift
.tint(...)
```

when customization is needed.

---

## 16. Typography

Use system fonts by default.

Preferred hierarchy:

- Window title: system title behavior
- Primary heading: `.title2` or context-appropriate native style
- Section heading: `.headline`
- Body: `.body`
- Secondary information: `.secondary`
- Metadata: `.caption` or `.footnote`

Avoid custom fonts unless branding genuinely requires them.

Do not hard-code font sizes across the application when semantic styles will work.

---

## 17. Icons

Use SF Symbols whenever an appropriate symbol exists.

Requirements:

- Choose symbols based on function, not decoration.
- Keep symbol weight consistent with adjacent text.
- Do not mix unrelated icon styles.
- Use filled variants only when state or emphasis warrants it.
- Prefer platform-recognizable symbols over custom icons.

Custom icons are appropriate for product-specific concepts not represented by SF Symbols.

---

## 18. Spacing and Density

macOS applications should retain desktop information density.

Do not blindly copy iOS spacing.

General guidance:

- 4-8 pt: tightly related elements
- 8-12 pt: common control spacing
- 12-16 pt: local grouping
- 16-24 pt: section separation
- 24+ pt: major structural separation

Use system control sizing wherever possible instead of enforcing custom dimensions.

---

## 19. Selection

Use native macOS selection behavior.

Examples:

- sidebar row selection
- list selection
- table selection
- text selection

Do not create custom selection colors unless a product requirement demands it.

Selection should remain clear in:

- light mode
- dark mode
- high contrast
- reduced transparency
- different Liquid Glass appearance settings

---

## 20. Animation

Motion should communicate:

- state changes
- hierarchy
- navigation
- expansion/collapse
- object continuity

Avoid animation that exists only as decoration.

Respect Reduce Motion.

Use native transitions and control animations before custom spring configurations.

---

## 21. Accessibility Requirements

Every project MUST be tested with:

- Light Mode
- Dark Mode
- Reduce Transparency
- Increase Contrast
- Reduce Motion
- keyboard-only navigation
- VoiceOver for major workflows
- different Liquid Glass appearance/tint settings
- different window sizes

Never assume glass will remain equally transparent for every user. The system may modify or suppress transparency based on user preferences.

---

## 22. Window Resizing

macOS applications should adapt gracefully.

Requirements:

- define sensible minimum window dimensions
- avoid clipped toolbar actions
- allow content to reflow where appropriate
- use split views for resizable pane relationships
- preserve useful content when width is constrained
- do not assume a single fixed resolution

Menu-bar utilities and popovers may use fixed dimensions when the workflow genuinely benefits from them.

---

## 23. Light and Dark Mode

Never design only for Dark Mode.

Avoid hard-coded:

```swift
Color.white
Color.black
```

for standard content surfaces and labels.

Prefer semantic values:

```swift
.primary
.secondary
.windowBackground
.selection
.separator
.tint
```

where appropriate.

---

## 24. Compatibility Strategy

If the application supports older macOS releases, keep the core interface based on APIs available across the supported range.

For new macOS 27-only visual APIs:

```swift
if #available(macOS 27, *) {
    // macOS 27 enhancement
} else {
    // compatible fallback
}
```

Do not create a completely separate visual design for older systems. The application should retain the same hierarchy and interaction model.

---

## 25. Recommended SwiftUI Architecture

Example:

```swift
struct RootView: View {
    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            MainContentView()
                .background(.windowBackground)
        }
        .toolbar {
            ToolbarContent()
        }
    }
}
```

Principle:

- navigation/sidebar → system treatment
- toolbar → system treatment
- main content → stable semantic surface
- custom glass → only when necessary

---

## 26. Recommended NSWindow / AppKit Architecture

For AppKit-heavy applications:

- use `NSToolbar`
- use `NSSplitView`
- use `NSScrollView`
- use native controls
- avoid manually drawing title-bar materials
- avoid custom opaque layers over system navigation
- use semantic system colors
- allow standard components to inherit macOS appearance

Use `NSGlassEffectView` only for custom interface elements that truly need to behave as glass.

---

## 27. Menu-Bar Application Standard

For applications launched from `NSStatusItem`:

### Status item

- Prefer a recognizable monochrome SF Symbol or template image.
- Keep menu-bar presence visually simple.
- Use status indicators only when state genuinely matters.

### Popover

- Use native `NSPopover`.
- Avoid opaque root backgrounds.
- Keep navigation/system chrome translucent when appropriate.
- Keep long-form or dense content stable.
- Prefer system controls throughout.

### Popover sizing

Choose dimensions based on the workflow, not arbitrary symmetry.

Avoid making utility popovers unnecessarily large.

---

## 28. Search

Search should use standard macOS search controls.

Use:

- `.searchable(...)`
- `NSSearchField`

Do not create custom faux search fields unless necessary.

Search should normally appear near the content or navigation scope it affects.

---

## 29. Settings

Use native settings architecture.

SwiftUI:

```swift
Settings {
    SettingsView()
}
```

Settings should:

- use standard controls
- use logical sections
- avoid excessive glass
- prioritize scanning and clarity
- follow macOS keyboard behavior

---

## 30. Context Menus

Use native context menus for object-specific actions.

Do not hide essential primary actions exclusively inside a context menu.

Use:

```swift
.contextMenu {
    ...
}
```

or AppKit equivalents.

---

## 31. Keyboard Interaction

A Mac application should be fully useful from the keyboard.

Support appropriate conventional shortcuts:

- `⌘N` New
- `⌘O` Open
- `⌘S` Save
- `⌘F` Find
- `⌘W` Close
- `⌘,` Settings
- `⌘Z` Undo
- `⇧⌘Z` Redo

Only implement shortcuts relevant to the application.

Include menu commands when the action belongs in the macOS menu bar.

---

## 32. Anti-Patterns

Avoid the following unless there is a specific documented reason.

### Visual

- full-window custom blur
- opaque root backgrounds that suppress native chrome
- `.opacity(...)` used to simulate system materials
- multiple stacked glass cards
- glass behind long-form text
- excessive rounded rectangles
- arbitrary shadows
- excessive gradients
- hard-coded RGB colors
- hard-coded border colors
- custom toolbar backgrounds

### Interaction

- iOS-style navigation transplanted directly to Mac
- oversized touch-oriented buttons
- hidden hover-only essential functions
- nonstandard keyboard behavior
- custom controls that ignore accessibility settings
- excessive animation

---

## 33. Decision Matrix

| UI Region | Default Treatment |
|---|---|
| Window title bar | System |
| Toolbar | System / Liquid Glass |
| Sidebar | Native sidebar / Liquid Glass |
| Navigation | System / Liquid Glass |
| Inspector | System |
| Main document content | `windowBackground` |
| Text editor | Stable semantic content surface |
| Calendar | Stable semantic content surface |
| Dense table | Stable semantic content surface |
| Floating controls | System glass when appropriate |
| Search | Native search field |
| Footer utility bar | System / subtle glass |
| Alerts | Native |
| Menus | Native |
| Settings | Stable system surfaces |
| Decorative content | Content-driven, not glass-driven |

---

## 34. Project Review Checklist

Before release, verify:

### Structure
- [ ] Navigation and content are visually distinct.
- [ ] Main content is the visual focus.
- [ ] No unnecessary root-level opaque background suppresses system chrome.
- [ ] Sidebars use native behavior where appropriate.
- [ ] Toolbars use native APIs.

### Glass
- [ ] Liquid Glass is used primarily for navigation and controls.
- [ ] Custom glass effects are limited.
- [ ] There are no unnecessary overlapping glass layers.
- [ ] Long-form text remains on a stable readable surface.

### Controls
- [ ] Standard controls are used where possible.
- [ ] SF Symbols are used consistently.
- [ ] Selection uses system semantics.
- [ ] Context menus behave conventionally.

### Appearance
- [ ] Light Mode tested.
- [ ] Dark Mode tested.
- [ ] Multiple wallpaper/background conditions tested.
- [ ] Liquid Glass appearance/tint preferences tested.
- [ ] Increased contrast tested.
- [ ] Reduced transparency tested.

### Accessibility
- [ ] Keyboard navigation works.
- [ ] VoiceOver labels are meaningful.
- [ ] Reduce Motion is respected.
- [ ] Contrast remains sufficient.
- [ ] Focus state is visible.

### Window behavior
- [ ] Minimum size is sensible.
- [ ] Resize behavior is intentional.
- [ ] No clipping occurs.
- [ ] Split views behave naturally.
- [ ] State restoration is considered where appropriate.

---

## 35. Default Design Rule for New Projects

When starting a new macOS 27 project, use this default unless there is a clear reason not to:

```text
SYSTEM WINDOW
├── Native toolbar / header
├── Native sidebar or navigation
│
└── MAIN CONTENT
    └── Stable semantic window background
```

Then add custom glass only when an element is:

1. interactive,
2. visually elevated,
3. functionally part of navigation or control chrome, and
4. not already handled by a system component.

---

## 36. Quick Reference

### Prefer

```swift
.background(.windowBackground)
```

for stable content.

```swift
.listStyle(.sidebar)
```

for sidebar navigation.

```swift
.searchable(...)
```

for search.

```swift
.toolbar { ... }
```

for toolbar actions.

```swift
.tint(...)
```

for semantic application accent.

### Avoid by default

```swift
.background(Color(NSColor.windowBackgroundColor))
```

on the entire root hierarchy.

```swift
.opacity(0.8)
```

to imitate system translucency.

Custom blur/material stacks behind native controls.

Repeated `.glassEffect()` modifiers on ordinary content.

---

## 37. Design Philosophy Summary

A macOS 27 application should not be judged by how much glass it displays.

It should feel native because hierarchy, controls, navigation, content, typography, spacing, accessibility, and behavior all follow the platform.

The desired visual relationship is:

**Glass establishes interface hierarchy.  
Stable surfaces protect content.  
Native controls provide familiarity.  
The user's content remains the focus.**

---

## Apple References

- Liquid Glass technology overview:  
  https://developer.apple.com/documentation/technologyoverviews/liquid-glass

- Adopting Liquid Glass:  
  https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass

- SwiftUI `windowBackground`:  
  https://developer.apple.com/documentation/swiftui/shapestyle/windowbackground

- Apple Design Resources / macOS 27 UI kit:  
  https://developer.apple.com/design/resources/

- WWDC26 - Modernize your AppKit app:  
  https://developer.apple.com/videos/play/wwdc2026/289/

- WWDC26 Design guide:  
  https://developer.apple.com/wwdc26/guides/design/

---

## Recommended Use With Coding Assistants

Add this file to the root of each macOS project as:

`MACOS_27_DESIGN_SPEC.md`

Then instruct the coding assistant:

> Follow `MACOS_27_DESIGN_SPEC.md` for all visual, layout, interaction, SwiftUI, and AppKit decisions. Prefer native macOS components and semantic system styling. Do not introduce custom glass, opacity, blur, background colors, corner radii, or control replacements unless the design spec permits them or the project requirements explicitly require them.

For existing projects, also ask the assistant to identify violations of the specification before changing code.
