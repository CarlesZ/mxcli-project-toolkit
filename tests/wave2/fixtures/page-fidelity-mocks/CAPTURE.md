# page-fidelity-mocks — what these two wireframes are, and what was changed

`page-fidelity.js` parses **wireframe HTML**, so per `CLAUDE.md` -> "Shipping an instrument"
rule 1 its fixture input must be a real capture, not something imagined. These two files
reproduce the STRUCTURE of two real wireframes from a **MOC/PSSR app replacement**
(requirements-driven, 2026-09-09) — the grouped project overview and the approver queue —
and **only their literal text and class prefixes were changed**, because the wireframes
themselves and the palette in them are a customer's.

**What is verbatim, because every one of these is a fact nobody would have imagined:**

- the `div.wf-wrap > div.wf-screen` boundary, with `div.anno` as a **sibling** of the
  screen and not a child;
- `.page-head` holding the page's only `<h1>` **and** a `.sub` paragraph **and** a
  `.page-actions` block, all in one once-used div;
- `.toolbar` once-used, holding a search input and a filter select;
- the group heading / table / pager triple **repeated twice**, which is what makes
  `.x-group-head`, `.x-tablewrap` and `.pager` used-twice and `.page-head` used-once in
  the same file — the pair the classifier has to separate;
- sample rows as `<td>` text with chips as `<span>`, three list items in the other file;
- the whole class vocabulary declared in the wireframe's **own** `<style>` block, which is
  what puts all of it in front of the classifier in the first place.

**What was changed:** the record names, department names, site codes, page titles and the
class prefix (`ds-` -> `x-` for the design-system-looking names, so the fixture cannot be
mistaken for a claim about any real design system). No line was reflowed, no block
reordered, no selector altered, no structure simplified.

**Two `class="bound"` elements were ADDED to `grouped-overview.html`**, and they are the one
thing here that is not a reduction of the real file: an `<h2 class="bound">` holding a record's
own title and a `<span class="bound">` holding a filename. They stand in for the real detail
page's `<h1>` and file chip, which is where the defect was found (54%, all three misses being
sample values a correctly binding page cannot contain). Reproduced on the overview fixture
rather than adding a third wireframe, because the marker's behaviour has nothing to do with
which screen carries it.

**Counts measured on the REAL overview wireframe** (the numbers the defect was found on):

| class | uses | subtree kept when dropped | old verdict | correct verdict |
|---|---|---|---|---|
| `page-head` | 1 | 0.513 | mock (deleted the h1) | structure |
| `toolbar` | 1 | 0.825 | mock | structure |
| `ds-card` | 1 | 0.962 | mock | structure |
| `ds-tablewrap` | 2 | 0.172 | mock | mock |
| `ds-state` | 10 | 0.795 | mock | mock |

The old rule was `uses === 1 && kept < 0.4` -> structure. Only `ds-card`-sized wrappers
cleared it; the page header did not, and it is the one holding the heading.

## bind-contract — the five-column bind table and DESCRIBE's blind ImageUrl (2026-09-23)

`bind-contract.html` carries five rows of the real bind table in a field project's
`CatalogView-redesign-v2.html`, **verbatim in markup and prose** — including the struck
`<s>Demo chip</s>` row with its `CUT —` verdict, the CSS cell "(already a ds.css candidate)",
and the Dark-mode cell naming `#mxapp.theme-dark`. Changed: the class prefix (`mps-` -> `x-`)
and the attribute names (`LastPublishedVersionLogo` -> `LogoUrl`,
`PublisherOrganizationLogo` -> `PublisherLogoUrl`, `LastPublishedVersionDemoUrl` -> `DemoUrl`).

`bind-contract-describe.mdl` is a reduction of `mxcli describe page` (v0.23.0) output for the
built page: the two `image` widgets are verbatim apart from names, and they show the fact
nobody would have imagined — `ImageUrl: '{1}'` with **no parameters**, although the `.mpr`
holds a `Forms$ClientTemplate` whose `Parameters` carry the attribute (read from the unit's
BSON). The surrounding widgets were cut to what the rows need.

`bind-contract-alter.mdl` is the binding script's shape (`set ImageUrl = [Attr] on <widget>`),
which is what makes those bindings visible to the scorer.

Measured on the real page: bindings 13/18 -> 14/16 (DemoUrl row no longer owed; the two
image rows seen through the ALTER script), contract 16/30 -> 16/29 (`.css` gone).

## commented-template — a template comment that names `<main>` (2026-10-02)

`commented-template.html` reduces a wireframe from a requirements-driven build whose team
wrote its own wireframe template. **Verbatim in shape:** the `<!DOCTYPE>` followed by a
header comment whose rules say "inside `<main>`" and "AFTER `</main>`" (rules 3 and 7 kept
word for word apart from the product name); `div.app-shell > aside.app-rail` with a
`.userchip`; `div.app-main > main.page-column` holding `.page-header` (crumb, `h1.page-title`,
`p.page-sub`), `.seg-tabs`, a `.dg-toolbar`, a bound `.inbox` list, an `h2.section-title`
and a `table.dg`; then `div.wf-anno` with `table.bind` **after** `</main>`. **Changed:** every
name and sample value (the domain became orders and customers), and the rail, filters, rows
and bind table were cut to two or three entries each.

