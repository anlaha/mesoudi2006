# Figure 4 of Mesoudi, Whiten & Dunbar (2006), recreated from their published
# Experiment 2 data, then redrawn with error bars and the social materials in
# color. The report runs this code live using the "## ---- label ----" markers,
# after power_sim.R has loaded the data as `mesoudi`.

## ---- mesoudi-figure-4 ----
# each material's mean score at each generation, with standard errors across
# the 10 chains. Both figures below use this table
by_generation <- mesoudi |>
  mutate(material = factor(str_to_title(material),
                           levels = c("Gossip", "Social", "Individual", "Physical"))) |>
  summarize(mean = mean(score), se = sd(score) / sqrt(n()),
            .by = c(generation, material))

# the original, as a share of each paragraph's 14 propositions
ggplot(by_generation, aes(x = generation, y = mean / 14, shape = material)) +
  geom_errorbar(aes(ymin = (mean - se) / 14, ymax = (mean + se) / 14), width = 0.04) +
  geom_line() +
  geom_point() +
  scale_x_continuous(breaks = 1:4, labels = paste0("F", 1:4)) +
  scale_y_continuous(limits = c(0, 1)) +
  labs(x = "Generation", y = "Proportion of correctly\nrecalled propositions")

## ---- improved-figure-4 ----
# the same data in propositions out of 14. Each material gets its own color
# and shape, so they stay apart without color too. Social materials are in
# color (blue, red), non-social in black and grey
material_colors <- c(Gossip = "#1565C0", Social = "#C62828",
                     Individual = "black", Physical = "#9E9E9E")
# nudges the four materials apart at each generation so the error bars don't overlap
dodge <- position_dodge(width = 0.15)

ggplot(by_generation, aes(x = generation, y = mean, color = material, shape = material)) +
  geom_errorbar(aes(ymin = mean - se, ymax = mean + se), width = 0.1, position = dodge) +
  geom_line(position = dodge) +
  geom_point(size = 2, position = dodge) +
  scale_color_manual(values = material_colors, name = "Material") +
  # filled shapes, since the default plus is hard to see
  scale_shape_manual(values = c(16, 17, 15, 18), name = "Material") +
  scale_x_continuous(breaks = 1:4, labels = paste0("G", 1:4)) +
  labs(x = "Generation", y = "Propositions recalled (of 14)")
