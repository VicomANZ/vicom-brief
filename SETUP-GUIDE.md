# Vicom Daily Brief — Complete Automation Setup

## System Architecture

```
┌─────────────────────────────────────────────────────────┐
│  6:00 AM AEST — ClickUp AI Agents (5 specialists)      │
│  Briefs written into: "Compiled Daily Briefs" task      │
└──────────────────────┬──────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────┐
│  7:00 AM AEST — Zapier Automation                       │
│                                                         │
│  Step 1: Schedule trigger (7AM Mon-Fri)                 │
│  Step 2: ClickUp API — Find today's compiled task       │
│  Step 3: ClickUp API — Get all attached docs            │
│  Step 4: Claude API — Structure briefs into JSON        │
│  Step 5: Code — Base64 encode JSON                      │
│  Step 6: GitHub API — Push JSON file to repo            │
│  Step 7: (Optional) Slack notification                  │
└──────────────────────┬──────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────┐
│  7:01 AM — GitHub Actions auto-updates index.json       │
│  Dashboard live at: username.github.io/vicom-brief/     │
│  Managers bookmark this URL. Works on mobile.           │
│  Navigate: Daily → Weekly → Monthly → Quarterly → Annual│
└─────────────────────────────────────────────────────────┘
```

---

## Part 1: GitHub Repository Setup

### 1.1 Create the Repository

1. Go to https://github.com/new
2. **Name:** `vicom-brief`
3. **Visibility:** Public (required for free GitHub Pages)
4. **Check:** Add a README
5. Click **Create repository**

### 1.2 Upload Files

Upload these files to the repo:

```
vicom-brief/
├── index.html                          ← Dashboard (from the build)
├── data/
│   └── (empty - Zapier will populate)
└── .github/
    └── workflows/
        ├── update-index.yml            ← Auto-generates index.json
        └── cleanup.yml                 ← Removes data >365 days old
```

**To upload via GitHub web UI:**
1. Go to your repo
2. Click "Add file" → "Upload files"
3. Upload `index.html` to root
4. Create `data/` folder by uploading any file with path `data/.gitkeep`
5. Create `.github/workflows/` and upload both yml files

### 1.3 Enable GitHub Pages

1. Go to repo **Settings** → **Pages**
2. Source: **GitHub Actions** (or Deploy from branch → main → root)
3. Your dashboard URL: `https://YOUR_USERNAME.github.io/vicom-brief/`

### 1.4 Create GitHub Personal Access Token

1. Go to https://github.com/settings/tokens?type=beta
2. Click **Generate new token** (Fine-grained)
3. **Name:** `vicom-brief-zapier`
4. **Expiration:** 90 days (set calendar reminder to rotate)
5. **Repository access:** Only select → `vicom-brief`
6. **Permissions:** Contents → Read and Write
7. **Generate** → Copy the token immediately

---

## Part 2: Zapier Zap Configuration

### Overview

Total steps: 6 (or 7 with Slack notification)
Zapier plan needed: **Free tier works** (~5 tasks per run × 22 workdays = 110/month, free tier allows 100). Starter plan if you want buffer.

---

### Step 1: TRIGGER — Schedule by Zapier

- **App:** Schedule by Zapier
- **Trigger Event:** Every Day
- **Time of Day:** 07:00
- **Timezone:** Australia/Brisbane
- **Day of Week:** Monday, Tuesday, Wednesday, Thursday, Friday

**Output:** `{{zap_meta_human_now}}` gives you today's date/time.

---

### Step 2: CODE — Format Today's Date

- **App:** Code by Zapier
- **Event:** Run JavaScript

**Input Data:**
- `raw_date` → `{{zap_meta_human_now}}`

**Code:**
```javascript
const now = new Date();
// Adjust to AEST (UTC+10)
const aest = new Date(now.getTime() + (10 * 60 * 60 * 1000));
const yyyy = aest.getFullYear();
const mm = String(aest.getMonth() + 1).padStart(2, '0');
const dd = String(aest.getDate()).padStart(2, '0');

const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
const days = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];

output = {
  date_iso: `${yyyy}-${mm}-${dd}`,
  date_label: `${days[aest.getDay()]} ${aest.getDate()} ${months[aest.getMonth()]} ${yyyy}`,
  task_name: `Compiled Daily Briefs — ${aest.getDate()} ${months[aest.getMonth()]} ${yyyy}`
};
```

