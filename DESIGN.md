---
name: dotfiles
description: One Mac, declared part by part. An unbuilt model kit on a cutting mat.
colors:
  mat: "#1e6a4c"
  mat-mark: "#1c6548"
  mat-shade: "#0c3524"
  on-mat: "#f7f8f5"
  on-mat-soft: "#d3e8dd"
  plastic: "#cdd5d8"
  plastic-shade: "#a4afb4"
  paper: "#f7f8f5"
  ink: "#14201b"
  ink-soft: "#3c4a45"
  on-ink-soft: "#c5d1cb"
  caution: "#e0483a"
typography:
  moulded-letter:
    fontFamily: "Archivo, Helvetica Neue, Arial, sans-serif"
    fontSize: "clamp(4.5rem, 30cqi, 9.5rem)"
    fontWeight: 800
    lineHeight: 0.76
  display:
    fontFamily: "Archivo, Helvetica Neue, Arial, sans-serif"
    fontSize: "clamp(2.375rem, 13.4cqi, 4.25rem)"
    fontWeight: 800
    lineHeight: 0.98
    letterSpacing: "-0.02em"
  headline:
    fontFamily: "Archivo, Helvetica Neue, Arial, sans-serif"
    fontSize: "clamp(2.5rem, 6vw, 4.5rem)"
    fontWeight: 800
    lineHeight: 0.95
    letterSpacing: "-0.025em"
  headline-tab:
    fontFamily: "Archivo, Helvetica Neue, Arial, sans-serif"
    fontSize: "clamp(1.875rem, 9.4cqi, 3rem)"
    fontWeight: 800
    lineHeight: 1.02
    letterSpacing: "-0.02em"
  title:
    fontFamily: "Archivo, Helvetica Neue, Arial, sans-serif"
    fontSize: "1.375rem"
    fontWeight: 700
    lineHeight: 1.15
  action:
    fontFamily: "Archivo, Helvetica Neue, Arial, sans-serif"
    fontSize: "1.25rem"
    fontWeight: 700
    lineHeight: 1.2
  part-name:
    fontFamily: "Archivo, Helvetica Neue, Arial, sans-serif"
    fontSize: "1.0625rem"
    fontWeight: 700
    lineHeight: 1.25
  body:
    fontFamily: "Archivo, Helvetica Neue, Arial, sans-serif"
    fontSize: "1.0625rem"
    fontWeight: 400
    lineHeight: 1.55
  label:
    fontFamily: "M PLUS Rounded 1c, Archivo, Helvetica Neue, Arial, sans-serif"
    fontSize: "0.9375rem"
    fontWeight: 500
    lineHeight: 1.2
    letterSpacing: "0.06em"
  numeral:
    fontFamily: "M PLUS Rounded 1c, Archivo, Helvetica Neue, Arial, sans-serif"
    fontSize: "1.75rem"
    fontWeight: 500
    lineHeight: 1
  caption:
    fontFamily: "ui-monospace, SF Mono, Menlo, Consolas, monospace"
    fontSize: "0.75rem"
    fontWeight: 400
    lineHeight: 1.2
rounded:
  focus: "0.125rem"
  part: "0.375rem"
  action: "0.5rem"
  tab: "0.625rem"
  part-corner: "1.125rem"
  runner: "clamp(1.25rem, 4vw, 1.75rem)"
  pill: "999px"
spacing:
  gate: "0.625rem"
  bar: "0.5rem"
  runner-gap: "1.25rem"
  mat-grid: "1.5rem"
  mat-grid-major: "7.5rem"
  gutter: "clamp(1rem, 5vw, 4.5rem)"
  section: "6rem"
