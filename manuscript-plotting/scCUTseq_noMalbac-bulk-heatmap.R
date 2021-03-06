## Author: Luuk Harbers
## Date: 2020-10-28
## Script for plotting BICRO243 HQ heatmap

## Load/install packages
packages = c("data.table", "ggplot2", "matrixStats")
sapply(packages, require, character.only = T)
source("/mnt/AchTeraD/Documents/R-functions/save_and_plot.R")

base_path = "/mnt/AchTeraD/data/BICRO217/NZ28/"
bulk = "/mnt/AchTeraD/data/BICRO188/XZ244/"

rda = list.files(base_path, pattern = ".Rda", recursive = T, full.names = T)
rda = c(rda, list.files(bulk, pattern = ".Rda", recursive = T, full.names = T))
rds = list.files(base_path, pattern = ".Rds", recursive = T, full.names = T)
rds = c(rds, list.files(bulk, pattern = ".Rds", recursive = T, full.names = T))


data = lapply(1:length(rda), function(lib) {
  load(rda[lib])
  stats = readRDS(rds[lib])
  stats = stats$stats[[1]]
  setDT(stats)
  return(list(data.table(psoptim), stats))
})

# Set thresholds
min_reads = 3e5
max_spikiness = 0.5
min_avgreads = 50

total = lapply(1:length(data), function(lib) {
  # Get usable cells and filter dt
  usable_cells = data[[lib]][[2]][reads > min_reads & spikiness < max_spikiness & mean > min_avgreads, cell]
  dt = data[[lib]][[1]][, usable_cells, with = F]

  # return dt
  return(dt)
})
total = do.call(cbind, total)

# Remove placeholder
total = total[, !grepl("placeholder", colnames(total)), with = F]
setnames(total, c(paste0("cell_", 1:(ncol(total)-1)), "Bulk"))

# Prepare for plotting heatmap
stats = readRDS(rds[1])
bins = stats$binbed[[1]]
setDT(bins)

# Get cumulative locations
bins[, bin := seq_along(chr)]
bins[, end_cum := cumsum((end - start) + 1)]
bins[, start_cum := c(1, end_cum[1:length(end_cum)-1] + 1)]

# Make chr_bounds
chr_bounds = bins[, list(min = min(bin), max = max(bin), chrlen_bp = sum(end-start)), by = chr]
chr_bounds = chr_bounds %>% 
  mutate(mid = round(min + (max-min) / 2,0),
         end_bp=cumsum(as.numeric(chrlen_bp)), 
         start_bp = end_bp - chrlen_bp, 
         mid_bp = round((chrlen_bp / 2) + start_bp, 0))

#Colors
colors = c("#496bab", "#9fbdd7", "#c1c1c1", "#e9c47e", "#d6804f", "#b3402e",
           "#821010", "#6a0936", "#ab1964", "#b6519f", "#ad80b9", "#c2a9d1")
names(colors) = c(as.character(0:10), "10+")

# Combine dt with bins
dt = data.table(cbind(bins, total))

hc = hclust(dist(t(dt[, 7:ncol(dt)])), method = "average")
dhc = as.dendrogram(hc)

# Rectangular lines
ddata = dendro_data(dhc, type = "rectangle")

# Plot Dendrogram
dendro = ggplot(ggdendro::segment(ddata)) + 
  geom_segment(aes(x = x, y = y, xend = xend, yend = yend)) +
  coord_flip() + 
  scale_y_reverse(expand = c(0, 0)) +
  scale_x_continuous(expand = c(0.016, 0.016)) +
  theme_dendro()

# Prepare for heatmap
dt_melt = melt(dt, id.vars = c("chr", "start", "end", "bin", "start_cum", "end_cum"))
dt_melt[, value := factor(value)]
dt_melt[as.numeric(value) > 10, value := "10+"]
dt_melt[, value := factor(value, levels = c(as.character(0:10), "10+"))]

# Set sample order
dt_melt[, variable := factor(variable, levels = ddata$labels$label)]

# Plot heatmap 20K+
heatmap = ggplot(dt_melt) +
  geom_linerange(aes(ymin = start_cum, ymax = end_cum, x = variable, color = value), size = 5) +
  coord_flip() +
  scale_color_manual(values = colors, drop = F) +
  labs(color = "Copy Number") + 
  scale_y_continuous(expand = c(0, 0), labels = chr_bounds$chr, breaks = chr_bounds$mid_bp) + 
  geom_hline(data = chr_bounds, aes(yintercept = end_bp), linetype = 1, size = .8) +
  theme(axis.ticks.y = element_blank(),
        axis.ticks.x = element_blank(),
        axis.title = element_blank())

# Combine plots and save
combined = plot_grid(dendro, heatmap,  align = "h", rel_widths = c(.3, 2), ncol = 2)
save_and_plot(combined, 
              "/mnt/AchTeraD/Documents/Projects/scCUTseq/Plots/manuscript/scCUTseq-nomalbac/scCUTseq-nomalbac-bulk-heatmap",
              width = 16, height = 5)
