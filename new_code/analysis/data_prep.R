# Data preparation and sanity checks for the Mesoudi, Whiten & Dunbar (2006)
# Experiment 2 replication. The report runs this code live, piece by piece,
# using the "## ---- label ----" markers, so paths are relative to writeup/.
# Chunk options (when a piece runs, figure captions) stay in the report.

## ---- import-data ----
# The raw data live in the whispers PocketBase on sciminds.cloud (lab
# login needed). `npm run export` in whispers saves every row to this file
export_path <- "../new_code/whispers/exports/whispers_responses.json"
# exports/ is gitignored, so a fresh clone has no export file at all
responses <- if (file.exists(export_path)) {
  jsonlite::read_json(export_path, simplifyVector = TRUE)
} else {
  list()
}
# the export is missing or empty before the pilot, which skips the data
# chunks below
has_data <- length(responses) > 0

# TRUE: the pilot (test chains). FALSE: the real study
pilot <- TRUE
if (has_data) responses <- filter(responses, test == pilot)

# the hand codes: the coding Google Sheet downloaded as an .xlsx
# (File > Download > Microsoft Excel) into the same gitignored folder, and
# the key from coding_sheet.R that links each recall code to its chain.
# Until the coded sheet is there, the hand-codes chunk below is skipped
exports <- "../new_code/whispers/exports/"
which_data <- if (pilot) "pilot" else "study"
coded_path <- paste0(exports, "coded_", which_data, ".xlsx")
key_path <- paste0(exports, "coding_key_", which_data, ".csv")
has_codes <- file.exists(coded_path)

# the frozen Claude scorer's scores, one row per recall and paragraph, which
# new_code/scoring/score.py saves into the same folder
scores_path <- paste0(exports, "llm_scores_", which_data, "_claude.csv")
has_scores <- has_data && file.exists(scores_path)

## ---- exclusion-rules ----
# The preregistered exclusion rules, written out as code. The app applied
# the same rules live (src/lib/server/gate.js in whispers), so this also
# checks every decision it made
canary_word <- "erstwhile"  # the word the hidden note asks an AI to use
min_typed_share <- 0.5      # at least half as many keystrokes as characters
min_words <- 10             # nearly empty: under 10 words,
min_word_share <- 0.25      #   and under a quarter of the words it read
min_overlap <- 0.15         # off topic: under 15% of its long words are in
                            #   what it read

# a text's 4+ letter words, which skips "the", "and", "was"
long_words <- function(text) {
  unique(str_extract_all(tolower(text), "[a-z]{4,}")[[1]])
}

rules <- responses |>
  filter(status %in% c("passed", "held", "excluded")) |>
  mutate(
    # clear fails: excluded, and the generation runs again
    canary = str_detect(tolower(recall_raw), canary_word),
    not_typed = lengths(keystroke_log$large_insertions) > 0 |
      keystroke_log$keystrokes < min_typed_share * nchar(recall_raw),
    said_outside_help = outside_help %in% "Yes",
    # borderline: held until the recall is read
    near_empty = str_count(recall_raw, "\\S+") < min_words &
      str_count(recall_raw, "\\S+") <
        min_word_share * str_count(input_text, "\\S+"),
    # a recall with no long words has nothing to compare: not off topic
    off_topic = coalesce(map2_dbl(recall_raw, input_text, \(recall, read)
      mean(long_words(recall) %in% long_words(read))) < min_overlap, FALSE),
    failed_instructed = !instructed_passed
  )

# how many recalls each rule caught
rules |>
  summarize(across(canary:failed_instructed, sum)) |>
  pivot_longer(everything(), names_to = "rule", values_to = "recalls") |>
  knitr::kable(format = "latex", booktabs = TRUE, centering = FALSE, caption = paste(
    "Recalls caught by each exclusion rule. Canary, not typed and outside",
    "help excluded a recall; near empty, off topic and failed instructed held",
    "it for review."))

# every recall a rule caught, with what the app decided, only if any were
caught <- rules |>
  filter(if_any(canary:failed_instructed)) |>
  select(chain, generation, status, canary:failed_instructed)
if (nrow(caught) > 0) knitr::kable(caught)

## ---- exclusions ----
# what happened to each recall, in one table. Every exclusion was decided
# before the next generation read the recall: canary and not_typed at
# submit, outside_help after the final questions, and review for a held
# recall (near_empty, off_topic, instructed_response) excluded after
# reading it
responses |>
  mutate(outcome = case_when(
    status == "excluded" ~ paste("excluded:", exclude_reason),
    status == "passed" & lengths(flags) > 0 ~
      paste("passed after review:", map_chr(flags, \(f) paste(f, collapse = ", "))),
    status == "abandoned" ~ "left or timed out",
    .default = status
  )) |>
  count(outcome, name = "recalls") |>
  knitr::kable(format = "latex", booktabs = TRUE, centering = FALSE, caption = paste(
    "What happened to each recall. Excluded recalls and those whose",
    "participant left were rerun with a new participant."))

# only accepted recalls go on to scoring
recalls <- filter(responses, status == "passed")

