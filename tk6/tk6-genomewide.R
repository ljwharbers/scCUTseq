## Author: Luuk Harbers
## Date: xxxx-xx-xx
## Script for analysis of TK6 - CAS9 cells

## Load/install packages
packages = c("data.table")
sapply(packages, require, character.only = T)
source("/mnt/AchTeraD/Documents/R-functions/save_and_plot.R")

# Set threads
nthreads = 32

# Select all libraries with TK6 cells (control and CAS9)
libraries = data.table(library = paste0("NZ", c(120:135, 175, 179:183)),
                       basepath = c(paste0("/media/luukharbers/HDD1/P18158_combined/NZ", 120:135, "/"),
                                    paste0("/mnt/AchTeraD/data/ngi/P19254/NZ", c(175, 179:183), "/")),
                       type = c(rep("Cas9", 16), rep("Control", 6)))


# Set thresholds
min_reads = 3e5
max_spikiness = 0.5
min_avgreads = 50
diploid = TRUE

# Loop through dirs and get copy numbers
total = pblapply(1:nrow(libraries), function(i) {
  load(paste0(libraries$basepath[i], "out/dnaobj-psoptim-500000.Rda"))
  stats = readRDS(paste0(libraries$basepath[i], "out/dnaobj-500000.Rds"))
  bins = stats$binbed[[1]]
  stats = stats$stats[[1]]
  setDT(stats)
  dt = data.table(psoptim)
  
  usable_cells = stats[reads > min_reads & spikiness < max_spikiness & mean > min_avgreads, cell]
  dt = dt[, ..usable_cells]
  
  # Select diploid only
  if(diploid) dt = dt[, apply(dt, 2, function(x) mean(x) > 1.9 & mean(x) < 2.1), with = F]
  
  # Set colnames to include library
  if(ncol(dt) > 0) setnames(dt, paste0(libraries$library[i], "_", colnames(dt)))
  
  # Return dt
  return(cbind(bins, dt))
}, cl = nthreads)

merged = Reduce(function(x, y) merge(x, y, by = c("chr", "start", "end"), all = TRUE, sort = F), total)
merged = merged[complete.cases(merged)]

# Select bins
bins = merged[, 1:3]

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
colors = c("#153570", "#577aba", "#c1c1c1", "#e3b55f", "#d6804f", "#b3402e",
           "#821010", "#6a0936", "#ab1964", "#b6519f", "#ad80b9", "#c2a9d1")
names(colors) = c(as.character(0:10), "10+")

# Make dt
dt = cbind(bins, merged[, 4:ncol(merged)])

# Distance and clustering
dist = dist(t(dt[, 7:ncol(dt)]))
hc = hclust(dist, method = "average")

# Make dendrogram
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

# Set sample and chromosome orderorder
dt_melt[, variable := factor(variable, levels = ddata$labels$label)]

# Plot heatmap
heatmap = ggplot(dt_melt) +
  geom_linerange(aes(ymin = start_cum, ymax = end_cum, x = variable, color = value), size = .3) +
  coord_flip() +
  scale_color_manual(values = colors, drop = F) +
  labs(color = "Copy Number", subtitle = paste0("n = ", ncol(dt) -7)) + 
  scale_y_continuous(expand = c(0, 0), labels = chr_bounds$chr, breaks = chr_bounds$mid_bp) + 
  geom_hline(data = chr_bounds, aes(yintercept = end_bp), linetype = 1, size = .8) +
  theme(axis.text.y = element_blank(),
        axis.ticks.y = element_blank(),
        axis.ticks.x = element_blank(),
        axis.title = element_blank())


samples = data.table(sample = colnames(dt[, 7:ncol(dt)]))
samples[, library := gsub("_.*", "", sample)]
annot = merge(samples, libraries, by = "library")
annot[, sample := factor(sample, levels = ddata$labels$label)]

annot_plt = ggplot(annot, aes(x = 1, y = sample, fill = type)) +
  geom_bar(stat = "identity",
           width = 1) +
  scale_fill_npg() +
  theme_void() +
  theme(legend.position = "left")

# Plot combined
plt = plot_grid(dendro, annot_plt, heatmap,  align = "h", rel_widths = c(.3, .1, 2), ncol = 3)

save_and_plot(plt, "/mnt/AchTeraD/Documents/Projects/scCUTseq/Plots/TK6-deletion/heatmap-ctrl+cas9",
              width = 22, height = 16)