On the real wireframe, master's `contentOf()` matched `<main` inside the comment and scored
the comment text: `headings 0/0 actions 0/0 content 0/0 classes 0/0 bindings 3/6`, printed
as `fidelity 50%`; a sibling page printed `fidelity 100%` on `bindings 1/1`. On this fixture
master prints `fidelity 100% … bindings 2/2`; with comments stripped it is
`text-match 85% … headings 2/2 … classes 6/22 … bindings 2/2`.

`commented-template.mdl` is the page built to that wireframe; `-stub.mdl` is the same page as a
forward-reference stub carrying a `Stub:` caption; `-snippets.mdl` moves the page header into a
snippet declared in the same file and calls a second snippet that is not in the input.

## dynclasses-* — the DynamicClasses shapes (2026-10-05)

`dynclasses-describe-v025.mdl` is **verbatim** `DESCRIBE PAGE` output from mxcli v0.25.0
(built from the v0.25.0 tag) on a scratch copy of mxcli's own public `testdata/pedapp`, after
`exec` of `dynclasses-script.mdl`. Only its four `--` header lines were added. It is the shape
the parser had never seen: v0.25 prints the expression bare (`DynamicClasses: if … then
'is-active' else 'is-idle'`), under `--mdl 0` as well. `dynclasses-script.mdl` is the
headerless script as exec'd (quoted form). `dynclasses.html` is a **synthetic** one-card
wireframe; nothing in it is a fact about a real wireframe — the case is about the MDL side.

## product-overview — text matched on what the page shows; ButtonStyle classes (2026-10-13)

The MDL side is **not copied here**: the test reads the real `mxcli describe page` capture that
already lives at `tests/wave2/fixtures/context-pack/capture/describe/PAGE__Sales.Product_Overview.out`.
It carries what the two rules need and nobody would have imagined: a multi-line `actionbutton`
with `ButtonStyle: Primary`, one with `ButtonStyle: Danger`, two with **no** ButtonStyle (DESCRIBE
omits the Default style), a page named `Product_Overview` whose title is `'Catalog'`, a
microflow `ACT_Product_Deactivate` behind a button captioned `'Deactivate'`, and a `-- Context:`
comment inside the grid.

`product-overview.html` is **synthetic**, one element per rule. Shown by the page: the H1
`Catalog`, the sub-title paragraph, `New item` / `Edit` / `Delete` buttons with
`btn btn-<style>` classes. Not shown by the page: an H2 `Product overview` (only the page
*name* carries those words), a `Deactivate product` button (the caption is `Deactivate`; the
second word is in identifiers only), an `Add` button (no `>3`-char word, so it used to pass
vacuously), and a `row-actions` wrapper the page does not declare.

Master: `89% headings 2/2 actions 5/5 content 1/1 classes 4/9`. Fixed: `73% headings 1/2
actions 3/5 content 1/1 classes 8/9`.

The ButtonStyle → `btn btn-<style>` mapping rests on `learned-stylegallery.md` → "The Mendix
DOM contract" (ACTIONBUTTON → `<button class="btn mx-button … btn-default">`, measured in a
running 11.13 app). Only the Default style was measured there; the other styles follow the
same `btn-<lowercase style>` class, which is how Atlas styles them. A rendered-DOM capture of a
non-default style is still owed.

## layout-app-default — chrome from the page's layout (2026-10-13)

`layout-app-default.mdl` is **upstream mxcli's own example**, verbatim: the
`LayoutTest.App_Default` layout and `LayoutTest.Home` page from `mendixlabs/mxcli`
`mdl-examples/doctype-tests/layouts.mdl` at commit `bd45c47` (Apache-2.0), which upstream's
doctype test execs. It is a script, not a field capture — no field project in this repo has
a captured `describe layout`; upstream documents that `DESCRIBE LAYOUT` emits this same
re-executable form. `layout-app-default.html` is **synthetic**: the page drawn inside its
frame, with the layout's `region-topbar` / `region-sidebar` / `region-content` classes.

Master: `71% classes 0/2` (the layout's region classes scored as the page's). Fixed, with the
layout in the input or named with `--chrome`: `100% classes 0/0`, both reported as chrome.
Without either, the default chrome set is unchanged and the classes are still owed.

## alter-multiline — review counter-case for the caption match (2026-10-13)

**Synthetic**, all three files: the independent review's counter-case, kept as written apart
from the marker comments and the `btn btn-success` classes on the Approve button. It pins three
things the first cut of the caption match got wrong: an ALTER `set (…) on w` spread over
several lines (the segment ended at the first newline and dropped `'Approve order'`); a
plural wireframe heading (`Orders`) against a singular title (`'Order'`), which whole-word
matching without a plural fold read as missing; and a ButtonStyle set by that ALTER. Misses
that remain are real: `Save changes` vs the caption `'Save'`, an icon-only Edit button with an
empty caption, and `Recent activity`, whose second word is a bound parameter.
