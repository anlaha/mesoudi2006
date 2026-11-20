# Replication of Mesoudi, Whiten & Dunbar (2006), Experiment 2

This repository holds a preregistered replication of Experiment 2 from Mesoudi, Whiten and Dunbar (2006), "A bias for social information in human cultural transmission," *British Journal of Psychology*, 97, 405–423 (https://doi.org/10.1348/000712605X85871). Participants pass four short paragraphs along transmission chains of four people, and asks whether social information survives retelling better than non-social information.

## File structure

```
mesoudi2006/
├── writeup/
│   ├── Replication Report Template.qmd   full replication report
│   ├── Replication-Report-Template.pdf   full rendered report
│   └── figures/                          figures render saves, in pilot/ and main/
├── new_code/
│   ├── analysis/
│   │   ├── data_prep.R           loads data, exclusion rules, sanity checks, asserts
│   │   ├── confirmatory.R        planned test (H1), the four pairs (H2), and their figures
│   │   ├── scorer_validation.R   LLM scorers checked against the hand codes
│   │   ├── exploratory.R         reading position and first-generation analyses
│   │   └── make_anon_data.R      writes anonymized files in data/
│   ├── power/
│   │   └── power_sim.R           power simulation
│   ├── scoring/
│   │   ├── score.py              LLM scorer
│   │   ├── prompt.txt            LLM scorer prompt
│   │   └── propositions.csv      the 56 propositions, 14 per paragraph
│   ├── coding_sheet.R            makes blind hand-coding sheet
│   └── whispers/                 web app (git submodule)
├── data/                         anonymized data (see Data below)
│   └── private/                  raw data, coding sheets, scorer logs (gitignored, not in the repo)
├── original_paper/               the original article (Mesoudi et al. 2006)
├── original_code/
│   └── mesoudi_whiten_dunbar_2006/   Mesoudi's published data and code (git submodule)
├── presentation/                 slides for final presentation
├── renv.lock                     exact R package versions (see Rerunning the analysis)
└── renv/, .Rprofile              renv's setup, which loads the project's packages (writeup/.Rprofile does the same for the report)
```

The report runs R files in `new_code/analysis/` and `new_code/power/` live, using their `## ---- label ----` markers.

The LLM scorer (`new_code/scoring/`) was frozen at the tag `llm-scorers-frozen` before any main data were collected. Later commits to `score.py` only changed what it reads and saves. Prompt and propositions are unchanged.

The two submodules are separate repositories. To get them, clone with `git clone --recursive`, or run `git submodule update --init` in an existing clone. Mesoudi's is pinned to the version the report uses, and includes his propositional coding sheet and coding guide.

## Data

Raw data is stored in private database. `new_code/analysis/make_anon_data.R` writes anonymized copies to `data/`, which the report reads. Prolific IDs were never stored. Row ids, session tokens, browser details and raw event logs are left out.

`responses-anon.csv` has one row per response, pilot and main study:

- `test`: TRUE for the pilot (test chains), FALSE for the main study
- `chain`: chain number, 1 to 20 in the main study (0 for someone who arrived when no slot was open)
- `generation`: position in the chain, 1 to 4. Generation 1 read the original paragraphs
- `order`: which of the four paragraph orders the chain used, from the balanced Latin square (0 with no chain)
- `status`: `passed` (accepted and passed on), `excluded` (failed an exclusion rule, rerun generation), `abandoned` (left or timed out mid-task, rerun generation), or `no_slot` (arrived when no slot was open)
- `exclude_reason`: why an excluded recall was excluded, e.g. `not_typed`, `outside_help`, `canary`, `no_final_questions`
- `flags`: why a passed recall was first held for review, e.g. `near_empty`
- `age`: self-reported age (0 if not answered)
- `gender`: self-reported gender
- `english_fluency`: self-reported English fluency (`native` or `fluent`)
- `read_ms`: time on the read screen, in milliseconds
- `recall_ms`: time spent writing the recall, in milliseconds
- `instructions_attempts`: tries needed to pass the instructions check
- `keystrokes`: keys pressed while writing the recall
- `large_insertions`: number of single insertions over 20 characters, such as a paste
- `outside_help`: answer to the honesty item about outside help (`Yes` or `No`)
- `instructed_passed`: TRUE if the participant passed the instructed-response item
- `input_text`: the text the participant read
- `recall_raw`: the recall exactly as typed, which is what gets scored
- `recall_passed`: the recall passed to the next generation, with spacing corrected

The other files link recalls to hand codes and scores, each once for the pilot (`_pilot`) and once for the main study (`_study`):

- `coding_key_*-anon.csv`: each hand-coded recall's code (R01, R02, ...) with its chain and generation. The pilot hand coded every recall, the main study a random third of the chains
- `coded_*-anon.xlsx`: hand codes. The `rubric` tab lists the propositions; each other tab is one coder, one row per recall, 1 if a proposition is present
- `llm_scores_*_claude-anon.csv` and `llm_scores_study_gemma-anon.csv`: each frozen scorer's score for each recall and paragraph (`material`), out of 14. Main-study recalls are named by chain and generation, e.g. C03G2

Pre-registration (release `v1.0-prereg`): https://doi.org/10.5281/zenodo.24232620

## Rerunning the analysis

Requires R (4.6) and Quarto. Must be connected to internet.

1. Clone with the submodules: `git clone --recursive https://github.com/kyaneos/mesoudi2006.git`
2. Open R in the repo's top folder and run `renv::restore()`. This installs the exact package versions in `renv.lock` into a library just for this project
3. From `writeup/`, render the report:

        quarto render "Replication Report Template.qmd"

The LLM scores are already in `data/`. Rerunning the scorer itself (`new_code/scoring/score.py`) needs the private raw data and an Anthropic API key, which you likely do not have if you are reading this!

The report reads the anonymized data in `data/`, and loads Mesoudi's published data from his repository (https://github.com/amesoudi/mesoudi_whiten_dunbar_2006), pinned to one version. File paths are built with the `here` package, so the R files run from any folder inside the repo.

The report runs on the main study. To render the pilot instead, set `pilot <- TRUE` in the report's first code chunk. Figures are saved as `writeup/figures/<pilot or main>/fig<number>-<pilot or main>-<what it shows>.png`, numbered as in the report.
