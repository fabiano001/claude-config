<!--
  TEMPLATE: agents-frontmatter.md
  PURPOSE : YAML frontmatter block placed at the very top of every repo's AGENTS.md
            (before the first heading, above any existing content).

  USAGE   : Copy the fenced block below verbatim, then replace every placeholder:

    {REPO_NAME}  → the short repo name used throughout the platform, e.g.
                   "terraform-module-core-irsa" or "crossplane-xrd-irsa-role"

    {DEP-N}      → short repo names of direct dependencies (repos this repo reads
                   from, configures, or publishes to).  Add or remove list items as
                   needed.  Use "none" as the sole item when there are no dependencies.

  RULES   :
    - mobius.org is ALWAYS "boatsgroup" — do not change it.
    - mobius.repo must match the GitHub repository name exactly (slug, not display).
    - Keep the fence delimiters (---) — they are required YAML front-matter markers.
    - This block is parsed by mobius-tools/scripts/lib/parse-frontmatter.sh; preserve
      the exact key names.

  SHARED vs UNIQUE:
    - `mobius.org` is SHARED (identical across all repos).
    - `mobius.repo` and `mobius.dependencies` are UNIQUE per repo.
-->

---
mobius:
  repo: {REPO_NAME}
  org: boatsgroup
  dependencies:
    - {DEP-1}
    - {DEP-2}
---
