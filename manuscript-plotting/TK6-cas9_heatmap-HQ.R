## Author: Luuk Harbers
## Date: 2020-10-28
## Script for plotting TK6 cells deletion

## Load/install packages
packages = c("data.table", "ggplot2", "pbapply", "ggdendro")
sapply(packages, require, character.only = T)
source("/mnt/AchTeraD/Documents/R-functions/save_and_plot.R")

base_path = "/mnt/AchTeraD/data/ngi/P18158_combined/"
nthreads = 40

rda = list.files(base_path, pattern = "-250000.Rda", recursive = T, full.names = T)
rds = list.files(base_path, pattern = "-250000.Rds", recursive = T, full.names = T)
libraries = basename(list.dirs(base_path, recursive = F))
libraries = libraries[!grepl("fastq", libraries)]

# Set thresholds for HQ profiles
min_reads = 3e5
max_spikiness = 0.55
min_avgreads = 50


# Loop through libraries
data = pblapply(1:length(rda), function(lib) {
  load(rda[lib])
  stats = readRDS(rds[lib])
  stats = stats$stats[[1]]
  setDT(stats)
  dt = data.table(psoptim)
  
  usable_cells = stats[reads > min_reads & spikiness < max_spikiness & mean > min_avgreads, cell]
  dt = dt[, ..usable_cells]
  
  # Select diploid only
  if(diploid) dt = dt[, apply(dt, 2, function(x) mean(x) > 1.9 & mean(x) < 2.1), with = F]
  
  # Set colnames to include library
  if(ncol(dt) > 0) setnames(dt, paste0(libs[lib], "_", colnames(dt)))
  
  # Return dt
  return(dt)
}, cl = nthreads)

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

total = do.call(cbind, data)
dt = data.table(cbind(bins, total))

# Select diploid cells
dt = dt[, c(rep(TRUE, 6), apply(dt[, 7:ncol(dt)], 2, function(x) median(x)) == 2), with = F]

hc = hclust(dist(t(dt[, 7:ncol(dt)])), method = "average")
dhc = as.dendrogram(hc)

# Rectangular lines
ddata = dendro_data(dhc, type = "rectangle")

# Plot Dendrogram
dendro = ggplot(ggdendro::segment(ddata)) + 
  geom_segment(aes(x = x, y = y, xend = xend, yend = yend)) +
  coord_flip() + 
  scale_y_reverse(expand = c(0, 0)) +
  scale_x_continuous(expand = c(0.004, 0.004)) +
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
  ggrastr::rasterize(geom_linerange(aes(ymin = start_cum, ymax = end_cum, x = variable, color = value), size = .2),
                     dpi = 2400) +
  coord_flip() +
  scale_color_manual(values = colors, drop = F) +
  labs(color = "Copy Number") + 
  scale_y_continuous(expand = c(0, 0), labels = chr_bounds$chr, breaks = chr_bounds$mid_bp) + 
  geom_hline(data = chr_bounds, aes(yintercept = end_bp), linetype = 1, size = .8) +
  theme(axis.text.y = element_blank(),
        axis.ticks.y = element_blank(),
        axis.ticks.x = element_blank(),
        axis.title = element_blank())

# Combine plots and save
combined = plot_grid(dendro, heatmap,  align = "h", rel_widths = c(.3, 2), ncol = 2)
cairo_ps("/mnt/AchTeraD/Documents/Projects/scCUTseq/Plots/manuscript/TK6-heatmaps/250kb-HQ-TK6-ngi_only-genomewideheatmap_cairo_ps.eps", 
         onefile = TRUE, height=8, width=16, family="Helvetica", pointsize=8, antialias="none", fallback_resolution = 2400)
combined
dev.off()
