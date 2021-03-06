# library(rvest)
# library("RJSONIO")
# library("TTR")
library(rgl)
library(zoom)
# library(gplots)
# library(MASS)
library(LPCM)
# library(princurve)
#source("functions.R")

path <- "tracks/"
scrap_file <- "collserola_scrap.csv"
colors <- palette()[2:length(palette())]

####### Functions #######
crop <- function(track, lonlim, latlim){
  track <- track[(track$lon<lonlim[2]) & (track$lon>lonlim[1]) & (track$lat<latlim[2]) & (track$lat>latlim[1]),]
  return(track)  
}

delta_dist <- function(track){
  delta_lat <- abs(track$lat[2:length(track$lat)]-track$lat[1:(length(track$lat)-1)])
  delta_lon <- abs(track$lon[2:length(track$lon)]-track$lon[1:(length(track$lon)-1)])
  delta_x <- sqrt(delta_lat^2 + delta_lon^2)  
  return(delta_x)
}

######## Scrap Collserola Wikiloc #########
remove("track_base")
n=1
for (i in seq(10,14457,10)){
  wikiloc <- read_html(paste0("http://es.wikiloc.com/wikiloc/find.do?act=all&q=collserola&from=", i-10,"&to=",i))
  
  track_link <- wikiloc %>% 
       html_nodes("h3") %>%
       html_nodes("a") %>% html_attr("href") 
  
  for (j in 1:10){
    print(n)
    
    track <- read_html(track_link[j])
    
    a <- track %>% 
         html_nodes("div") %>%
         html_nodes("script") 
    k <- grep('lat',html_text(a))
    a <- a[k]
    k <- grep('trinfo',html_text(a))
    a <-html_text(a[k])
    a <- gsub("\n\t\t\t\t\t\tvar trinfo =", "",  a)
    a <- gsub(";\n\t\t\t\t\t\t", "", a)
    a <- fromJSON(a)
    
    lon <- a$at$n
    ele <- a$at$l
    lat <- a$at$a
    
    id <- rep(n, length(lat))
      
    tr <- data.frame(id = id, lat = lat, lon = lon)
      
    if(!exists("track_base")){track_base <- tr
    }else{track_base <- rbind(track_base, tr)}    
      
    n=n+1
  }
}
write.csv(track_base, paste0(path, scrap_file), row.names = F)

###### Crop scatter map ###### 
track <- read.csv(paste0(path, scrap_file))

#lat_lim <- c(41.41, 41.425)
#lon_lim <- c(2.09,2.11)

lat_lim <- c(41.4, 41.43)
lon_lim <- c(2.08,2.12)

track <- crop(track, lon_lim , lat_lim )

plot(track$lon, track$lat, type='p',  col='black', pch='.')

##### Clean scatter map ######
track$density <- 0

#circus <- 0.00001
circus <- 0.00001

for (i in 1:nrow(track)){
  print(i)
  track$density[i] <- sum(sqrt((track$lat[i]-track$lat)^2 + (track$lon[i]-track$lon)^2)<circus)
}
write.csv(track, paste0(path, "collserola_scrap_density.csv"), row.names = F)
track <- read.csv(paste0(path, "collserola_scrap_density.csv"))
hist(track$density, breaks=1000)

#track_clean <- track[track$density>5,]
track_clean <- track[track$density>0.5,]

plot(track_clean$lon, track_clean$lat, type='p',  col='black', pch='.')

track_clean$density <- NULL
write.csv(track_clean, paste0(path, "collserola_scrap_clean.csv"), row.names = F)

##### Fill seeds #####
track <- read.csv(paste0(path, "collserola_scrap_clean.csv"))

track$id <- NULL

N <- 50
lon_bins <- seq(lon_lim[1],lon_lim[2],(lon_lim[2]-lon_lim[1])/N)
lat_bins <- seq(lat_lim[1],lat_lim[2],(lat_lim[2]-lat_lim[1])/N) 
remove("starting_points")
for(i in 1:(N-1)){
 for(j in 1:(N-1)){
   print(i)
   print(j)
   
   track_sample <- crop(track, lon_bins[i:(i+1)] , lat_bins[j:(j+1)] )
   
  if(nrow(track_sample)>5){
   if(!exists("starting_points")){ starting_points <- track_sample[sample(1:nrow(track_sample),1),1:2]
   }else{starting_points <- rbind(starting_points, track_sample[sample(1:nrow(track_sample),1),1:2])}
  }
 }
}

