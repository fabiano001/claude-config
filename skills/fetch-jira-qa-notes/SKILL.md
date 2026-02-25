---
name: fetch-jira-qa-notes
description: Fetches QA Notes from a Jira ticket's custom field. Use when the user asks to read, fetch, or extract QA notes from a Jira ticket.
allowed-tools: mcp__atlassian__getJiraIssue, mcp__atlassian__getAccessibleAtlassianResources, mcp__atlassian__fetch
---

# Fetch Jira QA Notes

Extracts QA Notes from a Jira ticket. QA Notes are stored in a **custom field** (`customfield_10312`), not in the ticket description, comments, or Confluence.

## Steps

### 1. Get the Jira issue

Use `mcp__atlassian__getJiraIssue` with the ticket key (e.g., `TRIDENT-813`).

**Important:** The standard issue response may NOT include custom fields in the visible output. You must look for `customfield_10312` specifically.

### 2. Check for QA Notes in `customfield_10312`

The QA Notes field is `customfield_10312`. It contains content in **Atlassian Document Format (ADF)** — a nested JSON structure with paragraphs, text nodes, inline cards (links), bullet lists, etc.

If `customfield_10312` is null or empty, the ticket has no QA Notes.

### 3. Parse the ADF content

The ADF JSON structure looks like this:

```json
{
  "type": "doc",
  "content": [
    {
      "type": "paragraph",
      "content": [
        { "type": "text", "text": "Some text" },
        {
          "type": "inlineCard",
          "attrs": { "url": "https://..." }
        }
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
                { "type": "text", "text": "List item text" }
              ]
            }
          ]
        }
      ]
    }
  ]
}
```

Key node types to extract:
- `text` nodes → plain text content
- `inlineCard` nodes → URLs (in `attrs.url`)
- `bulletList` / `orderedList` → list items
- `heading` nodes → section headers
- `hardBreak` → line breaks

### 4. If `customfield_10312` is not returned in the response

The MCP tool may truncate or omit large custom fields. If this happens:

1. Use `mcp__atlassian__fetch` with the issue's ARI (Atlassian Resource Identifier) to get the full issue data
2. Or serialize the entire response to a string and search for `customfield_10312` using regex

### 5. Present the QA Notes

Format the extracted content as readable markdown:
- Preserve headings and list structure
- Convert inline card URLs to clickable links
- Group related test scenarios together
- If the user asks for `<TEST_TO_RUN>` blocks, generate them from the extracted URLs and verification items

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `customfield_10312` is null | Ticket has no QA Notes — inform the user |
| Field not in response | Try `mcp__atlassian__fetch` with the issue ARI |
| ADF content is deeply nested | Recursively walk the `content` array to extract all text and URLs |
| URLs are in `inlineCard` nodes | Extract from `attrs.url`, not from text nodes |
