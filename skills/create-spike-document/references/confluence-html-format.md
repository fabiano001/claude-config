# Confluence HTML+ format for spike documents

This is the exact, verified HTML+ format the Atlassian MCP tools accept for a spike page. It renders with full rich formatting. **Never** use `contentFormat: "markdown"` (escapes everything to literal text) and **never** use raw storage format (`<ac:layout>`, `<ac:structured-macro>`, CDATA — the API rejects these).

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

### Two-equal-column layout (Objective | Business Purpose)

Goes at the very top of the body. This is the side-by-side top section.

```html
<section data-type="layout-two-equal">
  <div data-type="column">
    <h2>Objective</h2>
    <p>Short summary of the spike objective. A few sentences at most.</p>
  </div>
  <div data-type="column">
    <h2>Business Purpose</h2>
    <p>The business value of implementing the spike's prescribed changes. Short, focused on value.</p>
  </div>
</section>
```

### Table of Contents (directly below the layout)

Auto-generates from the `<h2>`/`<h3>` headings — no manual link list needed.

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

### Info / note panels (optional, for callouts)

```html
<div data-type="panel" data-panel-type="info"><div data-type="panel-content"><p>Callout text.</p></div></div>
```
Panel types: `info`, `note`, `success`, `warning`, `error`.

### Code blocks (for Appendix payloads, curl, field keys)

```html
<pre><code class="language-json">{ "id": "<app_id>", "data": { "boat_year": 2016 } }</code></pre>
```
Use `language-bash` for curl, `language-text` for plain.

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
<section data-type="layout-two-equal">
  <div data-type="column"><h2>Objective</h2><p>…</p></div>
  <div data-type="column"><h2>Business Purpose</h2><p>…</p></div>
</section>
<div data-type="extension" data-extension-key="toc" data-extension-type="com.atlassian.confluence.macro.core"></div>

<!-- caller's body sections, one <h2> each, high-level writing -->
<h2>First Custom Section</h2>
<p>…</p>
<h2>Second Custom Section</h2>
<p>…</p>

<!-- default trailing sections, always in this order -->
<h2>Out of Scope</h2>
<ul><li>…</li></ul>
<h2>Jira Tickets</h2>
<table><tbody><tr><th>Ticket</th><th>Description</th></tr><tr><td>…</td><td>…</td></tr></tbody></table>
<h2>Effort Size</h2>
<p>…sprints / …developers.</p>
<h2>Dependencies</h2>
<ul><li>…</li></ul>
<h2>Appendix</h2>
<h3>Appendix A — …</h3>
<pre><code class="language-json">…</code></pre>
```

## Verification checklist after writing

- Objective and Business Purpose render **side-by-side**, not stacked.
- Table of Contents appears **directly below** them and lists every section.
- No `#`, `|`, `**`, or raw HTML tags appear as literal on-page text (that means markdown mode leaked — re-do with `contentFormat: "html"`).
- All caller sections present and in order; trailing defaults present in order.
