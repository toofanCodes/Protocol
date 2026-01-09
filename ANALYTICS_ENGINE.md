# Analytics Engine

> **Status:** Planning  
> **Created:** January 2026  
> **Goal:** Build a flexible web analytics platform for Protocol habit data

---

## Overview

A web-based analytics dashboard hosted on Firebase that reads habit data from Google Drive and provides flexible data exploration capabilities.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    iOS App (Protocol)                        │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  SyncEngine → DriveService → Upload JSON files      │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                     Google Drive                             │
│  📁 Toofan_Empire_Sync/Records/                             │
│      ├── MoleculeTemplate_xxx.json                          │
│      ├── MoleculeInstance_yyy.json                          │
│      └── AtomTemplate_zzz.json                              │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│           Web Analytics Dashboard (Firebase)                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐   │
│  │  Sync Layer  │→ │ Transform    │→ │ Analytics/Charts │   │
│  │  (Drive API) │  │ (Normalize)  │  │ (Visualization)  │   │
│  └──────────────┘  └──────────────┘  └──────────────────┘   │
│         ↓                 ↓                                  │
│  Download new/     Resolve UUIDs,       Query and render     │
│  changed files     parse dates          charts               │
└─────────────────────────────────────────────────────────────┘
```

---

## Key Components

### 1. Sync Layer

Downloads JSON files from Google Drive using incremental sync.

| Feature | Implementation |
|---------|----------------|
| Auth | Google OAuth via Firebase Auth |
| Incremental sync | Query `modifiedTime > lastSyncTime` |
| Local cache | IndexedDB in browser |
| Offline support | Serve from cache when offline |

### 2. Data Transformation Layer

Normalizes scattered JSON files into a queryable structure.

**Input (Raw files):**
```json
// MoleculeTemplate_xxx.json
{ "id": "xxx", "title": "Morning Routine", "atomTemplateIDs": ["a1", "a2"] }

// MoleculeInstance_yyy.json  
{ "id": "yyy", "parentTemplateID": "xxx", "scheduledDate": "2026-01-08", "isCompleted": true }
```

**Output (Normalized):**
```javascript
{
  templates: Map<id, { ...template, atoms: Atom[] }>,
  instances: [{ ...instance, parentTemplate: Template, date: Date }],
  byDate: Map<dateString, Instance[]>
}
```

### 3. Analytics Engine

Queries the normalized data to compute insights.

**Example queries:**
```javascript
// Completion rate last 7 days
const recentInstances = instances.filter(i => i.date > sevenDaysAgo);
const rate = recentInstances.filter(i => i.isCompleted).length / recentInstances.length;

// Best performing habit
const byTemplate = groupBy(instances, 'parentTemplateID');
const rates = Object.entries(byTemplate).map(([id, items]) => ({
  template: templates.get(id),
  rate: items.filter(i => i.isCompleted).length / items.length
}));
const best = maxBy(rates, 'rate');
```

---

## Data Flow

```
1. User opens dashboard
2. Check: Signed in with Google?
   └── No → Show sign-in button
   └── Yes → Continue
3. Check: Last sync time?
   └── Never synced → Download all files
   └── Has timestamp → Download files modified since
