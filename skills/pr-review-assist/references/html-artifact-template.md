# HTML artifact skeleton (Step 4 detail)

Load this before writing the artifact file. Adapt the structure below to the specific PR's sections — don't reinvent the sync mechanics, data-embedding pattern, or theme handling from scratch each time. This skeleton is deliberately plain so it's easy to adapt; still run it past the `artifact-design` skill's guidance for actual visual polish (spacing, type, color) before publishing — this file covers *mechanics*, not final visual design.

Remember the environment's Artifact constraints this skeleton already respects: no external CDN scripts/styles/fonts (CSP blocks them), theme-aware light/dark via `prefers-color-scheme` + `data-theme` override, responsive (no horizontal page scroll — the diff pane scrolls internally instead), and Mermaid renders natively via `<pre class="mermaid">` with no library to load.

## Data-embedding pattern (no live calls)

Bake everything fetched in Step 1 and derived in Steps 2–3 into one inline JSON blob. The page's own JS reads it; nothing is fetched at runtime.

```html
<script type="application/json" id="pr-data">
{
  "prUrl": "https://github.com/OWNER/REPO/pull/123",
  "owner": "OWNER",
  "repo": "REPO",
  "number": 123,
  "title": "Add retry logic for failed uploads",
  "overallSummary": "Adds automatic retry logic for failed file uploads and surfaces the new error message across all supported locales. 18 files changed; grouped into 4 sections.",
  "sections": [
    {
      "id": "s1",
      "title": "Retry helper for failed uploads",
      "summary": "Adds a reusable helper that retries an upload a limited number of times before giving up.",
      "files": [{ "path": "src/upload/retry.ts", "startLine": 1, "endLine": 42 }],
      "diagram": null
    },
    {
      "id": "s2",
      "title": "Uploads now retry automatically on failure",
      "summary": "Wires the new retry helper into the existing upload client, so a failed upload is retried instead of failing immediately.",
      "files": [{ "path": "src/upload/uploadClient.ts", "startLine": 10, "endLine": 65 }],
      "diagram": "sequenceDiagram\n  participant U as Uploader\n  participant R as RetryHelper\n  U->>R: upload(file)\n  R-->>U: failure\n  R->>R: retry (up to N times)\n  R-->>U: success"
    }
  ],
  "files": [
    {
      "path": "src/upload/retry.ts",
      "hunks": [
        { "newStart": 1, "newEnd": 42, "lines": [
          { "type": "context", "newLine": 1, "text": "export interface RetryOptions {" },
          { "type": "add", "newLine": 2, "text": "  maxAttempts: number;" },
          { "type": "del", "oldLine": 2, "text": "  attempts: number;" }
        ]}
      ]
    }
  ]
}
</script>
```

- `sections[].files[].startLine/endLine` are **new-file line numbers**, matching what's rendered in the diff pane — this is the anchor the click-to-scroll behavior uses.
- `files[].hunks[].lines[].type` is `"add" | "del" | "context"`; `newLine` is present for `add`/`context`, `oldLine` for `del`/`context` (context lines have both). This is all the diff renderer needs — no external diff library.
- `diagram` is `null` for most sections (text-only, per the opt-in rule) — only set it when the change is genuinely a flow/sequence.

## Page structure

```html
<!doctype-equivalent handled by the Artifact wrapper — do not include <!DOCTYPE>/<html>/<head>/<body> tags yourself, per the Artifact tool's own contract -->

<header class="pr-header">
  <h1 id="pr-title"></h1>
  <a id="pr-link" href="#" target="_blank" rel="noopener"></a>
  <p id="pr-overall-summary"></p>
</header>

<main class="panes">
  <section class="diff-pane" id="diff-pane" aria-label="Diff (read-only)">
    <!-- one <div class="file-block"> per changed file, collapsible, rendered from files[] -->
  </section>

  <aside class="summary-pane" id="summary-pane" aria-label="Section summaries">
    <!-- one <article class="summary-card" data-section-id="..."> per sections[] entry -->
  </aside>
</main>
```

