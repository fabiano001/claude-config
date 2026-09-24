# Confluence HTML+ format for general documentation pages

This is the exact, verified HTML+ format the Atlassian MCP tools accept. It renders with full rich formatting. **Never** use `contentFormat: "markdown"` (escapes everything to literal text) and **never** use raw storage format (`<ac:layout>`, `<ac:structured-macro>`, CDATA — the API rejects these).

This reference is a sibling of `create-spike-document/references/confluence-html-format.md`, with two structural differences: **no two-equal-column layout at the top** — the Table of Contents is the first thing in the body instead of sitting below a layout section — and **only one default trailing section (Appendix)**, not the spike document's five (Out of Scope, Jira Tickets, Effort Size, Dependencies, Appendix).

## Tool call shape

Update the existing target page (the skill overwrites the page at the given URL):

```
updateConfluencePage(
  cloudId: "<site cloudId — Boats Group: ba2e3477-a4e5-4924-a530-47c471494d0f>",
  pageId: "<numeric id from the URL>",
  title: "<keep the page's current title unless told to change it>",
  body: "<the HTML string below>",
  contentFormat: "html",
  versionNumber: <current version.number + 1>
)
```

Always call `getConfluencePage` first to read the current `version.number` and `title`.

## Building blocks

### Table of Contents (the very first thing in the body)

Auto-generates from the `<h2>`/`<h3>` headings — no manual link list needed. No layout section precedes it in this skill.

```html
<div data-type="extension" data-extension-key="toc" data-extension-type="com.atlassian.confluence.macro.core"></div>
```

### Section headings

Use real heading elements (the ToC links to these):

```html
<h2>Section Title</h2>
<h3>Sub-section Title</h3>
<p>Body text…</p>
```

### The diagram section: choosing between "Architecture Diagram" and "Process Flow"

This is the second fixed section, and it needs an actual diagram, not just prose — but Confluence's HTML+ API has no native flowchart macro reachable from these MCP tools. Two decisions, in order:

**Decision 1 — title.** Pick exactly one; never write both words in the same heading (`<h2>Architecture Diagram or Process Flow</h2>` is wrong):

| Use this title… | …when the page is primarily documenting | The diagram shows |
|---|---|---|
| `<h2>Architecture Diagram</h2>` | A *system* — a service, its components, and how they connect | A structural map (boxes = components/services, arrows = calls/data flow) |
| `<h2>Process Flow</h2>` | A *process* — a sequence of steps a user, operator, or workflow moves through | A sequence (boxes = steps/stages, arrows = "then") |

If the page has real content for both a system and a process, title this section after whichever is the **primary subject** of the page, and put the other as a caller-supplied body section or fold it into the Appendix — don't invent a compound heading to cover both.

**Decision 2 — how to render it.** Pick based on what's available in context, in this priority order:

1. **A real diagram image already exists** (e.g. published earlier this session as an Artifact, or a screenshot/export the operator supplied with a reachable URL) → embed it directly:
   ```html
   <p><img src="<image URL>" alt="Architecture diagram" /></p>
   ```
2. **No image exists — build a clean text/box diagram** (the default case). Use a monospace code block so spacing/alignment survives Confluence's renderer:
   ```html
   <pre><code class="language-text">
   ┌─────────────┐      ┌─────────────┐      ┌─────────────┐
   │   Funnel     │ ──▶  │  Cloud Func  │ ──▶  │  Salesforce  │
   │  (frontend)  │      │  (backend)   │      │   (CRM)      │
   └─────────────┘      └─────────────┘      └─────────────┘
   </code></pre>
   ```
   Keep it to the **high-level shape** — major components/services or major process steps and how they connect — matching the "business-first" writing-depth rule. A box-per-major-component/step, arrows for the flow direction, one or two words per box. Do not try to cram implementation detail (field names, function names, retry logic) into the diagram itself — that belongs in the Appendix as a more detailed sub-diagram or a written step list if needed.
3. **Genuinely no diagram-worthy structure exists** (rare — e.g. documenting a single isolated function with no multi-step flow) → say so in one sentence instead of forcing a diagram: `<p>This service has a single-step flow with no meaningful architecture diagram to draw; see the Summary above.</p>`. Do not fabricate boxes and arrows just to fill the section.

### Info / note panels (optional, for callouts)

```html
<div data-type="panel" data-panel-type="info"><div data-type="panel-content"><p>Callout text.</p></div></div>
```
Panel types: `info`, `note`, `success`, `warning`, `error`.

### Code blocks (for Appendix payloads, curl, field keys)

```html
<pre><code class="language-json">{ "id": "<app_id>", "data": { "boat_year": 2016 } }</code></pre>
```
Use `language-bash` for curl, `language-text` for plain text or box diagrams.

### Lists

```html
<ul><li>Bullet item</li></ul>
<ol><li>Numbered item</li></ol>
```

### Tables

```html
<table>
  <tbody>
    <tr><th>Ticket</th><th>Description</th></tr>
    <tr><td>TRIDENT-969</td><td>Capture the BDP link…</td></tr>
  </tbody>
</table>
```

## Full skeleton (assemble in this order)

```html
<div data-type="extension" data-extension-key="toc" data-extension-type="com.atlassian.confluence.macro.core"></div>

<h2>Summary</h2>
<p>Short, concise summary of the service or process — a paragraph or two.</p>

<!-- title this <h2> "Architecture Diagram" OR "Process Flow" — pick one per the decision table above, never both -->
<h2>Process Flow</h2>
<pre><code class="language-text">
┌─────────┐    ┌─────────┐    ┌─────────┐
│  Step A  │──▶│  Step B  │──▶│  Step C  │
└─────────┘    └─────────┘    └─────────┘
</code></pre>

<!-- caller's body sections, one <h2> each, high-level writing -->
<h2>First Custom Section</h2>
<p>…</p>
<h2>Second Custom Section</h2>
<p>…</p>

<!-- default trailing section — only Appendix, unlike create-spike-document -->
<h2>Appendix</h2>
<h3>Appendix A — …</h3>
<pre><code class="language-json">…</code></pre>
```

## Verification checklist after writing

- Table of Contents is the **first** element in the body and lists every section.
- Summary comes immediately after the ToC, then the diagram section — in that order, before any caller section.
- The diagram section's `<h2>` reads exactly "Architecture Diagram" or exactly "Process Flow" — never the compound "Architecture Diagram or Process Flow", and the choice actually matches what the diagram shows (a component map vs. a step sequence).
- The diagram section actually contains a diagram (image or box/arrow text art), not just a paragraph describing one — unless the "genuinely no diagram-worthy structure" exception applies.
- No `#`, `|`, `**`, or raw HTML tags appear as literal on-page text (that means markdown mode leaked — re-do with `contentFormat: "html"`).
- All caller sections present and in order; the page ends with a single Appendix section — no Out of Scope, Jira Tickets, Effort Size, or Dependencies sections (those are `create-spike-document`'s trailing sections, not this skill's).
