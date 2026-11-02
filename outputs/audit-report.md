# Audit report

Generated 2026-11-02 13:17 by scripts/verify-sources.ps1 | scope: All | network: doi.org, Crossref, NCBI E-utilities

**Result:** 0 FAIL, 13 WARN, 865 PASS across 51 records.

## Per record

| Record | Screening | Worst | FAIL | WARN |
|---|---|---|---|---|
| pmid-40712681 | included | WARN | 0 | 1 |
| pmid-40879766 | included | PASS | 0 | 0 |
| pmid-40909826 | out-of-scope | WARN | 0 | 2 |
| pmid-40929953 | excluded | PASS | 0 | 0 |
| pmid-40983149 | included | WARN | 0 | 1 |
| pmid-41058112 | out-of-scope | PASS | 0 | 0 |
| pmid-41107253 | included | PASS | 0 | 0 |
| pmid-41128391 | included | PASS | 0 | 0 |
| pmid-41173167 | excluded | PASS | 0 | 0 |
| pmid-41332541 | out-of-scope | WARN | 0 | 1 |
| pmid-41446796 | excluded | PASS | 0 | 0 |
| pmid-41655471 | included | PASS | 0 | 0 |
| pmid-41804951 | uncertain | PASS | 0 | 0 |
| pmid-41896813 | out-of-scope | PASS | 0 | 0 |
| pmid-41902630 | excluded | PASS | 0 | 0 |
| pmid-41906356 | included | PASS | 0 | 0 |
| pmid-41948089 | included | PASS | 0 | 0 |
| pmid-41976997 | included | PASS | 0 | 0 |
| pmid-42084377 | included | PASS | 0 | 0 |
| pmid-42127382 | included | PASS | 0 | 0 |
| pmid-42144137 | excluded | PASS | 0 | 0 |
| pmid-42149230 | out-of-scope | PASS | 0 | 0 |
| pmid-42168718 | out-of-scope | PASS | 0 | 0 |
| pmid-42258584 | included | PASS | 0 | 0 |
| pmid-42331561 | included | PASS | 0 | 0 |
| pmid-42392681 | included | PASS | 0 | 0 |
| pmid-42400277 | out-of-scope | PASS | 0 | 0 |
| pmid-42497408 | out-of-scope | PASS | 0 | 0 |
| pmid-42517414 | included | PASS | 0 | 0 |
| pmid-42526162 | out-of-scope | PASS | 0 | 0 |
| pmid-42528343 | included | PASS | 0 | 0 |
| pmid-42534999 | out-of-scope | PASS | 0 | 0 |
| pmid-42580811 | included | PASS | 0 | 0 |
| pmid-42595937 | included | PASS | 0 | 0 |
| pmid-42614105 | excluded | PASS | 0 | 0 |
| pmid-42625818 | out-of-scope | PASS | 0 | 0 |
| pmid-42640016 | included | PASS | 0 | 0 |
| pmid-42642740 | out-of-scope | PASS | 0 | 0 |
| pmid-42664720 | excluded | PASS | 0 | 0 |
| pmid-42675180 | included | PASS | 0 | 0 |
| pmid-42679659 | excluded | PASS | 0 | 0 |
| pmid-42747518 | uncertain | PASS | 0 | 0 |
| pmid-42790052 | included | PASS | 0 | 0 |
| pmid-42845572 | included | PASS | 0 | 0 |
| pmid-42846244 | out-of-scope | PASS | 0 | 0 |
| pmid-42863796 | included | WARN | 0 | 1 |
| pmid-42873248 | included | PASS | 0 | 0 |
| pmid-42878250 | included | PASS | 0 | 0 |
| pmid-42888153 | uncertain | PASS | 0 | 0 |
| pmid-42897516 | excluded | PASS | 0 | 0 |
| pmid-42940731 | included | PASS | 0 | 0 |

## Failures

None.

## Warnings (review by hand)

- **pmid-40712681** - year vs Crossref: record 2025 | Crossref 2026
- **pmid-40909826** - title vs Crossref: similarity 0.82; record: 'Effects of 4-Month Methylphenidate Treatment on Functional Connectivity in Attention-Deficit Hyperactivity Disorder.' | Crossref: 'Effects of 4-Month Methylphenidate Treatment on Functional Connectivity in Male Individuals with Attention-Deficit Hyperactivity Disorder'
- **pmid-40909826** - journal vs Crossref: record: 'medRxiv : the preprint server for health sciences' | Crossref: ''
- **pmid-40983149** - Crossref notices: update/correction/retraction notices: erratum (10.1016/j.bpsc.2025.12.006)
- **pmid-41332541** - journal vs Crossref: record: 'bioRxiv : the preprint server for biology' | Crossref: ''
- **pmid-42863796** - year vs Crossref: record 2026 | Crossref 2027
- **report:ref 2** - reference journal: journal 'BMJ mental health' not found in reference
- **report:ref 4** - reference journal: journal 'European child & adolescent psychiatry' not found in reference
- **report:ref 5** - reference journal: journal 'Acta psychiatrica Scandinavica' not found in reference
- **report:PMID 41173167** - record mentioned in body: record is 'excluded' and not in References; fine if listed only in the screening flow, not if used as evidence
- **report:pmid-41804951** - record mentioned in body: record id mentioned in the body but not in References (check it is not used as evidence)
- **report:pmid-42747518** - record mentioned in body: record id mentioned in the body but not in References (check it is not used as evidence)
- **report:pmid-42888153** - record mentioned in body: record id mentioned in the body but not in References (check it is not used as evidence)

## Not checked by this script

- Whether each statement in the report is supported by the cited study (the numeric trace only finds numbers absent from the sources).
- Extracted evidence and appraisal against the paper itself.
- Publisher pages that block automated requests (reported as WARN).
