# Biomedical Literature Review Agent

AI agent for literature search- claudecode AI tilda course

A Claude Code project that searches PubMed, screens and appraises studies against explicit criteria, and writes a referenced evidence synthesis. Every paper is verified before use, and the report may contain only what is in the evidence table.

## How to run
1. Open this folder in Claude Code (a new session, so the three subagents in `.claude/agents/` load).
2. Edit `research-question.md`: question, factor/exposure, outcomes, study types, date range, language, inclusion/exclusion criteria. Set its status line to CONFIRMED.
3. Ask Claude to run the literature review. It follows `CLAUDE.md`: discovery, screening and appraisal, writing, four QC gates, export.
4. It asks you when it needs a decision (an unclear criterion, mostly abstract-only evidence, too few studies). Your rulings are written into `research-question.md` and the screening log so later runs apply them.

## What is where
| Path | Purpose |
|---|---|
| `CLAUDE.md` | Orchestrator: workflow, QC gates, anti-fabrication rules, stop conditions |
| `research-question.md` | Scope and criteria (single source of truth) |
| `.claude/agents/literature-scout.md` | Search, log, verify, create source records |
| `.claude/agents/evidence-reviewer.md` | Screen, extract, appraise, build the evidence table |
| `.claude/agents/research-writer.md` | Write the synthesis from the table only |
| `templates/paper-record-template.md` | Format of one source record |
| `sources/search-log.md` | Append-only log of every search run |
| `sources/records/` | One verified record per paper |
| `sources/screening-log.md` | Screening decisions and flow counts |
| `outputs/evidence-table.md`, `outputs/research-report.md` | Canonical working outputs |
| `outputs/*.xlsx`, `outputs/*.docx` | Final exports |
| `scripts/export.ps1` | Markdown to Word/Excel, with self-checks |
| `.claude/skills/evidence-audit/SKILL.md` | Skill: independent verification of all papers, DOIs, URLs, and citations |
| `scripts/verify-sources.ps1` | The audit script behind the skill; writes `outputs/audit-report.md` |

## Export
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\export.ps1 -QcConfirmed
```
Needs only Windows PowerShell 5.1. It refuses drafts and prints PASS/FAIL checks comparing the exported files to the markdown.

## Limits to know
- Sources are PubMed plus Crossref/OpenAlex for cross-checking. Papers outside PubMed may be missed.
- Many papers are available only as abstracts. Those are labelled, and quality cannot be fully assessed from them.
- The appraisal is an AI-assisted first pass and does not replace a human reviewer. Check the evidence table against the papers before relying on conclusions.
- Subagent definitions added during a session load only in the next session.
