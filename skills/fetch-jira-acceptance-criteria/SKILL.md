---
name: fetch-jira-acceptance-criteria
description: Fetches Acceptance Criteria from a Jira ticket's custom field. Use when the user asks to read, fetch, or extract acceptance criteria from a Jira ticket.
allowed-tools: mcp__atlassian__getJiraIssue, mcp__atlassian__getAccessibleAtlassianResources, mcp__atlassian__fetch
---

# Fetch Jira Acceptance Criteria

Extracts Acceptance Criteria from a Jira ticket. Acceptance Criteria are stored in a **custom field** (`customfield_10115`), not in the ticket description, comments, or Confluence.

## Steps

### 1. Get the Jira issue

Use `mcp__atlassian__getJiraIssue` with:
- `cloudId`: `ba2e3477-a4e5-4924-a530-47c471494d0f` (boats-group)
- `issueIdOrKey`: the ticket key (e.g., `TRIDENT-813`)
- `fields`: `["customfield_10115"]`

**Important:** The standard issue response does NOT include this custom field unless you explicitly request it in the `fields` parameter. You must ask for `customfield_10115` specifically.

### 2. Check for Acceptance Criteria in `customfield_10115`

The Acceptance Criteria field is `customfield_10115`. It contains content in **Atlassian Document Format (ADF)** — a nested JSON structure with a `panelType: "success"` (green panel) containing paragraphs, text nodes, inline cards (links), bullet lists, etc.

If `customfield_10115` is null or empty, the ticket has no Acceptance Criteria.

### 3. Parse the ADF content

The ADF JSON structure looks like this:

```json
{
  "type": "doc",
  "version": 1,
  "content": [
    {
      "type": "panel",
      "content": [
        {
          "type": "paragraph",
          "content": [
            { "type": "text", "text": "ACCEPTANCE CRITERIA", "marks": [{ "type": "strong" }] }
          ]
        },
        {
          "type": "bulletList",
          "content": [
            {
              "type": "listItem",
              "content": [
                {
                  "type": "paragraph",
                  "content": [
                    { "type": "text", "text": "Some criterion text" },
                    { "type": "text", "text": "code reference", "marks": [{ "type": "code" }] }
                  ]
                }
              ]
            }
          ]
        }
      ],
      "attrs": { "panelType": "success" }
    }
  ]
}
```

Key node types to extract:
- `text` nodes → plain text content
- `text` nodes with `marks: [{ "type": "code" }]` → inline code (wrap in backticks)
- `text` nodes with `marks: [{ "type": "strong" }]` → bold text
- `inlineCard` nodes → URLs (in `attrs.url`)
- `bulletList` / `orderedList` → list items
- `heading` nodes → section headers
- `hardBreak` → line breaks

### 4. If `customfield_10115` is not returned in the response

The MCP tool may truncate or omit large custom fields. If this happens:

1. Use `mcp__atlassian__fetch` with the issue's ARI: `ari:cloud:jira:ba2e3477-a4e5-4924-a530-47c471494d0f:issue/{issueId}`
2. Note: the `fetch` tool returns a text summary that may not include custom fields — prefer the `getJiraIssue` approach with explicit `fields` parameter

### 5. Present the Acceptance Criteria

Format the extracted content as readable markdown:
- Skip the "ACCEPTANCE CRITERIA" heading (it's just a panel title)
- Render each bullet item as a markdown bullet
- Preserve inline code formatting with backticks
- Preserve bold formatting
- Convert inline card URLs to clickable links

## Related Custom Fields

For reference, this project's Jira custom fields:
| Field | Custom Field ID | Panel Type |
|-------|----------------|------------|
| Acceptance Criteria | `customfield_10115` | `success` (green) |
| QA Notes | `customfield_10312` | `info` (blue) |
| Deployment Notes | `customfield_10313` | `info` (blue) |
| Rollback Steps | `customfield_10314` | `info` (blue) |

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `customfield_10115` is null | Ticket has no Acceptance Criteria — inform the user |
| Field not in response | Ensure you passed `fields: ["customfield_10115"]` in the request |
| ADF content is deeply nested | Recursively walk the `content` array to extract all text and URLs |
| URLs are in `inlineCard` nodes | Extract from `attrs.url`, not from text nodes |
| Code references in text | Look for `marks: [{ "type": "code" }]` on text nodes and wrap in backticks |
