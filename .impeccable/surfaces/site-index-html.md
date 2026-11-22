---
version: 1
slug: "site-index-html"
primary_target: "_site/index.html"
related_targets: []
---

# Surface brief: the dotfiles page

Scope: one static page, `_site/index.html`, published to GitHub Pages. Visitor
mode: Persuade.

## Audience, job, and action

A curious developer arrives from GitHub or a link with their own setup in
mind. They want to understand the approach and take ideas, not install it.
The primary action is "Read the source", a link to the repository.

## Proof and content

The parts are the real declarations, rendered from `Brewfile` and
`mise/config.toml` by `_scripts/render-software-catalog --page`: three runners
(command-line tools, applications and fonts, Mise runtimes and CLIs), each
part linking to the line that declares it. Assembly restates the bootstrap and update
lifecycle from the README. Inspection points to the fixture suites, the macOS
CI run, and the decision records. The closing panel states the personal scope.

## Constraints

Static HTML and CSS, no JavaScript, no build step, self-hosted fonts, no
third-party requests, WCAG 2.2 AA. Page copy is English. Counts and part
lists are generated, never typed. Mise versions stay off the page so an
upgrade cannot make it stale.

## Direction contract

THESIS: The Mac is an unbuilt model kit: every declared tool is a numbered
part still on its runner, and bootstrap is the assembly. It refuses the
terminal-costume page with a typed install command and a feature grid.

OWN-WORLD: A green gridded cutting mat is the ground. Runners, gates, name
tabs, and parts are one unpainted grey plastic, lettered in engraved
single-stroke numerals. The instruction sheet is white paper in black line
with numbered step frames and part balloons. Red appears only on the caution
mark. A dark box-side panel closes the page.

STORY: The visitor sees that the whole machine is written down part by part,
learns how the parts are assembled and kept current, sees what holds the
declarations to their word, and leaves for the repository. The order is
runner A, Assembly, Inspection, runners B and C, box side: the owner confirmed
that sequence. Runner A demonstrates the mechanism, the story follows while it
is fresh, and the other two runners are the reference a visitor browses after.
Assembly therefore names runners B and C as further down the page.

FIRST VIEWPORT: Runner A fills the viewport on the mat. Its name tab, at the
left, carries the moulded letter A, the headline "One Mac, declared part by
part.", two sentences, and the "Read the source" action. To its right the
command-line tools hang in rows from horizontal runners, each tile a part
number and a name. Navigation sits on the mat above the frame.

SIGNATURE INTERACTION: Pointing at or focusing a part snaps it off its gates:
the gates retract, the part lifts and turns slightly over its shadow, and a
paper callout names what it is for. Motion is one short, crisp snap with no
bounce; reduced motion keeps the callout and drops the movement. A
"Descriptions" switch on each runner lays the parts out as a parts list, which
is also how a touch screen reads the descriptions.

FORM: Model-kit runner and instruction sheet; candidate 6 of 7 on the ordered
list; seed:7294583e3f8618d2.

FINISH: unreviewed and undocumented is unfinished; this build ends with the
finish review, the verdict, DESIGN.md, and every shipping raster carrying its
provenance

## Publishing

`.github/workflows/pages.yml` deploys `_site/` to GitHub Pages after CI passes
for a push to `main`. The owner authorized the workflow and enabling Pages.
