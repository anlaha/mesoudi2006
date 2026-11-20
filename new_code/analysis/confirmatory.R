# The planned test for the Mesoudi, Whiten & Dunbar (2006) Experiment 2
# replication: each chain's social minus non-social difference (H1) and the
# four pairwise comparisons (H2), for both scorers, and the two figures that
# show them. The report runs this code live using the "## ---- label ----"
# markers, after data_prep.R, power_sim.R and mesoudi_figure_4.R.

## ---- confirmatory-test ----
set.seed(2006) # the same flips on every render

# one scorer's scores with each recall's chain and generation, complete chains
# only. The pilot's recall codes (R01, R02, ...) are matched through the
# coding key, and the main study's codes (C03G2) say both
read_scores <- function(path) {
  scores <- read_csv(path, show_col_types = FALSE)
  scores <- if (pilot) {
    left_join(scores, read_csv(key_path, show_col_types = FALSE), by = "recall")
  } else {
    mutate(scores, chain = as.integer(substr(recall, 2, 3)),
           generation = as.integer(substr(recall, 5, 5)))
  }
  filter(scores, chain %in% complete$chain)
}

# Claude is the primary scorer and Gemma the sensitivity check
scorer_paths <- c(Claude = scores_path, Gemma = gemma_path)
scorer_scores <- map(scorer_paths[file.exists(scorer_paths)], read_scores)
# each chain's social minus non-social difference, plus the four pairs
scorers <- map(scorer_scores, chain_difference)
study_differences <- scorers$Claude

# p-values for the tables. 5,000 flips can't show a p below 1 in 5,000, so
# small ones print as < 0.001
format_p <- function(p) if_else(p < 0.001, "< 0.001", sprintf("%.3f", p))

# the planned test (H1), for each scorer
imap(scorers, \(differences, scorer) tibble(
  Scorer = scorer,
  Chains = nrow(differences),
  `Mean difference` = mean(differences$difference),
  `Chains above 0` = sum(differences$difference > 0),
  p = format_p(sign_flip_p(differences$difference)))) |>
  list_rbind() |>
  knitr::kable(format = "latex", booktabs = TRUE, centering = FALSE, digits = 3,
               caption = paste("The planned test: each chain's social minus",
                               "non-social difference, in propositions, with a",
                               "two-sided sign-flip test (5,000 flips, alpha = 0.05)."))

# the four pairwise comparisons (H2), with the primary scorer, at the
# original's Bonferroni-corrected 0.01
tibble(Pair = c("Gossip vs individual", "Gossip vs physical",
                "Social vs individual", "Social vs physical"),
       column = c("gossip_vs_individual", "gossip_vs_physical",
                  "social_vs_individual", "social_vs_physical")) |>
  mutate(`Mean difference` = map_dbl(column, \(x) mean(study_differences[[x]])),
         p = format_p(map_dbl(column, \(x) sign_flip_p(study_differences[[x]])))) |>
  select(-column) |>
  knitr::kable(format = "latex", booktabs = TRUE, centering = FALSE, digits = 3,
               caption = paste("The four pairwise comparisons with the Claude",
                               "scorer, each a sign-flip test at alpha = 0.01."))

## ---- results-by-generation ----
# the main study drawn like the improved Figure 4, with the primary scorer
plot_materials(summarize_materials(scorer_scores$Claude))

## ---- chain-differences ----
# each chain's social minus non-social difference, the number the planned test
# uses: Mesoudi's 10 chains, then this study's 20 with each scorer
chain_differences <- bind_rows(
  tibble(source = "Mesoudi (2006)", difference = real_differences),
  imap(scorers, \(differences, scorer)
    tibble(source = scorer, difference = differences$difference)) |>
    list_rbind()) |>
  mutate(source = fct_inorder(source))

ggplot(chain_differences, aes(x = source, y = difference)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "grey50") +
  # see-through points so the mean shows behind them, and a fixed seed so
  # the points land in the same place every render
  geom_point(color = "#1565C0", alpha = 0.6,
             position = position_jitter(width = 0.1, height = 0, seed = 1)) +
  stat_summary(fun.data = mean_se, geom = "pointrange", color = "grey25") +
  labs(x = NULL, y = "Social minus non-social\n(propositions)")