**Outputs:** `date_iso`, `date_label`, `task_name`

---

### Step 3: WEBHOOKS — Search ClickUp for Today's Task

- **App:** Webhooks by Zapier
- **Event:** Custom Request

**Method:** POST
**URL:** `https://api.clickup.com/api/v3/workspaces/90161465641/search`

**Headers:**
```
Authorization: YOUR_CLICKUP_API_TOKEN
Content-Type: application/json
```

**Body:**
```json
{
  "keywords": "{{step2.task_name}}",
  "filters": {
    "asset_types": ["task"],
    "location": {
      "subcategories": ["901613701695"]
    }
  }
}
```

If the ClickUp v3 search doesn't work, use v2 alternative:

**Alternative — v2 API:**
**Method:** GET
**URL:** `https://api.clickup.com/api/v2/list/901613701695/task?statuses[]=open&include_closed=true&order_by=created&reverse=true`

Then filter results in a Code step to find today's task by name.

**Output:** Task ID (e.g., `86d24wayy`)

---

### Step 4: WEBHOOKS — Get All Docs Attached to Task

- **App:** Webhooks by Zapier
- **Event:** Custom Request

**Method:** POST
**URL:** `https://api.clickup.com/api/v3/workspaces/90161465641/search`

**Headers:**
```
Authorization: YOUR_CLICKUP_API_TOKEN
Content-Type: application/json
```

**Body:**
```json
{
  "keywords": "Daily Brief",
  "filters": {
    "asset_types": ["doc"]
  }
}
```

Then use a Code step to:
1. Filter results to only docs attached to today's task ID
2. Extract doc IDs and page IDs
3. For each doc, call the ClickUp doc pages API to get content

**Code step to get doc contents:**
```javascript
const taskId = inputData.task_id;
const apiToken = inputData.clickup_token;
const results = JSON.parse(inputData.search_results);

// Filter docs belonging to today's task
const taskDocs = results.results.filter(r =>
  r.hierarchy?.task?.id === taskId
);

// Get content for each doc
let allContent = '';
for (const doc of taskDocs) {
  const pageId = doc.pageId;
  const docId = doc.id;

  const resp = await fetch(
    `https://api.clickup.com/api/v3/workspaces/90161465641/docs/${docId}/pages/${pageId}?content_format=text/md`,
    { headers: { 'Authorization': apiToken } }
  );
  const data = await resp.json();
  allContent += '\n\n---\n\n' + (data.content || data.pages?.[0]?.content || '');
}

output = { all_briefs: allContent, doc_count: taskDocs.length };
```

**Note:** Zapier's Code step has a 1-second timeout on free, 30 seconds on paid. If you have many docs, you may need to split this into multiple webhook calls instead of a code loop.

**Alternative simpler approach:** If the ClickUp search is unreliable, use 5 separate Webhook steps to directly fetch each known doc by its pattern. The doc IDs change daily, but you can search for each agent's doc by name.

---

### Step 5: WEBHOOKS — Claude API Structures the Data

- **App:** Webhooks by Zapier
- **Event:** Custom Request

**Method:** POST
**URL:** `https://api.anthropic.com/v1/messages`

**Headers:**
```
x-api-key: YOUR_ANTHROPIC_API_KEY
anthropic-version: 2023-06-01
Content-Type: application/json
```

**Body:**
```json
{
  "model": "claude-sonnet-4-5-20250929",
  "max_tokens": 8192,
  "messages": [
    {
      "role": "user",
      "content": "Today's date is {{step2.date_iso}} ({{step2.date_label}}). Convert these 5 agent briefs into the JSON schema. Return ONLY valid JSON.\n\nBRIEFS:\n{{step4.all_briefs}}"
    }
  ],
  "system": "PASTE THE CONTENTS OF claude-api-prompt.txt HERE"
}
```

**Parse the response:**
The Claude API returns:
```json
{
  "content": [{"type": "text", "text": "{ ... the JSON ... }"}]
}
```

Extract `content[0].text` — this is your structured JSON.

---

### Step 6: CODE — Base64 Encode for GitHub

