## Author: Luuk Harbers
## Date: 2020-08-24
## Script for sourcing genomewide heatmap plotting of aneufinder results

## Load/install packages
packages = c("data.table", "pbapply", "RColorBrewer", "GenomicRanges", "ggdendro")
sapply(packages, require, character.only = T)
source("/mnt/AchTeraD/Documents/R-functions/save_and_plot.R")

# Functions
transCoord = function(gr) {
  cum.seqlengths = cumsum(as.numeric(seqlengths(gr)))
  cum.seqlengths.0 = c(0,cum.seqlengths[-length(cum.seqlengths)])
  names(cum.seqlengths.0) = seqlevels(gr)
  gr$start.genome = start(gr) + cum.seqlengths.0[as.character(seqnames(gr))]
  gr$end.genome = end(gr) + cum.seqlengths.0[as.character(seqnames(gr))]
  return(gr)
}

plotGenomewideHeatmap = function(files, num_threads) {
  # Make dt for clustering
  clustering_list = pblapply(files, function(cell) {
    load(cell)
    # Get name
    if(!is.null(model$segments)){
      name = gsub(".*\\/|.dedup.*", "", cell)
      dt = data.table(cn = model$bins$copy.number)
      setnames(dt, "cn", name)
      return(dt)}
  }, cl = num_threads)
  
  # Bind columns
  clustering_dt = dplyr::bind_cols(clustering_list)
  
  # Get distances and cluster for dendrogram
  hc = hclust(dist(t(clustering_dt)))
  dhc <- as.dendrogram(hc)
  
  # Rectangular lines
  ddata <- dendro_data(dhc, type = "rectangle")
  
  # Plot Dendrogram
  dend_plt = ggplot(segment(ddata)) + 
    geom_segment(aes(x = x, y = y, xend = xend, yend = yend)) +
    coord_flip() + 
    scale_y_reverse(expand = c(0, 0)) +
    scale_x_continuous(expand = c(0.008, 0.008)) +
    theme_dendro()
  
  # Make dt for plotting heatmap
  dt.list = pblapply(files, function(cell){
    load(cell)
    if(!is.null(model$segments)){
      model.seg = transCoord(model[["segments"]])
      dt = as.data.table(model.seg)
      dt[, ID := gsub(".*\\/|.dedup.*", "", cell)]
      dt
    }
  }, cl = num_threads)
  
  # Bind rows
  cn_total = dplyr::bind_rows(dt.list)
  
  # Get chromosome lines
  load(files[[1]])
  cum.seqlengths = cumsum(as.numeric(seqlengths(model[["segments"]])))
  names(cum.seqlengths) = seqlevels(model[["segments"]])
  cum.seqlengths.0 = c(0,cum.seqlengths[-length(cum.seqlengths)])
  names(cum.seqlengths.0) = seqlevels(model[["segments"]])
  label.pos = round(cum.seqlengths.0 + 0.5 * seqlengths(model[["segments"]]))
  df.chroms = data.table(y = c(0, cum.seqlengths), x = 1, xend = length(files))
  
  # Prepare for plotting
  cn_total[, state_fixed := ifelse(copy.number > 10, "> 10-somy", paste0(copy.number, "-somy"))]
  cn_total[, state_fixed := factor(state_fixed, levels = c("0-somy", "1-somy", "2-somy", "3-somy", "4-somy", "5-somy",
                                                           "6-somy", "7-somy", "8-somy", "9-somy", "10-somy", "> 10-somy"))]
  cn_total[, ID := factor(ID, levels = ddata$labels$label)] 
  
  colors = c("#043b6b", "#408ccf", "#c1c1c1", "#e9c47e", "#d6804f", "#b3402e",
             "#821010", "#6a0936", "#ab1964", "#b6519f", "#ad80b9", "#c2a9d1")
  
  # Plot heatmap
  plt_heatmap = ggplot(cn_total) + 
    geom_linerange(aes(ymin = start.genome, ymax = end.genome, x = ID, col = state_fixed), size = 5) + 
    geom_segment(data = df.chroms, aes(x = x, xend = xend, y = y, yend = y), col = 'black') +
    scale_y_continuous(breaks = label.pos, labels = names(label.pos)) + 
    # scale_color_manual(values = c(brewer.pal(5, "Set1")[4], brewer.pal(5, "Set1")[2], 
    #                               "white", brewer.pal(5, "Set1")[1], 
    #                               brewer.pal(5, "Set1")[5], brewer.pal(6, "Set1")[6])) +
    scale_color_manual(values = colors) + 
    coord_flip() +
    theme(panel.background = element_blank(),
          axis.ticks.x = element_blank(),
          axis.ticks.y = element_blank(),
          axis.line = element_blank(),
          axis.title = element_blank(),
          axis.text.y = element_text(hjust = 0, margin = margin(0, -20, 0, 0)))
  
  # Combine plots
  plt_noleg = cowplot::plot_grid(dend_plt,
                                 plt_heatmap + theme(legend.position = "none"),
                                 align = "h", rel_widths = c(0.2, 2), ncol = 2)
  
  # Get and add legend
  legend = cowplot::get_legend(
    plt_heatmap + guides(color = guide_legend(nrow = 1)) +
      theme(legend.position = "bottom",
            legend.justification = "left",
            legend.title = element_blank()))
  
  plt = cowplot::plot_grid(plt_noleg, legend, ncol = 1, rel_heights = c(1, 0.05))
  return(plt)
}