points(starting_points$lon, starting_points$lat, col='red',  type='p' , pch=19, cex=0.5)

new_point <- as.numeric(starting_points[1,])
i <- 0
while(!is.null(new_point)){
  print(i)
  fit <- lpc(track, h=0.0001, scaled=F, x0 = new_point)
  lat=fit$LPC[,1]
  lon=fit$LPC[,2]
  lines(lon, lat, col=colors[i%%length(colors)+1], lwd = 3)
  
  if(i==0){track_fit <- data.frame(lat = lat, lon = lon, id = i)
  }else{track_fit <- rbind(track_fit, data.frame(lat = lat, lon = lon, id = i))}
  
  id_rm <- c()
  for (j in 1:length(lat)){
    distance <- sqrt((lat[j]-starting_points$lat)^2 + (lon[j]-starting_points$lon)^2)
    id_rm <- c(id_rm, which(distance<0.0002))  
  }
  id_rm <- unique(id_rm)
  print(id_rm)
  
  starting_points <- starting_points[setdiff(1:nrow(starting_points), id_rm),]
  new_point <- as.numeric(starting_points[1,])
  i <- i + 1
}
write.csv(track_fit, paste0(path, "track_fit.csv"), row.names = F)

####### Clean acumulation of points #######
track_raw <- read.csv(paste0(path, "track_fit.csv"))

#Interpolation
for (i in 0:max(track_raw$id)){
  num <- nrow(track_raw[track_raw$id==i,])
  if(i==0) track_all <- data.frame(lon = approx(track_raw[track_raw$id==i,]$lon, n=10*num)$y, lat = approx(track_raw[track_raw$id==i,]$lat, n=10*num)$y, id = i)
  else track_all <- rbind(track_all, data.frame(lon = approx(track_raw[track_raw$id==i,]$lon, n=10*num)$y, lat = approx(track_raw[track_raw$id==i,]$lat, n=10*num)$y, id = i))
} 

delta_lat <- abs(track_all$lat[1:(length(track_all$lat)-1)]-track_all$lat[2:length(track_all$lat)])
delta_lon <- abs(track_all$lon[1:(length(track_all$lon)-1)]-track_all$lon[2:length(track_all$lon)])
delta <- sqrt(delta_lat^2 + delta_lon^2)
hist(log10(delta), breaks=100)
mask <- delta>0.000001
track <- track_all[mask,]

####### Clean overlaps ######
step <- 0.00005
track$nearest <- 0 
for (i in 1:length(track$lat)){
  print(i)
  Dlat = track$lat[i] - track$lat[1:i]
  Dlon = track$lon[i] - track$lon[1:i]
  D = sqrt(Dlat^2+Dlon^2)
  
  id_near <- which(step > D)
  id_near <- id_near[abs(i-id_near)>15]
  
  if(length(id_near)>0){
    index_split <-  which(id_near[2:length(id_near)] - id_near[1:(length(id_near)-1)]>15)
  
    if(length(index_split)>0){
      id_near_list <- list()
    
      for (j in 1:length(index_split)){
        if(j==1) id_near_list[[j]] <- id_near[1:index_split[j]]    
        else id_near_list[[j]] <- id_near[(index_split[j-1]+1):index_split[j]]      
      }
  
      id_nearest <- c()
      for (j in 1:length(index_split)){
        id_near <- id_near_list[[j]]
        id_nearest <- c(id_nearest, id_near[which(min(D[id_near]) == D[id_near])])
      }
      track$nearest[i] <- paste(id_nearest, collapse = ',')
      
    }else{
        id_nearest <-  id_near[which(min(D[id_near]) == D[id_near])]
        track$nearest[i] <- paste0(id_nearest)
    }
    
  }else{
    track$nearest[i] <- '0'
  }
}

id_nooverlap <- which(track$nearest==0)
plot(track$lon, track$lat, type='p', pch='.',  col='blue')
plot(track$lon[id_nooverlap], track$lat[id_nooverlap], type='p', pch='.',  col='blue')
track <- track[id_nooverlap,]