components:
  action:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
    typography: "{typography.action}"
    rounded: "{rounded.action}"
    padding: "1rem 1.625rem"
  action-hover:
    backgroundColor: "{colors.mat-mark}"
    textColor: "{colors.paper}"
  action-on-box:
    backgroundColor: "{colors.plastic}"
    textColor: "{colors.ink}"
    typography: "{typography.action}"
    rounded: "{rounded.action}"
    padding: "1rem 1.625rem"
  action-on-box-hover:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
  name-tab:
    backgroundColor: "{colors.plastic}"
    textColor: "{colors.ink}"
    rounded: "{rounded.tab}"
    padding: "clamp(1.25rem, 4vw, 2.25rem)"
  part:
    backgroundColor: "{colors.plastic}"
    textColor: "{colors.ink}"
    typography: "{typography.part-name}"
    rounded: "{rounded.part}"
    padding: "0.5rem 0.9375rem 0.75rem"
    height: "4.125rem"
  part-listed:
    backgroundColor: "{colors.plastic}"
    textColor: "{colors.ink}"
    rounded: "{rounded.part}"
    padding: "0.625rem 0.875rem 0.75rem"
  callout:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    padding: "0.25rem 0.625rem"
  instruction-sheet:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    padding: "clamp(1.5rem, 4.5vw, 4rem)"
  step-number:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
    typography: "{typography.numeral}"
    size: "3rem"
  step-current:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
    padding: "1.5rem 1.25rem 1.375rem"
  balloon:
    textColor: "{colors.ink}"
    rounded: "{rounded.pill}"
    size: "2.75rem"
  balloon-hover:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
  mark:
    textColor: "{colors.ink}"
    typography: "{typography.label}"
    rounded: "{rounded.pill}"
    padding: "0.25rem 0.75rem 0.1875rem"
  mark-repeat:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
  slip:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    padding: "1.5rem 1.375rem 1rem"
  box-side:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
    padding: "4.5rem clamp(1rem, 5vw, 4.5rem) 2.5rem"
---

# Design System: dotfiles

## Overview

**Creative North Star: "The Unbuilt Kit"**

The public page is an unbuilt model kit laid out on a cutting mat. Every
declared tool is a numbered part still attached to its runner, the bootstrap is
the instruction sheet, and the page closes on the dark side of the box. The
system is physical and literal: a thing on the page is the mat, a piece of
plastic, or a piece of paper, and it is drawn the way that material behaves.

Density is high and even. Parts are small tiles packed into justified rows, the
instruction sheet is a ruled grid of step frames, and prose is short and kept to
narrow measures. Nothing is ornamental: the grid on the mat, the gates under a
part, and the shaded lower edge of the plastic are the decoration, and each one
is also structure.

The page is static HTML and CSS with self-hosted fonts. Motion is one short
snap, and it is removed under reduced motion.

**Key Characteristics:**

- Three materials carry everything: a green gridded mat, one unpainted grey
  plastic, and white paper in black line. Dark ink is the fourth surface, used
  for the box side alone.
- One typeface family for reading (Archivo) and one rounded single-stroke face
  for everything engraved or stamped (M PLUS Rounded 1c).
- Depth is cast shadow on the mat in a single dark green tint, plus a shaded
  lower edge that gives plastic its thickness.
- Plastic is rounded, paper is square.
- Red appears once, on the caution mark.
- The signature interaction is the snap: a part lets go of its gates, lifts, and
  turns slightly over its shadow.

## Colors

A saturated cutting-mat green holds a cool grey plastic and a near-white paper;
dark green-black ink does the writing, and one red is reserved for caution.

### Primary