## ---- reading-times ----
# seconds each accepted participant spent writing their recall: the
# median, the fastest and the slowest. Reading time is in the reading speed
# plot below
recalls |>
  summarize(median = median(recall_ms) / 1000,
            min = min(recall_ms) / 1000,
            max = max(recall_ms) / 1000) |>
  knitr::kable(format = "latex", booktabs = TRUE, centering = FALSE, digits = 1, caption =
    "Seconds each participant spent writing their recall.")

## ---- words-per-generation ----
# recall length in words across generations, one line per chain, to check
# that each chain shrinks the story. The originals are generation 0
recall_lengths <- recalls |>
  mutate(words = str_count(recall_raw, "\\S+")) |>
  select(chain, generation, words)

originals <- recalls |>
  filter(generation == 1) |>
  mutate(generation = 0, words = str_count(input_text, "\\S+")) |>
  select(chain, generation, words)

chain_lengths <- bind_rows(originals, recall_lengths)

# one shade of blue per chain, from light to dark, however many chains
chain_blues <- colorRampPalette(c("#58A6D6", "#0B1F45"))(n_distinct(chain_lengths$chain))

ggplot(chain_lengths, aes(x = generation, y = words, color = factor(chain))) +
  geom_line() +
  geom_point() +
  scale_color_manual(values = chain_blues, guide = "none") +
  labs(x = "Generation (0 = original)", y = "Recall length (words)")

## ---- reading-pace ----
# each person's reading speed, to check that people actually read. The
# dashed line is the read screen's minimum time, and the band and solid line
# are where most adults and the average adult read (Brysbaert, 2019)
reading <- recalls |>
  mutate(words_read = str_count(input_text, "\\S+"),
         wpm = words_read / (read_ms / 60000)) |>
  select(chain, generation, words_read, wpm)

app_floor <- 400                  # the fastest the read screen allows
typical_rate <- 238               # average adult silent reading
typical_range <- c(175, 300)      # where most adults fall

# the reference lines and band, as tables so they get a key
rates <- tibble(rate = c(typical_rate, app_floor),
                line = c("Typical (238 wpm)", "App floor (400 wpm)"))
band <- tibble(ymin = typical_range[1], ymax = typical_range[2],
               what = "Most adults\n(175-300 wpm)")

ggplot(reading, aes(x = generation, y = wpm)) +
  geom_rect(data = band, aes(xmin = -Inf, xmax = Inf, ymin = ymin, ymax = ymax,
                             fill = what), inherit.aes = FALSE) +
  geom_hline(data = rates, aes(yintercept = rate, linetype = line),
             color = "grey50") +
  # a fixed seed so the dots land in the same place every render
  geom_point(position = position_jitter(width = 0.1, height = 0, seed = 1),
             color = "#2A7CBE") +
  scale_fill_manual(values = "#E1EFF8", name = NULL) +
  scale_linetype_manual(values = c("dashed", "solid"), name = NULL) +
  labs(x = "Generation", y = "Reading speed (wpm)") +
  # the line key and the band key stacked with no gap, as one key
  guides(linetype = guide_legend(order = 1), fill = guide_legend(order = 2)) +
  theme(legend.spacing.y = unit(0, "pt"), legend.margin = margin(0, 0, 0, 0))

## ---- complete-chains ----
# only chains with all four generations accepted are analyzed. The app
# allows one accepted recall per chain and generation, so four rows
# means all four
complete <- count(recalls, chain) |> filter(n == 4)
recalls <- filter(recalls, chain %in% complete$chain)

## ---- asserts ----
# rules the prepared data must follow. If one breaks, the render stops
library(assertthat)

assert_that(all(responses$test == pilot),
            msg = "the data mix test rows and real rows")

generations <- recalls |>
  summarize(gens = paste(sort(generation), collapse = ""), .by = chain)
assert_that(all(generations$gens == "1234"),
            msg = "a complete chain doesn't have exactly generations 1 to 4")

# each recall next to the one its chain passed on just before it
handoffs <- recalls |>
  arrange(chain, generation) |>
  mutate(passed_on = lag(recall_passed), .by = chain) |>
  filter(generation > 1)
assert_that(all(handoffs$input_text == handoffs$passed_on),
            msg = "a generation didn't read what the one before it passed on")

## ---- hand-codes ----
# the rubric tab turns each column header back into its material. The
# material is only written on each block's first row, so it's filled down
rubric <- readxl::read_excel(coded_path, "rubric") |> fill(material)
key <- read_csv(key_path, show_col_types = FALSE)

# every tab except the rubric is one coder: one row per recall, one column
# per proposition, 1 if present and blank if not
coders <- setdiff(readxl::excel_sheets(coded_path), "rubric")
hand_codes <- map(coders, \(coder) {
  mutate(readxl::read_excel(coded_path, coder), coder = coder)
}) |>
  list_rbind()

# each coder's score per recall and paragraph: how many of its 14
# propositions were marked present, with the recall's chain and generation
hand_scores <- hand_codes |>
  pivot_longer(any_of(rubric$point),
               names_to = "point", values_to = "present") |>
  left_join(select(rubric, point, material), by = "point") |>
  summarize(score = sum(present == 1, na.rm = TRUE),
            .by = c(coder, recall, material)) |>
  # skip tabs nobody has coded yet, since blank cells would count as zeros
  filter(sum(score) > 0, .by = coder) |>
  left_join(select(key, recall, chain, generation), by = "recall")