####### Split disjoint tracks ########
delta_lat <- abs(track$lat[1:(length(track$lat)-1)]-track$lat[2:length(track$lat)])
delta_lon <- abs(track$lon[1:(length(track$lon)-1)]-track$lon[2:length(track$lon)])
delta <- sqrt(delta_lat^2 + delta_lon^2)
#hist(log10(delta), breaks=100)

id_split <- which(delta > 0.0001)

track$id[1:(id_split[2]-1)] <- 1
for (i in 2:(length(id_split)-1)){
  track$id[(id_split[i]+1):id_split[i+1]] <- i  
}
track$id[(id_split[i+1]+1):nrow(track)] <- i+1 

# for (i in 0:max(track$id)){
#  if(i==0){plot(track$lon[track$id==i], track$lat[track$id==i], type='l', col=colors[i%%(length(palette())-1)+1], pch='.',
#                xlim = c(min(track$lon),max(track$lon)), ylim = c(min(track$lat),max(track$lat)))
#  }else{lines(track$lon[track$id==i], track$lat[track$id==i], col=colors[i%%(length(palette())-1)+1], pch='.')}
# }


####### Clean small tracks ######
delta_lat <- abs(track$lat[1:(length(track$lat)-1)]-track$lat[2:length(track$lat)])
delta_lon <- abs(track$lon[1:(length(track$lon)-1)]-track$lon[2:length(track$lon)])
delta <- sqrt(delta_lat^2 + delta_lon^2)

track_dist <- c()
for (i in 1:max(track$id)){
  mask <- which(track$id == i)
  mask <- mask[1:(length(mask)-1)]
  track_dist <- c(track_dist, sum(delta[mask]))
}
hist(log10(track_dist), breaks=100)

mask <- track$id %in% setdiff(which(track_dist > 0.000316), as.numeric(names(which(table(track$id) == 1))))
track <- track[mask,]

write.csv(track, paste0(path, "tracks_v1.csv"), row.names = F)


#######################
##### Join tracks #####
track <- read.csv(paste0(path, "tracks_v1.csv"))

step <- 0.0005
track$cross <- 0 

for (i in unique(track$id)){
  t <- track[(track$id == i),c(1,2)]
  edges <- t[c(1,nrow(t)),]
  for(j in c(1,2)){
    Dlat = edges$lat[j] - track$lat
    Dlon = edges$lon[j] - track$lon
    D = sqrt(Dlat^2+Dlon^2)
    
    id_near <- which((step > D) & (track$id != i) )
    if(length(id_near)>0){
      id <- id_near[(min(D[id_near]) == D[id_near])]
      track$cross[id] <- i
    }
  }
}

track[track$cross>1,]

id_split <- sort(c(which(track$cross>0), 
                   which((track$id[2:length(track$id)] - track$id[1:(length(track$id)-1)])>0)))

track$id[1:id_split[1]] <- 1
for (i in 1:(length(id_split)-1)){
  track$id[(id_split[i]+1):id_split[i+1]] <- i+1
}

for (i in 1:max(track$id)){
 if(i==1) plot(track$lon[track$id==i], track$lat[track$id==i], col=colors[i%%(length(palette())-1)+1], type='l', lwd=2,
               xlim = c(min(track$lon),max(track$lon)), ylim = c(min(track$lat),max(track$lat)) )
 lines(track$lon[track$id==i], track$lat[track$id==i], col=colors[i%%(length(palette())-1)+1], lwd=2)
}

#### Remove one point tracks ####
count <- aggregate(track$id, by = list(track$id) , length)
id_rm <- count[count$x==1, c(1)] 
track <- track[track$id %in% setdiff(unique(track$id), id_rm),]

#### Join tracks ####
id_split <- which((track$id[2:length(track$id)] - track$id[1:(length(track$id)-1)])>0)
id_split <- sort(c(1, id_split, id_split+1, nrow(track)))
edges <- track[id_split,]
rownames(edges) <- 1:nrow(edges)
edges$edge_type <- rep(c(1,2), nrow(edges)/2)
 