4. Transform: JSON files → Normalized structure
5. Cache: Store in IndexedDB
6. Render: Display charts and insights
```

---

## Tech Stack

| Layer | Technology |
|-------|------------|
| Hosting | Firebase Hosting |
| Auth | Firebase Auth (Google provider) |
| API | Google Drive API v3 |
| Cache | IndexedDB (via Dexie.js or idb) |
| Charts | Chart.js or ApexCharts |
| Framework | React, Vue, or Vanilla JS |

---

## Design Principles

1. **Flexibility** — Raw data access, not pre-computed stats
2. **Incremental** — Only sync new/changed files (like Fitbit)
3. **Offline-first** — Cache locally, work without internet
4. **Schema-tolerant** — Handle missing/new fields gracefully
5. **Privacy-focused** — Data stays in user's Drive, no server storage

---

## Implementation Phases

### Phase 1: Foundation
- [ ] Firebase project setup
- [ ] Google OAuth integration
- [ ] Basic Drive API file listing

### Phase 2: Sync Layer
- [ ] Download JSON files from Drive
- [ ] Incremental sync (modifiedTime filter)
- [ ] IndexedDB caching

### Phase 3: Transformation
- [ ] Parse and normalize JSON files
- [ ] Resolve UUID relationships
- [ ] Handle schema variations

### Phase 4: Analytics UI
- [ ] Completion rate charts
- [ ] Streak tracking
- [ ] Heatmap calendar
- [ ] Per-habit breakdown

---

## Concerns & Mitigations

| Concern | Mitigation |
|---------|------------|
| API rate limits | Batch requests, cache aggressively |
| Token expiry | Implement refresh token flow |
| Schema changes | Defensive parsing, version field |
| Large data sets | Pagination, archive old data |
| Offline access | IndexedDB cache as source of truth |

---

## LLM-Powered Natural Language Queries

### Overview

Users can ask questions in plain English, and the LLM converts them to SQL queries while selecting the most appropriate visualization.

### Architecture Flow

```
User Question → LLM (Gemini API) → { SQL, Visualization Config } → Execute → Render
```

### Example Interaction

**User:** "What was my completion rate last week?"

**LLM Response:**
```json
{
  "sql": "SELECT COUNT(*) FILTER (WHERE isCompleted) * 100.0 / COUNT(*) as rate FROM instances WHERE scheduledDate > date('now', '-7 days')",
  "visualization": {
    "type": "big_number",
    "format": "percentage",
    "title": "Completion Rate (Last 7 Days)"
  },
  "summary": "Your completion rate last week was {{rate}}%"
}
```

**Rendered:** Large "78%" with subtitle and optional trend indicator

---

### Visualization Library

The LLM selects from these platform-supported chart types based on storytelling effectiveness:

| Chart Type | Best For | Example Use Case |
|------------|----------|------------------|
| **Big Number** | Single metric | Overall completion rate, current streak |
| **Line Chart** | Trends over time | Completion rate over weeks, streak history |
| **Bar Chart** | Comparisons | Top 5 habits, daily completions by day of week |
| **Heatmap Calendar** | Daily patterns | GitHub-style contribution calendar |
| **Pie/Donut** | Proportions | Time allocation across habit categories |
| **Stacked Bar** | Multi-dimensional comparison | Completion by habit over time |
| **Table** | Detailed listings | All habits with stats, recent activity log |

---

### LLM Context Engineering

The prompt includes the **exact visualization capabilities** of the platform to guide selection:

```
Available visualizations:
1. big_number - Use for single aggregate values (e.g., "What's my streak?")
2. line - Use for time-series data showing trends
3. bar - Use for comparing discrete categories
4. heatmap - Use for daily/weekly activity patterns
5. pie - Use sparingly, only for clear proportional breakdowns
6. table - Use when user needs to see individual records

Database Schema:
- templates (id, title, recurrenceFreq, themeColorHex)
- instances (id, parentTemplateID, scheduledDate, isCompleted, notes)
- atoms (id, title, inputType, targetValue, unit)

User Question: "{{userQuestion}}"

Return JSON: { sql, visualization: { type, xAxis, yAxis, title }, summary }
```

---

### Intelligent Visualization Selection

The LLM chooses charts that **tell the story** effectively:

| User Intent | LLM Decision Logic |
|-------------|-------------------|
| "How many..." | Single number → **big_number** |
| "...over time" / "trend" | Time series → **line** |
| "Which habit..." / "compare" | Categorical comparison → **bar** |
| "Show me all..." | Many data points → **heatmap** or **table** |
| "Breakdown of..." | Proportional split → **pie** |

**Example:**
- ❌ Pie chart for "top 10 habits" (too many slices)
- ✅ Bar chart for "top 10 habits" (clear ranking)

---

### Safeguards

| Risk | Mitigation |
|------|------------|
| SQL injection | Validate LLM output against schema whitelist |
| Invalid SQL | Catch errors, send back to LLM with error context |
| Expensive queries | Set 5-second timeout, limit to 1000 rows |
| Hallucinated tables | Only allow known tables: `templates`, `instances`, `atoms` |
| Wrong viz type | Fallback to table if rendering fails |

---

### Implementation Notes

- **LLM API:** Gemini 1.5 Pro (structured JSON output)
- **SQL Engine:** sql.js (SQLite in browser)
- **Retry Logic:** If SQL fails, send error message back to LLM for correction
- **Caching:** Cache common question patterns to reduce API calls

---

## Future Enhancements

- [ ] Export/share analytics reports
- [ ] Client-side SQL queries (sql.js)
- [ ] Data encryption before upload
- [ ] Multi-device sync status
- [ ] Comparison views (this week vs last week)

---

*This document will be updated as the project evolves.*
