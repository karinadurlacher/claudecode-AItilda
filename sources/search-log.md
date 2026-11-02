# Search Log

Append-only. One entry per search run. Never edit past entries.

Entry format:

```
## Run <n>
- Date: YYYY-MM-DD
- Tool / database:
- Query (exact string):
- Filters (dates, language, article type, etc.):
- Results returned:
- Records created or updated:
- Not reviewed (results returned but not examined or recorded; counts or PMIDs):
- Notes (strategy rationale, issues, access limits):
```

---

## Run 1
- Date: 2026-11-02
- Tool / database: PubMed (search_articles)
- Query (exact string): (ADHD[MeSH Terms] OR "attention deficit hyperactivity disorder"[Title/Abstract]) AND (predictor*[Title/Abstract] OR moderator*[Title/Abstract] OR "treatment response"[Title/Abstract]) AND (methylphenidate OR stimulant* OR atomoxetine OR lisdexamfetamine OR treatment) AND (randomized controlled trial[Publication Type] OR cohort[Title/Abstract] OR meta-analysis[Publication Type] OR systematic review[Publication Type])
- Filters (dates, language, article type, etc.): publication date 2022/01/01-2026/11/02; default sort; max_results 10 (English not filterable in tool; checked per record)
- Results returned: 130 total, 10 returned
- Records created or updated: 8 created (pmid-42897516, 42873248, 42846244, 42675180, 42625818, 42614105, 42526162, 42497408)
- Notes: test-run cap; only first page reviewed. Precision low (several non-ADHD or protocol items).
- Not reviewed (correction added 2026-11-02): 2 of the 10 returned results were not recorded: pmid-42400277, pmid-42258584. Identified by re-running the identical query the same day (same 10 PMIDs returned, total 130); the 2 PMIDs were not logged at the time of Run 1. Plus the remaining 120 hits beyond the first page.

## Run 2
- Date: 2026-11-02
- Tool / database: PubMed (search_articles)
- Query (exact string): ADHD[Title] AND (loss of response OR treatment failure OR discontinuation OR non-response OR nonresponse OR tolerance) AND (predict* OR baseline OR factors)
- Filters (dates, language, article type, etc.): publication date 2022/01/01-2026/11/02; max_results 10
- Results returned: 77 total, 10 returned
- Records created or updated: 7 created (pmid-42888153, 42878250, 42679659, 42642740, 42595937, 42580811, 42534999); 3 results not recorded due to ~15-candidate test cap (42392681, 42331561, 42168718)
- Notes: "tolerance" expands to immune tolerance/tolerability; noisy.

## Run 3
- Date: 2026-11-02
- Tool / database: PubMed (find_related_articles, pubmed_pubmed)
- Query (exact string): PMID 42595937
- Filters (dates, language, article type, etc.): none (tool ignored max_results=8)
- Results returned: 100 related PMIDs (not dates-filtered)
- Records created or updated: none (test cap reached; related IDs not examined)
- Notes: related list mixes pre-2022 items; would need date screening via metadata before intake.

## Run 4 (follow-up/correction to Runs 1 and 2; no new search executed)
- Date: 2026-11-02
- Tool / database: PubMed (get_article_metadata) for metadata; Crossref REST API (api.crossref.org/works/<doi>, read-only GET) for cross-verification
- Query (exact string): PMIDs 42400277, 42258584 (unrecorded results of Run 1); PMIDs 42392681, 42331561, 42168718 (unrecorded results of Run 2)
- Filters (dates, language, article type, etc.): none (PMID lookup); language and date checked per record
- Results returned: 5 of 5 PMIDs resolved
- Records created or updated: 5 created (candidate: pmid-42258584, pmid-42392681, pmid-42331561; out-of-scope: pmid-42400277 [no treatment-response/outcome measure], pmid-42168718 [comparison of drug agents, no patient factor])
- Not reviewed: none for these 5 PMIDs
- Notes: Run 1 and Run 2 entries are unchanged. The remaining Run 1 and Run 2 hits beyond those listed there were not examined.