circus <- 0.0002
for (i in 1:nrow(edges)){
   delta_lat <- edges$lat[i]-edges$lat
   delta_lon <- edges$lon[i]-edges$lon
   delta <- sqrt(delta_lat^2 + delta_lon^2)    
   #print(paste0(edges$id[i], ":" , paste0(setdiff(edges$id[which(delta < circus)], edges$id[i]), collapse=' ') ))  
   #match <- setdiff(edges$id[which(delta < circus)], edges$id[i])
   #match <- setdiff(edges$id[which(delta < circus)], i)
   match <- setdiff(which(delta < circus), i)
#    if(i==1){
#       df <- data.frame(a=rep(edges$id[i], length(match)), b=match) 
#    }else{
#       df <- rbind(df, data.frame(a=rep(edges$id[i], length(match)), b=match))
#    }
     if(i==1){
      df <- data.frame(id_edge=rep(i, length(match)), id_edge_match=match) 
   }else{
      df <- rbind(df, data.frame(id_edge=rep(i, length(match)), id_edge_match=match))
   } 
}

head(df, n=100)

id_edges_join <- as.numeric(names(table(df$id_edge))[table(df$id_edge)==1])
match_dictionary <- df[df$id_edge %in% id_edges_join,]

rm <- c()
for (i in 1:nrow(match_dictionary)){
  if(sum(match_dictionary$id_edge[i] == match_dictionary$id_edge_match[1:i-1]) > 0) rm <- c(rm, i)
}

match_dictionary <- match_dictionary[setdiff(1:length(match_dictionary$id_edge), rm), ]
#id_track_match_1 <- edges[match_dictionary$id_edge,]$id
id_track_match_1 <- edges[match_dictionary$id_edge, c("id", "edge_type")]
rownames(id_track_match_1) <- 1:nrow(id_track_match_1)
#id_track_match_2 <- edges[match_dictionary$id_edge_match,]$id
id_track_match_2 <- edges[match_dictionary$id_edge_match, c("id", "edge_type")]
rownames(id_track_match_2) <- 1:nrow(id_track_match_2)

for (i in length(id_track_match_1$id):1){
   if(id_track_match_2$edge_type[i] == 2 & id_track_match_1$edge_type[i] == 1){
     new_track_1 <- track[track$id == id_track_match_1$id[i], ]
     track <- track[!(track$id == id_track_match_1$id[i]), ]  
     track <- rbind(track, new_track_1)
     track$id[track$id == id_track_match_2$id[i]] <- id_track_match_1$id[i]
   }else if(id_track_match_2$edge_type[i] == 2 & id_track_match_1$edge_type[i] == 2){
     rnames <- rownames(track[track$id == id_track_match_1$id[i], ]) 
     new_track_1 <- track[track$id == id_track_match_1$id[i], ][rev(rnames),]
     track <- track[!(track$id == id_track_match_1$id[i]), ]  
     track <- rbind(track, new_track_1)
     track$id[track$id == id_track_match_2$id[i]] <- id_track_match_1$id[i]
   }else if(id_track_match_2$edge_type[i] == 1 & id_track_match_1$edge_type[i] == 1){
     new_track_1 <- track[track$id == id_track_match_1$id[i], ]
     rnames <- rownames(track[track$id == id_track_match_2$id[i], ]) 
     new_track_2 <- track[track$id == id_track_match_2$id[i], ][rev(rnames),]
     track <- track[!(track$id == id_track_match_1$id[i]), ]  
     track <- track[!(track$id == id_track_match_2$id[i]), ]  
     track <- rbind(track, new_track_2)
     track <- rbind(track, new_track_1)
     track$id[track$id == id_track_match_2$id[i]] <- id_track_match_1$id[i]
   }
   else{
    track$id[track$id == id_track_match_2$id[i]] <- id_track_match_1$id[i]
   }
}

for (i in unique(track$id)){
 if(i==1) plot(track$lon[track$id==i], track$lat[track$id==i], col=colors[i%%(length(palette())-1)+1], type='l', lwd=2,
               xlim = c(min(track$lon),max(track$lon)), ylim = c(min(track$lat),max(track$lat)) )
 lines(track$lon[track$id==i], track$lat[track$id==i], col=colors[i%%(length(palette())-1)+1], lwd=2)
}
