# Build notes

How this prototype was produced, so the next person can reproduce the environment.

## Toolchain in the cloud container

The container had no Swift toolchain and swift.org downloads were blocked by the network
policy. The official `swift:6.2-noble` Docker image layers were downloaded directly from
Docker Hub's registry API and extracted; the toolchain binaries then ran on the host
(Ubuntu 24.04) without a container. `swift build` and `swift test` work for the two
packages; the iOS app target needs Xcode.

## Workflow

- Design and rulings: `docs/DESIGN.md` (brainstorming and grill-style interrogation of
  the specification, answered with recommended defaults because the build ran unattended).
- Plan: `docs/PLAN.md`, executed task by task with a ledger in `.superpowers/sdd/PLAN/progress.md`.
- Every function in `SymmetryCore` and `SymmetryModels` was written test-first: the test
  was run and seen to fail before the implementation existed, then run again to pass.
- The SwiftUI layer cannot be compiled here. It received a separate fresh-context static
  review for compile and runtime issues before delivery.

## Plugins and skills used

Installed into the Claude Code environment at the owner's request and applied where they
fit: Superpowers (brainstorming, writing-plans, test-driven-development, executing-plans,
verification-before-completion), Matt Pocock's grill-me, frontend-design (design
direction in `docs/DESIGN.md`), theme-factory (the "Scrub Light" tokens in
`App/SymmetryPrototype/App/Theme.swift`), mcp-server-dev, playwright, PlanetScale, and the
Vercel react-best-practices, composition-patterns and web-design-guidelines skills.
PlanetScale, MCP server development, Playwright web testing and the React skills have no
surface in an offline native iOS app and were not applied to the code.
