# Replication of Mesoudi, Whiten & Dunbar (2006), Experiment 2

This repository holds my preregistered replication of Experiment 2 from Mesoudi, Whiten and Dunbar (2006), "A bias for social information in human cultural transmission," *British Journal of Psychology*, 97, 405–423 (https://doi.org/10.1348/000712605X85871). Participants pass four short paragraphs along transmission chains of four people, and asks whether social information survives retelling better than non-social information.

## Files

- `writeup/Replication Report Template.qmd`: the report, rendered to `writeup/Replication-Report-Template.pdf`
- `new_code/power/power_sim.R`: the power simulation. The report runs it live, chunk by chunk
- `new_code/scoring/`: the LLM scorer (`score.py`), its prompt (`prompt.txt`) and the 56 propositions (`propositions.csv`), frozen at the tag `llm-scorers-frozen` before any main data were collected. Later commits to `score.py` (before the `preregistration` tag) only changed what it reads and saves; the prompt and propositions are unchanged
- `new_code/coding_sheet.R`: makes the blind hand-coding sheet
- `new_code/whispers/`: the web app participants use, kept in its own repository and linked as a git submodule
- `original_paper/`: the original article
- `original_code/mesoudi_whiten_dunbar_2006/`: Mesoudi's published data, reanalysis code, propositional coding sheet and coding guide, linked as a git submodule pinned to the version the report uses. To get it, clone with `git clone --recursive`, or run `git submodule update --init` in an existing clone
- `presentation/`: slides for the final presentation
- `data/`: empty until data collection

Raw data is stored in private database.

Pre-registration (release `v1.0-prereg`): https://doi.org/10.5281/zenodo.24232620

## Rendering the report

The report needs R with tidyverse, and Quarto. From `writeup/`, run:

    quarto render "Replication Report Template.qmd"

The report loads Mesoudi's published data from his repository (https://github.com/amesoudi/mesoudi_whiten_dunbar_2006), pinned to one version, so rendering needs an internet connection.
