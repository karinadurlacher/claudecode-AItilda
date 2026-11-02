---
name: evidence-audit
description: Independent verification of every paper in the literature review project. Checks each source record's DOI, PMID, URLs, bibliographic metadata and retraction/correction status against doi.org, Crossref and PubMed, then checks that the evidence table and the report citations match the records and that every number in the report exists in the sources. Use before screening, before writing, before export, or whenever the user asks to verify, audit, or QC the papers, links, DOIs or citations.
allowed-tools: Read, Grep, Glob, Write, PowerShell
---

# Evidence audit

Independent QC for the literature review project. It does not search, screen, extract, or write. It checks what the other agents produced and reports pass/fail. Run it from the project root (the folder that holds `CLAUDE.md`).

## When to run
| Moment | Scope | Purpose |
|---|---|---|
| After the literature-scout (QC1) | All records | Records are real, identifiers resolve, metadata matches |
| After the evidence-reviewer (QC2) | All records | Evidence-table rows map to included, verified records |
| After the research-writer (QC3) | All records | References, in-text citations and numbers trace to the sources |
| Before export | All records | Last gate; any FAIL blocks `scripts/export.ps1` |

## Step 1: Run the checks
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify-sources.ps1
```
Options: `-Scope Included` (included records only), `-SkipNetwork` (offline consistency checks only), `-OutFile <path>`. It writes `outputs/audit-report.md` and exits with code 1 if any check FAILS. It makes read-only GET requests to doi.org, Crossref, NCBI E-utilities, and any non-DOI, non-PubMed source URL. A run over about 50 records takes a few minutes.

What it checks per record:
- Required fields: title, authors, journal, year, DOI or PMID, source URL.
- DOI: valid format, resolves at doi.org, Crossref title / year / journal match, Crossref update notices (erratum, correction, retraction).
- PMID: exists in PubMed, title / first author / year / journal match, PubMed lists the same DOI, PubMed publication types for retraction or correction.
- URLs: the PubMed URL has the record's PMID, the doi.org URL has the record's DOI, other URLs are reachable.
- Text damage: corrupted characters (mojibake) in the record.

Project-wide:
- Every evidence-table row has an `included`, `verified` record, with the same DOI and PMID, and every included record has a row.
- Every reference in the report maps to an included record: same DOI, title, journal, year, first author, with a link.
- Every PMID cited in the text is in References, and every reference is cited.
- Numeric trace: every number in the report body (percentages, decimals, thousands) must appear in the evidence table or a record.

## Step 2: Read the audit report and judge each item yourself
The script only finds mismatches. For each FAIL and WARN decide what it means:

| Finding | Meaning | Action |
|---|---|---|
| DOI does not resolve, PMID not in PubMed, DOI differs between record and PubMed | Possible wrong or invented identifier | Mark the record `unverified`, remove it from the table and report, send it to the scout to re-retrieve. Never correct an identifier from memory. |
| Title / first author mismatch | Wrong paper, or encoding damage | Open the PubMed record, decide which, and send back to the scout |
| Year differs between Crossref and PubMed | Usually online-first vs print year | Acceptable if the record year matches PubMed; say so in the summary |
| Crossref or PubMed notice (erratum, correction) | Published numbers may have changed | Read the notice; if it changes extracted values, send back to the reviewer. A retraction means exclude the study. |
| Journal mismatch | Usually naming variants or preprints | Check by hand; preprints are not eligible |
| URL HTTP 403 / 429 / timeout | Often a publisher blocking automated requests | Re-run later or open once by hand; not a pass until resolved |
| Reference or table mismatch with record | Report drifted from the sources | Send to the research-writer or evidence-reviewer with the exact lines |
| Number not found in sources | Possible fabricated or mistyped number | Find it in the cited study's row or record; if it is not there, send back to the writer |
| Mojibake in a record | Extracted numbers may be damaged | Compare with the PubMed abstract before trusting any value from that record |

Do not "fix" content during the audit except to mark a record `unverified` or record a user ruling. Send each problem back to the owner with the record id and the exact finding.

## Step 3: Manual checks the script cannot do
1. **Claim trace.** For every study-specific sentence in the report, find the evidence-table cell that supports it and check that the wording does not claim more than the cell says (association vs cause, abstract-only evidence labelled, direction of effect).
2. **Table vs paper.** For each included study, open the PubMed record (or full text if the record used it) and confirm that the key numbers in the table match the source.
3. **Abstract-only labelling.** Studies read from abstracts only are labelled in the table, appraisal, and report.
4. **Reference reading.** Read the References list once as a whole: no duplicates, no study that was excluded, nothing the table does not contain.

## Step 4: Report to the user
Write a short summary in the user's language (Hebrew if they write Hebrew):
- Counts: records audited, FAIL, WARN, PASS
- Each FAIL, with the record id and what is wrong
- Warnings you resolved by hand, and how
- Manual checks done and what they found
- Verdict: **PASS** (no FAIL, every WARN resolved or explained), or **BLOCKED** with what must be fixed before export

Never state a paper, DOI, URL, number, or citation is valid unless the script or your own retrieval showed it.
