# The preregistered checks of the two LLM scorers against the hand-coded
# third of the chains. The report runs this code live using the
# "## ---- label ----" markers, after confirmatory.R has read the scores.

## ---- scorer-validation-table ----
# each hand-coded paragraph's score from the hand codes and from each model
validation <- imap(scorer_scores, \(scores, scorer)
  inner_join(hand_scores, scores, by = c("chain", "generation", "material"),
             suffix = c("_hand", "_model")) |>
    mutate(scorer = scorer)) |>
  list_rbind()

# the preregistered bars, for when no second human coder is available
min_r <- 0.90              # paragraph scores must correlate at least this well
min_icc_lower <- 0.75      # and the ICC's lower 95% bound must reach this
max_chain_gap <- 0.5       # a hand-coded chain's difference can be off by this much

# how far each hand-coded chain's social minus non-social difference moves
# when the model scores it instead of the hand codes
chain_gap <- function(scores) {
  by_hand <- chain_difference(select(scores, chain, material, score = score_hand))
  by_model <- chain_difference(select(scores, chain, material, score = score_model))
  mean(abs(by_model$difference - by_hand$difference[match(by_model$chain, by_hand$chain)]))
}

validation |>
  summarize(
    r = cor(score_hand, score_model),
    # two-way, absolute agreement, single scores
    icc_lower = irr::icc(cbind(score_hand, score_model), model = "twoway",
                         type = "agreement", unit = "single")$lbound,
    chain_gap = chain_gap(pick(everything())),
    .by = scorer) |>
  mutate(passes = r >= min_r & icc_lower >= min_icc_lower & chain_gap <= max_chain_gap,
         passes = if_else(passes, "yes", "no")) |>
  knitr::kable(format = "latex", booktabs = TRUE, centering = FALSE, digits = 3,
               col.names = c("Scorer", "r (at least 0.90)", "ICC lower bound (at least 0.75)",
                             "Mean chain gap (at most 0.5)", "Passes"),
               caption = paste("Each scorer against the hand-coded third of the",
                               "chains, with the preregistered bars for when no",
                               "second human coder is available."))

## ---- scorer-validation ----
# the same paragraphs as a scatter. Points on the dashed line are exact agreement
ggplot(validation, aes(x = score_hand, y = score_model)) +
  geom_abline(linetype = "dashed", color = "grey50") +
  # a little jitter, since many paragraphs share the same pair of scores
  geom_point(color = "#1565C0", alpha = 0.5,
             position = position_jitter(width = 0.15, height = 0.15, seed = 1)) +
  facet_wrap(~scorer) +
  coord_equal() +
  labs(x = "Hand-coded score (of 14)", y = "Model score (of 14)")