- **App:** Code by Zapier
- **Event:** Run JavaScript

**Input Data:**
- `json_content` → `{{step5.__content__0__text}}`

**Code:**
```javascript
// Clean up any markdown fences Claude might add
let json = inputData.json_content;
json = json.replace(/^```json\n?/gm, '').replace(/\n?```$/gm, '').trim();

// Validate it's valid JSON
try {
  JSON.parse(json);
} catch(e) {
  // If invalid, return error
  output = { error: 'Invalid JSON from Claude', raw: json.slice(0, 500) };
  return;
}

// Base64 encode for GitHub API
const encoded = Buffer.from(json).toString('base64');
output = { encoded: encoded, json: json, valid: 'true' };
```

---

### Step 7: WEBHOOKS — Push to GitHub

- **App:** Webhooks by Zapier
- **Event:** Custom Request

**Method:** PUT
**URL:** `https://api.github.com/repos/YOUR_USERNAME/vicom-brief/contents/data/{{step2.date_iso}}.json`

**Headers:**
```
Authorization: Bearer YOUR_GITHUB_TOKEN
Content-Type: application/json
Accept: application/vnd.github.v3+json
User-Agent: vicom-brief-zapier
```

**Body:**
```json
{
  "message": "Daily brief {{step2.date_iso}}",
  "content": "{{step6.encoded}}",
  "branch": "main"
}
```

**Important:** If the file already exists (re-run), you need the file's SHA. Add a Filter step or handle the 422 error. For first-time creation this works as-is.

---

### Step 8 (Optional): SLACK — Notify Team

- **App:** Slack
- **Event:** Send Channel Message
- **Channel:** #marketing (or your preferred channel)
- **Message:**
```
📊 *Vicom Daily Brief — {{step2.date_label}}*
Dashboard updated: https://YOUR_USERNAME.github.io/vicom-brief/
```

---

## Part 3: Testing the Flow

### Test Manually First

Before enabling the schedule:

1. **Test Step 2** — Verify date formatting works
2. **Test Step 3** — Confirm ClickUp search finds today's task
3. **Test Step 4** — Verify all 5 doc contents are retrieved
4. **Test Step 5** — Confirm Claude returns valid JSON
5. **Test Step 6** — Verify Base64 encoding
6. **Test Step 7** — Check GitHub for the new file
7. **Visit dashboard** — Confirm data renders

### Common Issues

| Issue | Solution |
|-------|----------|
| ClickUp search returns no results | Check task naming matches exactly; try v2 API fallback |
| Claude returns invalid JSON | Add retry logic or a Code step that validates and re-requests |
| GitHub 422 error | File already exists; need to include `sha` of existing file |
| Dashboard shows "No data" | Check file is at `data/YYYY-MM-DD.json`; check index.json generated |
| Date navigation doesn't work | Verify index.json contains the date; hard refresh browser |

---

## Part 4: Cost Summary

| Service | Cost | Notes |
|---------|------|-------|
| GitHub Pages | Free | Public repo required |
| GitHub Actions | Free | ~2 minutes/month of compute |
| Zapier | Free–$20/mo | Free: 100 tasks/mo (tight). Starter: 750 tasks/mo |
| Claude API (Sonnet) | ~$0.50/mo | ~$0.02 per daily brief structuring |
| **Total** | **$0–20/mo** | Free tier works if nothing else uses Zapier |

---

## Part 5: Files Included

| File | Purpose |
|------|---------|
| `index.html` | Production dashboard with all time period views |
| `claude-api-prompt.txt` | System prompt for Claude API in Zapier Step 5 |
| `.github/workflows/update-index.yml` | Auto-generates index.json when data is pushed |
| `.github/workflows/cleanup.yml` | Weekly cleanup of data >365 days |
| `data/2026-03-02.json` | Sample data file (today's brief) |

---

## Part 6: Manager Access

Share this URL with your managers:

**`https://YOUR_USERNAME.github.io/vicom-brief/`**

They can:
- Bookmark it (works on mobile)
- View any day's brief (date arrows)
- Switch between Daily / Weekly / Monthly / Quarterly / Annual views
- Interactive action checklist (daily view)
- Print any view

No login required. Updates every morning by 7:01 AM AEST.
