# The two preregistered exploratory analyses for the Mesoudi, Whiten & Dunbar
# (2006) Experiment 2 replication: whether a paragraph's position in the
# reading order affects how much of it survives, and how first-generation
# recall compares with the original's. The report runs this code live using
# the "## ---- label ----" markers, after confirmatory.R has read the scores.

## ---- reading-position ----
# which material each chain read in each position, from the app's four
# orders (whispers src/lib/materials.js). Each order is one row of a
# balanced Latin square
orders <- tibble(
  order = rep(1:4, each = 4),
  position = rep(1:4, times = 4),
  material = c("gossip", "social", "physical", "individual",
               "social", "individual", "gossip", "physical",
               "individual", "physical", "social", "gossip",
               "physical", "gossip", "individual", "social"))

# each chain's mean score for the paragraph it read in each position, across
# its four generations
by_position <- scorer_scores$Claude |>
  left_join(distinct(recalls, chain, order), by = "chain") |>
  left_join(orders, by = c("order", "material")) |>
  summarize(score = mean(score), .by = c(chain, position))

ggplot(by_position, aes(x = position, y = score)) +
  stat_summary(fun = mean, geom = "col", fill = "#C3DDF0", width = 0.6) +
  stat_summary(fun.data = mean_se, geom = "linerange", linewidth = 1, color = "grey25") +
  geom_point(color = "#1565C0", alpha = 0.6,
             position = position_jitter(width = 0.15, height = 0, seed = 1)) +
  labs(x = "Position in the reading order", y = "Propositions recalled (of 14)")

## ---- first-generation ----
# first-generation recall of each material, here and in the original
first_generation <- bind_rows(
  mutate(filter(mesoudi, generation == 1), source = "Mesoudi (2006)"),
  mutate(filter(scorer_scores$Claude, generation == 1), source = "Replication")) |>
  summarize_materials(by = "source")

ggplot(first_generation, aes(x = material, y = mean, fill = source)) +
  geom_col(position = position_dodge(width = 0.7), width = 0.65) +
  geom_linerange(aes(ymin = mean - se, ymax = mean + se), linewidth = 1,
                 color = "grey25", position = position_dodge(width = 0.7)) +
  scale_fill_manual(values = c("grey70", "#C3DDF0"), name = NULL) +
  labs(x = NULL, y = "Propositions recalled\nat generation 1 (of 14)")