**The PR header is required** — render `prUrl` as a real anchor (`<a href="${data.prUrl}" target="_blank" rel="noopener">#${data.number} · ${data.owner}/${data.repo}</a>`), plus the title and overall summary, above the two panes. This is the reviewer's way back to the real PR — never omit it, and never make it a decorative non-link.

## CSS layout skeleton

```css
:root {
  --bg: #ffffff;
  --fg: #1a1a1a;
  --pane-border: #e2e2e2;
  --add-bg: #e6ffed;
  --add-fg: #22863a;
  --del-bg: #ffeef0;
  --del-fg: #cb2431;
  --card-bg: #f6f8fa;
  --card-active-bg: #dbeafe;
  --highlight-bg: #fff3b0;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #0d1117; --fg: #e6edf3; --pane-border: #30363d;
    --add-bg: #033a16; --add-fg: #3fb950;
    --del-bg: #3c0d12; --del-fg: #f85149;
    --card-bg: #161b22; --card-active-bg: #1f3a5f;
    --highlight-bg: #4d3d00;
  }
}
:root[data-theme="dark"] { /* same dark values as above, for explicit toggle */ }
:root[data-theme="light"] { /* same light values as above, for explicit toggle */ }

html, body { background: var(--bg); color: var(--fg); }
.panes { display: flex; gap: 1rem; height: calc(100vh - 8rem); }
.diff-pane { flex: 1 1 60%; overflow-y: auto; border: 1px solid var(--pane-border); font-family: ui-monospace, "SF Mono", monospace; font-size: 0.85rem; }
.summary-pane { flex: 1 1 40%; overflow-y: auto; display: flex; flex-direction: column; gap: 0.75rem; }
.diff-line.add { background: var(--add-bg); color: var(--add-fg); }
.diff-line.del { background: var(--del-bg); color: var(--del-fg); }
.diff-line.highlighted { background: var(--highlight-bg); } /* click-to-scroll target highlight, layered over add/del */
.summary-card { background: var(--card-bg); border-radius: 0.5rem; padding: 0.75rem; cursor: pointer; }
.summary-card.active { background: var(--card-active-bg); } /* currently-in-view via IntersectionObserver */
.summary-card .file-label { font-family: ui-monospace, monospace; font-size: 0.75rem; opacity: 0.7; }

/* Responsive: stack panes instead of overflowing horizontally on narrow viewports */
@media (max-width: 720px) {
  .panes { flex-direction: column; height: auto; }
  .diff-pane, .summary-pane { flex: none; max-height: 60vh; }
}
```

Swap these placeholder colors for whatever `artifact-design` recommends for a distinctive look — the important structural bits are the CSS custom properties (theme-swappable), the flex two-pane layout, and the responsive stack-on-narrow rule.

## JS: rendering + two-way sync