- **Cutting Mat Green** (`mat`, #1e6a4c): the ground of the whole page, the
  browser theme color, and the favicon field. It also returns as the text
  selection color on plastic and paper.
- **Mat Grid Lines** (rgb(124 190 160), untokenized): the ruled grid on the
  mat. Minor lines every 1.5rem at 0.2 opacity, major lines every 7.5rem at 0.5
  opacity, all 1px.
- **Moulded Green** (`mat-mark`, #1c6548): green pressed into plastic. It
  colors the moulded runner letter on a name tab, the hover state of the dark
  action, and the knob of a switch that is on. It is never used on the mat
  itself.
- **Mat Shade** (`mat-shade`, #0c3524): the darkest green. It is the scrollbar
  track and, at 0.7 opacity, the track of a switch that is off.

### Secondary

- **Unpainted Plastic** (`plastic`, #cdd5d8): runner frames, runner bars,
  gates, name tabs, parts, the switch outline and knob, and the action when it
  sits on the box side.
- **Plastic Shade** (`plastic-shade`, #a4afb4): the lower edge of a name tab
  (0.375rem) and of a part (0.3125rem), drawn as a hard band. It is the only
  place plastic shows thickness.

### Tertiary

- **Caution Red** (`caution`, #e0483a): the caution triangle on the box side.

### Neutral

- **Sheet Paper** (`paper`, #f7f8f5): the instruction sheet, the two slips,
  the callout, and text on ink.
- **On Mat** (`on-mat`, #f7f8f5): text set directly on the mat, and the focus
  ring on the mat. Same value as paper, named separately for its role.
- **On Mat Soft** (`on-mat-soft`, #d3e8dd): secondary text on the mat: the
  hint under a runner's name and the group labels above a set of parts.
- **Kit Ink** (`ink`, #14201b): text and line on plastic and paper, the dark
  action, step numbers, the closing step frame, and the box side.
- **Ink Soft** (`ink-soft`, #3c4a45): secondary text on plastic and paper:
  part numbers, part descriptions in the list, slip footers, list markers.
- **On Ink Soft** (`on-ink-soft`, #c5d1cb): body text on the box side.

### Named Rules

**The Three Materials Rule.** Every surface is the mat, the plastic, or the
paper. A new element is assigned to one of them and takes that material's
color, corner, and shadow; it does not get a color of its own.

**The Caution-Only Red Rule.** Red belongs to the caution mark alone. It is not
a link color, an error color, or an accent.

**The Soft Pair Rule.** Each ground has exactly one quieter text color:
`on-mat-soft` on the mat, `ink-soft` on plastic and paper, `on-ink-soft` on
ink. Secondary text uses the pair for its ground and never opacity.

## Typography

**Display Font:** Archivo, variable in weight and width (with Helvetica Neue,
Arial, sans-serif)
**Body Font:** Archivo (same stack)
**Label Font:** M PLUS Rounded 1c at weight 500 (falling back to the Archivo
stack)
**Mono Font:** the system monospace stack (ui-monospace, SF Mono, Menlo,
Consolas), for inline code and figure captions only

**Character:** A heavy, tight grotesque sets the headlines like box-lid
lettering, and the same family at regular weight carries the reading. The
rounded single-stroke face is the engraving: part numbers, counts, step
numerals, and stamped labels, always uppercase and letterspaced.

### Hierarchy

- **Moulded Letter** (800, clamp(4.5rem, 30cqi, 9.5rem), line-height 0.76; a
  fixed 3.5rem on a phone): the runner's letter on its name tab, in Moulded
  Green.
- **Display** (800, clamp(2.375rem, 13.4cqi, 4.25rem), line-height 0.98,
  -0.02em): the page headline on the lead name tab. Sized against the tab's own
  width, not the viewport.
- **Headline** (800, clamp(2.5rem, 6vw, 4.5rem), line-height 0.95, -0.025em):
  section headings on the instruction sheet and on the mat. A name tab that
  heads a later runner uses the smaller tab headline (800, clamp(1.875rem,
  9.4cqi, 3rem), line-height 1.02, -0.02em).
- **Title** (700, 1.375rem, line-height 1.15): step headings and the heading of
  the records slip. Box-side headings use the same weight at 1.5rem.
- **Action** (700, 1.25rem, line-height 1.2): the action label.
- **Part Name** (700, 1.0625rem, line-height 1.25): a part's name. Below 40rem
  it drops to 1rem and narrows to 78% width.
- **Body** (400, 1.0625rem, line-height 1.55): reading text. Measures are
  capped per context: 36ch on a name tab, 46ch on the mat and the box side,
  62ch on the sheet, 70ch for the colophon. Lead paragraphs on the sheet and
  the mat are 1.125rem.
- **Label** (M PLUS Rounded 1c, 500, 0.8125rem to 1rem, line-height 1.2,
  0.06em, uppercase): part numbers, the runner count and name, group labels,
  the switch label, step marks, slip heading and footer, the box-side
  specification line.
- **Numeral** (M PLUS Rounded 1c, 500, line-height 1): step numbers at 1.75rem,
  balloon letters at 1.375rem, the count figure at 1.375rem.
- **Caption** (system mono, 0.75rem, line-height 1.2): the file names under a
  figure. Inline code is the same stack at 0.9em of its context.

### Named Rules

**The Engraved Rule.** Anything stamped into the kit is M PLUS Rounded 1c at
weight 500, uppercase, letterspaced 0.06em. Anything read as prose or as a name
is Archivo.

**The No Light Weight Rule.** Archivo runs from 400 for reading to 800 for
headlines; names, titles, and actions are 700. Nothing is set lighter than 400.

**The Tab-Relative Rule.** Type on a name tab is sized in container units of
the tab, so the headline keeps its proportion to the plastic it is moulded
into at every width.

## Layout

The page has no centered container. Everything sits between a fluid gutter
(clamp(1rem, 5vw, 4.5rem)) on the mat, sections are separated by 6rem, and the
box side runs edge to edge.

The mat grid is 1.5rem with a heavier line every fifth step (7.5rem).

A runner is a frame holding a name tab and a tree of parts with a 1.25rem gap.
Below 60rem they stack. From 60rem the frame is two columns (minmax(20rem,
0.76fr) and 1fr), the name tab is sticky 1.25rem from the top, and the lead tab
is as tall as the first viewport allows (clamp(30rem, 100svh - 14.25rem,
44rem)) with its action pinned to the bottom edge.

Inside a tree, one line names the runner: the count, the name, and the
Descriptions switch. On a phone the count and the switch share the first line
and the name takes the next. Sets of parts wrap, and a set is only as wide as
its parts, so short groups share a row.

The instruction sheet is a ruled grid of step frames: one column on a phone,
two from 40.0625rem, three from 60rem. Wide steps span two columns. The
inspection section is one column, then a lead above two slips (1fr 2fr), then
three columns (5fr 3fr 4fr). The box side is one, two, then three columns
(1.2fr 1fr 1fr), with the specification line and the colophon spanning the
full width.

Breakpoints are 22.5rem (narrowest phones, switch label one size down), 40rem
(phone), and 60rem (two-column runner, three-column sheet).

## Elevation & Depth

Depth is physical and shallow. Objects lie on the mat and cast one kind of
shadow, a dark green tint (rgb(6 30 21)) that is never neutral black. Plastic
shows thickness through a hard shaded band on its lower edge, not through
shadow. The box side is flat.

### Shadow Vocabulary

- **Lift** (`box-shadow: 0 0.125rem 0.25rem rgb(6 30 21 / 0.45)`): a part or a
  name tab at rest.
- **Frame** (`box-shadow: 0 0.1875rem 0.375rem rgb(6 30 21 / 0.45), inset 0 0.1875rem 0.375rem rgb(6 30 21 / 0.45)`): the runner frame, casting outward
  onto the mat and inward onto the mat it encloses.
- **Bar Cast** (a 0.25rem gradient from rgb(6 30 21 / 0.4) to transparent): the
  shadow that hangs under each horizontal runner bar.
- **Paper** (`box-shadow: 0 0.25rem 0.75rem rgb(6 30 21 / 0.45)`): the
  instruction sheet and the slips.
- **Callout** (`box-shadow: 0 0.375rem 0.75rem rgb(6 30 21 / 0.5)`): the paper
  callout under a snapped part.
- **Snapped** (`box-shadow: 0 0.875rem 1.125rem -0.25rem rgb(6 30 21 / 0.6)`):
  a part lifted off its gates.

### Named Rules

**The Cast Shadow Rule.** A shadow means an object is lying on the mat. It is
always the dark green tint, always falls straight down, and grows only when
the object is lifted.

**The Thickness Rule.** Plastic gets its depth from a hard band of Plastic
Shade along its lower edge. The band has no blur.

## Shapes

Plastic is rounded and paper is square. Parts and gates carry a small radius
(0.375rem), the action 0.5rem, a name tab 0.625rem, and the runner frame the
largest (clamp(1.25rem, 4vw, 1.75rem)). The instruction sheet, the step
frames, the step numbers, the slips, and the callout have no radius.

Kit parts are not all one outline: on the runner, some parts swell one or two
corners to 1.125rem, on a repeating count across the row, so a row reads as
moulded pieces and not as a uniform grid of cards.

Plastic structure is drawn at fixed gauges: runner bars and the list spine are
0.5rem, gates are 0.3125rem wide and 0.625rem long, two per part at 22% from
each side. The runner frame's wall is clamp(0.625rem, 2.2vw, 1rem).

Paper is drawn in line: 0.09375rem ink rules for step frames, balloons, marks,
and the callout border; a dashed rule in Ink Soft above a slip's footer; 1px
hairlines at low opacity between records and above the box-side specification
line. Figures are outline drawings on a 1.75 stroke with round caps and joins,
in the current text color. Circles and pills are reserved for drawn marks:
balloons, step marks, and the switch.

On tablet and desktop the checklist slip lies rotated -1.5 degrees; nothing
else on the page is rotated at rest.

## Components

### Action

One moulded button, dark on plastic and plastic on the box.

- **Shape:** gently rounded (0.5rem), padding 1rem 1.625rem; on a phone
  0.875rem 1.375rem at 1.125rem type.
- **On plastic:** Kit Ink ground, Sheet Paper label, Archivo 700 at 1.25rem.
- **On the box side:** Unpainted Plastic ground, Kit Ink label.
- **Hover / Active:** the ground changes to Moulded Green (to Sheet Paper on
  the box side) and the button presses down 0.0625rem when active, both on the
  140ms snap.
- **Focus:** the 0.1875rem ring, in Kit Ink on plastic.

### Navigation

- The wordmark is Archivo 800 at 1.125rem; links are Archivo 500 at 0.9375rem
  with 0.02em tracking, set directly on the mat in On Mat with no ground of
  their own.
- Links are not underlined at rest and underline on hover. The masthead wraps
  on narrow screens; it does not collapse into a menu.
- Text links elsewhere inherit their color and keep an underline (0.09em, offset
  0.2em) that thickens to 0.16em on hover.

### Runner and name tab

- **Runner:** a plastic frame (the border is the plastic) around the bare mat,
  with the Frame shadow. It holds one name tab and one tree.
- **Name tab:** a plastic plate (0.625rem radius, Thickness band 0.375rem,
  Lift shadow) carrying the moulded letter, a headline, a short paragraph, and
  on the lead tab the action.
- **Runner line:** the count, the runner's name, and the switch in the Label
  face on the mat, followed where needed by a one-line hint in On Mat Soft.

### Part

A part is one declaration: a part number in the Label face (Ink Soft,
0.8125rem) above its name (Archivo 700). The whole part is a link. The part
lists are generated from the repository's declarations; the system defines how
a part looks, never what it says.

- **On the runner:** parts hang in justified rows from horizontal bars. Each
  is a plastic tile at least 4.125rem tall (3.75rem on a phone) with the
  Thickness band and the Lift shadow, held by two gates. A part grows to a
  little past the length of its own name and no further, so a short name alone
  in a row stays a part.
- **The snap:** on hover or focus the gates retract, the part lifts 0.625rem
  and turns 4 degrees (alternating direction by position) under the Snapped
  shadow, and a paper callout names what the part is for. The focus ring is On
  Mat, offset 0.1875rem.
- **Callout:** a square paper slip with a 0.09375rem ink border, 0.875rem
  text, tucked under the lifted part where anchor positioning is available and
  centered at the foot of the window where it is not.
- **In the list:** with the Descriptions switch on, and in any browser without
  `:has()`, parts hang from a single vertical spine in columns of at least
  17rem, each a plastic card with one gate, its number and name on one line and
  its description below in Ink Soft. Hover underlines the name; nothing moves.

### Descriptions switch

- A checkbox drawn as a 2.5rem by 1.375rem pill with a plastic outline and
  knob on a Mat Shade track, labelled in the Label face.
- On, the track fills with plastic and the knob turns Moulded Green and slides
  across on the snap.
- It is present only where the runner layout is; the list is the default
  without it.

### Instruction sheet

- **Sheet:** square white paper with the Paper shadow, padding clamp(1.5rem,
  4.5vw, 4rem) (1rem on a phone), a Headline and a lead paragraph above the
  steps.
- **Step frame:** a cell in a grid ruled in 0.09375rem ink, padded 1.5rem
  1.25rem 1.375rem. A 3rem ink square in the top-left corner carries the step
  number in the Numeral face.
- **Figure:** a step is drawn before it is described: outline figures with a
  mono caption, joined by an arrow. A solid arrow is an action; a dashed arrow
  is a link.
- **Balloon:** a 2.75rem ink-ruled circle holding a runner's letter, linking
  to that runner. It fills with ink on hover. In a wide step it grows to 4rem.
- **Mark:** an ink-ruled pill in the Label face at the foot of a step. Outline
  for a step that happens once; filled ink for a step that repeats.
- **Closing frame:** the last cell is filled ink with paper text and no
  number.

### Slips

- **Checklist slip:** square paper with the Paper shadow, a heading and footer
  in the Label face, items in Archivo 600 numbered in Ink Soft numerals, and a
  dashed rule above the footer. Rotated -1.5 degrees from 40.0625rem.
- **Records slip:** square paper, a Title, a short note in Ink Soft, and a
  numbered list of links separated by low-opacity hairlines.

### Box side

- A full-width Kit Ink panel that closes the page, padded 4.5rem above and
  2.5rem below, with headings in Archivo 700 at 1.5rem and body text in On Ink
  Soft.
- The caution mark (3rem by 2.75rem, a 3.5 stroke triangle) sits above the
  first heading in Caution Red.
- The action appears here in its plastic form.
- A specification line in the Label face, above a hairline, and a colophon at
  0.875rem close the panel.

### Focus and selection

- **Focus:** a 0.1875rem solid ring, offset 0.1875rem. On Mat on the mat and
  for a part on its runner; Kit Ink on plastic and paper.
- **Selection:** Kit Ink on the mat; Cutting Mat Green on plastic and paper;
  Unpainted Plastic on the box side.

### Motion

- One timing for everything: 140ms on cubic-bezier(0.16, 1, 0.3, 1). It
  decelerates and does not overshoot.
- It is applied to the snap, the gates, the switch, the callout's opacity, and
  hover color changes.
- Under reduced motion every transition is instant and a part does not move;
  the callout still appears.

## Do's and Don'ts

### Do:

- **Do** assign every new element to the mat, the plastic, or the paper, and
  give it that material's color, corner, and shadow.
- **Do** set stamped text (numbers, counts, labels) in M PLUS Rounded 1c 500,
  uppercase, 0.06em, and everything read as prose or a name in Archivo.
- **Do** tint every shadow rgb(6 30 21) and let it fall straight down.
- **Do** give plastic its thickness with a hard Plastic Shade band on the
  lower edge (0.3125rem on a part, 0.375rem on a name tab).
- **Do** keep paper square and ruled in 0.09375rem ink, and draw figures in
  outline on a 1.75 stroke.
- **Do** pair each ground with its own soft text color: `on-mat-soft`,
  `ink-soft`, `on-ink-soft`.
- **Do** switch the focus ring to Kit Ink on plastic and paper and keep it On
  Mat on the mat.
- **Do** use the single 140ms snap for every state change, and keep every
  description reachable without motion and without hover.
- **Do** keep the part lists generated; style the part, never retype it.

### Don't:

- **Don't** use Caution Red anywhere but the caution mark.
- **Don't** add a bounce, an overshoot, or a second timing to the snap.
- **Don't** round the corners of paper, or square the corners of plastic.
- **Don't** use a neutral black or grey shadow; shadows are the dark green
  tint.
- **Don't** introduce a color that is not one of the three materials or the
  ink.
- **Don't** set a headline in the engraved face or a part number in Archivo.
- **Don't** load a font, script, or image from another origin; the two
  typefaces are self-hosted.
