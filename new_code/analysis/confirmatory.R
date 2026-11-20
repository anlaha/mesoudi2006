# The planned test for the Mesoudi, Whiten & Dunbar (2006) Experiment 2
# replication: each chain's social minus non-social difference (H1) and the
# four pairwise comparisons (H2), for both scorers, and the two figures that
# show them. The report runs this code live using the "## ---- label ----"
# markers, after data_prep.R and power_sim.R.

## ---- confirmatory-test ----
set.seed(2006) # the same flips on every render

# each material's mean score, with standard errors across chains, at each
# generation unless `by` names another column. exploratory.R uses it too
summarize_materials <- function(scores, by = "generation") {
  scores |>
    mutate(material = factor(str_to_title(material),
                             levels = c("Gossip", "Social", "Individual", "Physical"))) |>
    summarize(mean = mean(score), se = sd(score) / sqrt(n()),
              .by = c(all_of(by), material))
}

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

## ---- recall-by-gn ----
# propositions recalled from each material at each generation, in the
# original (Mesoudi's Figure 4, redrawn) next to this study with the primary
# scorer. Each material gets its own color and shape, so they stay apart
# without color too. Social materials are in color (blue, red), non-social in
# black and grey
material_colors <- c(Gossip = "#1565C0", Social = "#C62828",
                     Individual = "black", Physical = "#9E9E9E")
# nudges the four materials apart at each generation so the error bars don't overlap
dodge <- position_dodge(width = 0.15)

by_material <- bind_rows(
  mutate(mesoudi, study = "Original (10 chains)"),
  mutate(scorer_scores$Claude, study = "Replication (20 chains)")) |>
  summarize_materials(by = c("study", "generation"))

ggplot(by_material, aes(x = generation, y = mean, color = material, shape = material)) +
  geom_errorbar(aes(ymin = mean - se, ymax = mean + se), width = 0.1, position = dodge) +
  geom_line(position = dodge) +
  geom_point(size = 2, position = dodge) +
  facet_wrap(~study) +
  scale_color_manual(values = material_colors, name = "Material") +
  # filled shapes, since the default plus is hard to see
  scale_shape_manual(values = c(16, 17, 15, 18), name = "Material") +
  scale_x_continuous(breaks = 1:4, labels = paste0("G", 1:4)) +
  labs(x = "Generation", y = "Propositions recalled")

## ---- social-vs-nonsocial ----
# propositions recalled per social paragraph (gossip and social) and per
# non-social paragraph (individual and physical) at each generation, in the
# original and in this study with the primary scorer. The gap between the two
# lines is what the planned test measures
social_vs_nonsocial <- bind_rows(
  mutate(mesoudi, study = "Original (10 chains)"),
  mutate(scorer_scores$Claude, study = "Replication (20 chains)")) |>
  mutate(kind = if_else(material %in% c("gossip", "social"), "Social", "Non-social"),
         kind = factor(kind, levels = c("Social", "Non-social"))) |>
  # each chain's mean per kind at each generation, then the mean across chains
  summarize(score = mean(score), .by = c(study, chain, generation, kind)) |>
  summarize(mean = mean(score), se = sd(score) / sqrt(n()),
            .by = c(study, generation, kind))

ggplot(social_vs_nonsocial, aes(x = generation, y = mean, color = kind)) +
  geom_errorbar(aes(ymin = mean - se, ymax = mean + se), width = 0.1) +
  geom_line() +
  geom_point(size = 2) +
  facet_wrap(~study) +
  scale_color_manual(values = c(Social = "#1565C0", `Non-social` = "grey40"), name = NULL) +
  scale_x_continuous(breaks = 1:4, labels = paste0("G", 1:4)) +
  labs(x = "Generation", y = "Propositions recalled")
