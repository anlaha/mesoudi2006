# Writes the anonymized data files in data/ that the report reads, so anyone
# with the repo can rerun the analysis. Run it with Rscript, after
# `npm run export -- ../../data/private/whispers_responses.json` in whispers
# has saved the raw rows from PocketBase to the gitignored data/private/.
# Prolific IDs are never stored, so nothing here identifies a participant. Row ids, session tokens, browser details and
# the raw event logs are left out.
library(tidyverse)

# here() builds each path from the repo's top folder
private <- here::here("data", "private")
data_dir <- here::here("data")

# one row per response: pilot (test) and main study rows, every status
responses <- jsonlite::read_json(file.path(private, "whispers_responses.json"),
                                 simplifyVector = TRUE)
responses |>
  mutate(
    # the typing log, kept only as the two counts the exclusion rules use
    keystrokes = keystroke_log$keystrokes,
    large_insertions = lengths(keystroke_log$large_insertions),
    # why a recall was held for review, if it was, e.g. "near_empty"
    flags = map_chr(flags, \(f) paste(f, collapse = ";"))
  ) |>
  select(test, chain, generation, order, status, exclude_reason, flags,
         age, gender, english_fluency, read_ms, recall_ms,
         instructions_attempts, keystrokes, large_insertions, outside_help,
         instructed_passed, input_text, recall_raw, recall_passed) |>
  arrange(desc(test), chain, generation) |>
  write_csv(file.path(data_dir, "responses-anon.csv"))

# the coding key (recall code to chain and generation, without the row id),
# the hand codes and both frozen scorers' scores, for whichever of the pilot
# and the study exist yet
for (which_data in c("pilot", "study")) {
  key_file <- file.path(private, paste0("coding_key_", which_data, ".csv"))
  if (file.exists(key_file)) {
    read_csv(key_file, show_col_types = FALSE) |>
      select(recall, chain, generation) |>
      write_csv(file.path(data_dir, paste0("coding_key_", which_data, "-anon.csv")))
  }
  coded_file <- file.path(private, paste0("coded_", which_data, ".xlsx"))
  if (file.exists(coded_file)) {
    file.copy(coded_file, file.path(data_dir, paste0("coded_", which_data, "-anon.xlsx")),
              overwrite = TRUE)
  }
  for (scorer in c("claude", "gemma")) {
    scores_file <- file.path(private, paste0("llm_scores_", which_data, "_", scorer, ".csv"))
    if (file.exists(scores_file)) {
      file.copy(scores_file,
                file.path(data_dir, paste0("llm_scores_", which_data, "_", scorer, "-anon.csv")),
                overwrite = TRUE)
    }
  }
}