```html
<script>
(function () {
  const data = JSON.parse(document.getElementById('pr-data').textContent);

  // --- Header ---
  document.getElementById('pr-title').textContent = data.title;
  const link = document.getElementById('pr-link');
  link.href = data.prUrl;
  link.textContent = `#${data.number} · ${data.owner}/${data.repo}`;
  document.getElementById('pr-overall-summary').textContent = data.overallSummary;

  // --- Render diff pane (one collapsible block per file) ---
  const diffPane = document.getElementById('diff-pane');
  data.files.forEach(file => {
    const block = document.createElement('div');
    block.className = 'file-block';
    const header = document.createElement('button');
    header.className = 'file-header';
    header.textContent = file.path;
    header.setAttribute('aria-expanded', 'true');
    header.addEventListener('click', () => {
      const collapsed = block.classList.toggle('collapsed');
      header.setAttribute('aria-expanded', String(!collapsed));
    });
    block.appendChild(header);

    file.hunks.forEach(hunk => {
      hunk.lines.forEach(line => {
        const row = document.createElement('div');
        row.className = `diff-line ${line.type}`;
        row.dataset.file = file.path;
        if (line.newLine) row.dataset.newLine = line.newLine;
        row.textContent = line.text;
        block.appendChild(row);
      });
    });
    diffPane.appendChild(block);
  });

  // --- Render summary cards ---
  const summaryPane = document.getElementById('summary-pane');
  const cardsById = {};
  data.sections.forEach(section => {
    const card = document.createElement('article');
    card.className = 'summary-card';
    card.dataset.sectionId = section.id;
    card.tabIndex = 0;

    const label = document.createElement('div');
    label.className = 'file-label';
    label.textContent = section.files.map(f => `${f.path}:${f.startLine}-${f.endLine}`).join(', ');

    const title = document.createElement('h3');
    title.textContent = section.title;
    const summary = document.createElement('p');
    summary.textContent = section.summary;

    card.append(label, title, summary);

    if (section.diagram) {
      const pre = document.createElement('pre');
      pre.className = 'mermaid';
      pre.textContent = section.diagram;
      card.appendChild(pre);
    }

    card.addEventListener('click', () => scrollDiffToSection(section));
    card.addEventListener('keydown', e => { if (e.key === 'Enter' || e.key === ' ') scrollDiffToSection(section); });

    summaryPane.appendChild(card);
    cardsById[section.id] = card;
  });

  // --- Click a card -> scroll diff pane + highlight lines ---
  function scrollDiffToSection(section) {
    clearHighlights();
    const first = section.files[0];
    const target = diffPane.querySelector(
      `.diff-line[data-file="${first.path}"][data-new-line="${first.startLine}"]`
    );
    if (target) target.scrollIntoView({ behavior: 'smooth', block: 'center' });

    section.files.forEach(f => {
      diffPane.querySelectorAll(`.diff-line[data-file="${f.path}"]`).forEach(row => {
        const n = Number(row.dataset.newLine);
        if (n >= f.startLine && n <= f.endLine) row.classList.add('highlighted');
      });
    });
  }
  function clearHighlights() {
    diffPane.querySelectorAll('.diff-line.highlighted').forEach(el => el.classList.remove('highlighted'));
  }

  // --- Scroll diff pane -> highlight the in-view card ---
  // Insert one invisible marker element per section at the top of its first line,
  // then observe those markers (cheap, robust vs. observing every diff line).
  data.sections.forEach(section => {
    const first = section.files[0];
    const target = diffPane.querySelector(
      `.diff-line[data-file="${first.path}"][data-new-line="${first.startLine}"]`
    );
    if (target) target.dataset.sectionMarker = section.id;
  });

  const observer = new IntersectionObserver(entries => {
    entries.forEach(entry => {
      const id = entry.target.dataset.sectionMarker;
      if (!id) return;
      const card = cardsById[id];
      if (entry.isIntersecting) {
        Object.values(cardsById).forEach(c => c.classList.remove('active'));
        card.classList.add('active');
        card.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
      }
    });
  }, { root: diffPane, threshold: 0.1 });

  diffPane.querySelectorAll('[data-section-marker]').forEach(el => observer.observe(el));
})();
</script>
```

Notes on the skeleton above:
- No inline commenting UI, no execution of diff content, no `fetch`/`XMLHttpRequest`/`WebSocket` calls anywhere — purely rendering already-embedded data. This satisfies the "read-only, self-contained, no live calls" constraint by construction.
- The IntersectionObserver watches one lightweight marker per section (the first line of its first file range) rather than every diff line — cheaper and avoids flicker when multiple sections' lines are simultaneously visible.
- Collapsing a file block (the `file-header` click handler) is a plain class toggle — pair it with a CSS rule like `.file-block.collapsed .diff-line { display: none; }`.
- If a section's `diagram` is set, it's appended directly inside the summary card as `<pre class="mermaid">` — the Artifact runtime renders Mermaid natively, no extra script tag needed.