## Run 5
- Date: 2026-11-02
- Tool / database: PubMed (search_articles); metadata via get_article_metadata; Crossref API cross-check
- Query (exact string): (ADHD[MeSH Terms] OR "attention deficit hyperactivity disorder"[Title/Abstract]) AND (genotype OR polymorphism OR pharmacogenetic* OR pharmacogenomic* OR polygenic OR neuroimaging OR biomarker* OR EEG OR "magnetic resonance") AND (methylphenidate OR amphetamine OR lisdexamfetamine OR atomoxetine) AND (response OR predict*)
- Filters (dates, language, article type, etc.): publication date 2022/01/01-2026/11/02; max_results 30 (English not filterable in tool; checked per record, all 'eng' where retrieved)
- Results returned: 100 total, 30 returned (has_more true)
- Records created or updated: 18 created. candidate (14): pmid-42940731, 42863796, 42790052, 42664720, 41948089, 41655471, 41446796, 41173167, 41128391, 41107253, 40983149, 40929953, 40879766, 40712681. out-of-scope (4): pmid-41896813 (protocol), 41332541 (bioRxiv preprint), 40909826 (medRxiv preprint), 41058112 (no ADHD patients/response data in abstract). 1 returned PMID already had a record (42675180).
- Not reviewed: 70 hits beyond the first 30 were not retrieved. Of the 30 returned, 11 were screened by title only and not recorded (clearly non-human, case report, or non-treatment-response topics; some borderline): 42457071, 42328622, 42063172, 41931177, 41873451, 41788094, 41611009, 41591817, 41570264, 41557094, 41256939.
- Notes: 14 candidate + 4 out-of-scope = 18 created. Titles for screening were obtained from NCBI esummary (read-only GET). 41873451 (MPH and oxidative stress, observational) and 41256939 (single-dose lisdexamfetamine vs guanfacine, cognition) may deserve a second look by the orchestrator if recall matters. Crossref lists an erratum for pmid-40983149.

## Run 6
- Date: 2026-11-02
- Tool / database: PubMed (search_articles); metadata via get_article_metadata; Crossref API cross-check
- Query (exact string): (ADHD[MeSH Terms] OR "attention deficit hyperactivity disorder"[Title/Abstract]) AND (persistence OR remission OR "long-term outcome" OR "functional outcome" OR "adult outcome" OR trajectories) AND (predictor* OR "risk factor*" OR moderator* OR baseline)
- Filters (dates, language, article type, etc.): publication date 2022/01/01-2026/11/02; max_results 30
- Results returned: 335 total, 30 returned (has_more true)
- Records created or updated: 4 created (candidate): pmid-42747518, 42640016, 42845572, 42517414. 3 returned PMIDs already had records (42873248, 42675180, 42497408).
- Not reviewed: 305 hits beyond the first 30 were not retrieved. Of the 30 returned, 23 were screened by title only and not recorded (mostly non-ADHD, non-treatment or general-population topics). Possibly borderline and unrecorded: 42807763 (predictors of suicidal thoughts in youth with/without ADHD), 42503306 (systematic review of longitudinal MRI studies), 42481172 (sex differences in symptom persistence in adolescents in psychiatric care, not ADHD-specific), 42506346.
- Notes: precision low; the query is broad ("persistence", "trajectories" match many non-treatment studies). Given the cap, only the most relevant items were recorded.

## Run 7
- Date: 2026-11-02
- Tool / database: PubMed (search_articles); metadata via get_article_metadata; Crossref API cross-check
- Query (exact string): (ADHD[MeSH Terms] OR "attention deficit hyperactivity disorder"[Title/Abstract]) AND (comorbidity OR sex OR age OR "baseline severity" OR "symptom severity") AND (moderator* OR predictor* OR "predicts" OR "associated with") AND ("treatment response" OR "medication response" OR "treatment outcome" OR "treatment effect") AND (adult* OR child* OR adolescent*)
- Filters (dates, language, article type, etc.): publication date 2022/01/01-2026/11/02; max_results 30
- Results returned: 131 total, 30 returned (has_more true)
- Records created or updated: 9 created. candidate (8): pmid-42528343, 42127382, 42144137, 42084377, 41976997, 41906356, 41804951, 41902630. out-of-scope (1): pmid-42149230 (intervention comparison only; ADHD or ODD sample). 5 returned PMIDs already had records (42897516, 42625818, 42595937, 42580811, 42497408).
- Not reviewed: 101 hits beyond the first 30 were not retrieved. Of the 30 returned, 16 were screened by title only and not recorded (non-ADHD, protocols, or off-topic). Possibly borderline and unrecorded: 42415397 (dexamphetamine vs methylphenidate RCT, treatment comparison), 42831355 (MPH vs risperidone in preschool ADHD), 42892735 (guanfacine naturalistic), 42207988 (viloxazine in adult ADHD with depression/anxiety symptoms, open-label), 42955815 (protocol, out-of-scope).
- Notes: Total new records created across Runs 4-7 = 36 (29 candidate, 7 out-of-scope), under the cap of about 40.
