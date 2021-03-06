
#----------------------------------------------------------------------------------------
# NDVI/EVI MODIS time series and QA for a given roi.shp

# Author: Roberto Chavez, Sergio Estay
# Last update: 18-03-2015
# Description: delivers 3 tables (QA1, QA2, TS of NDVI/EVI filtered by QA2)

#----------------------------------------------------------------------------------------

library(raster)
library(rgdal)
library(foreign)
library(maptools)
library(parallel)

rasterOptions(tmpdir="~/ROCCO/tmp")

rm(list=ls()) #will remove ALL objects
t1<-Sys.time()
#----------------------------------------------------------------------------------------

# Please enter here paths, roi, and output name

vipath <- "~/ROCCO/PROJECTS/16b_trapananda_TS/00_MOD13_QA_testt/02_msk_lenga"
vifl <- list.files(path=vipath, pattern=glob2rx("*MOD13Q1*.tif"), full.names=T)
sceneID <- substr(vifl, 81, 116)
dates.table <- read.csv("~/ROCCO/PROJECTS/16b_trapananda_TS/00_MOD13_QA_testt/MOD13Q1_400_dates.csv", sep = ",", header=TRUE)
out.path <- "~/ROCCO/PROJECTS/16b_trapananda_TS/00_MOD13_QA_testt/table"

out.names <- 'lenga' # this goes on the output files
#poly.roi = readShapePoly('~/PROJECTS/06_lengas_puyehue/shp/pol_lenga_antillanca.shp')

modis.prod <- 'MOD13Q1'
mc.cores = 2 # number of cores (Roble server = 4 cores)

modis.vi.band = 2 # 1 for NDVI, 2 for EVI
modis.qa.band = 3 # band containing VI Quality
modis.pr.band = 4 # band containing the MODIS pixel reliability

# QA3 thresholds, please cross-check with output table 2

#QA2.thres1 = 2193 # Enter QA3 threshold <
#QA2.thres2 = 2061 # Enter QA3 threshold >
# but not QA2 == 2062,2066,2070,2118,2122,2126,2186,2190
#----------------------------------------------------------------------------------------

# THIS IS THE CODE, DO NOT CHANGE ANYTHING HERE

n.scenes <-length(sceneID)
out.table1 <- paste(out.path,'/',modis.prod,'_ts',n.scenes,'_',out.names,'_QA1.csv',sep="")
out.table2 <- paste(out.path,'/',modis.prod,'_ts',n.scenes,'_',out.names,'_QA2.csv',sep="")
out.table.ndvi <- paste(out.path,'/',modis.prod,'_ts',n.scenes,'_',out.names,'_NDVI.csv',sep="")
out.table.evi <- paste(out.path,'/',modis.prod,'_ts',n.scenes,'_',out.names,'_EVI.csv',sep="")

#----------------------------------------------------------------------------------------

# Defining a mask (region of interest) with a shapefile
ras <- raster(vifl[1])
nmaskpix <- ncell(ras)
#projection(ras)

#poly <- poly.roi
#projection(poly) # It returns NA, but the projection is fine
#mask <- rasterize(poly, ras, background=9999)
#nmask <-mask
#nmask[mask==9999] <- NA
#nmaskpix <- ncell(nmask)-cellStats(nmask, 'countNA')  

#plot(mask)

#----------------------------------------------------------------------------------------

#================================================
#     QA1 PIXEL RELIABILITY CODE -> TABLE 1     #
#================================================

# Function calculating the stats for a roi (shapefile)
tscr1 <-function(x) {
  r <- raster(x, band=modis.pr.band)
  #r[mask==9999] <- NA
  #r[r<0.13] <- NA # This applies a mask for NDVI values < 0.13
  npixels <- ncell(r)-cellStats(r, 'countNA')
  
  if (npixels == 0) {
    QA0 <- nmaskpix
    QA1 <- 0
    QA2 <- 0
    QA3 <- 0
    na <- nmaskpix
  } else {
    
    r-> rtemp
    r[r!=1] <- NA
    QA1 <- ncell(r)-cellStats(r, 'countNA')
    
    r<-rtemp
    r[r!=2] <- NA
    QA2 <- ncell(r)-cellStats(r, 'countNA')
    
    r<-rtemp
    r[r!=3] <- NA
    QA3 <- ncell(r)-cellStats(r, 'countNA')  
    
    r<-rtemp
    r[r!=0] <- NA
    QA0 <- ncell(r)-cellStats(r, 'countNA')  
    
    na <- nmaskpix-QA0-QA1-QA2-QA3
    
  }
  ff<-rbind(QA0,QA1,QA2,QA3, na)
  ff<-ff
}

# Apply the first function and create the output table
tscr2 <-function(X,d) {
  x1<-mclapply(X=vifl, FUN=tscr1, mc.cores=mc.cores)
  final<-NULL
  for(i in 1:length(x1)){
    final<-cbind(final,x1[[i]])}
  final<-t(final)
  final2<-cbind(d,final)
  write.table(final2,file=out.table1,row.names=F)
  final2<-final2
}

# Run the multicore process (2 functions at once)
out<-tscr2(X=vifl,d=dates.table)

#================================================
#       QA2 VI QUALITY CODE -> TABLE 2          #
#================================================

# The function to be run in parallel using multi-cores
QA3.list <-function(x,v) {
  r3 <-raster(x,band=3)
  #r3[mask==9999] <- NA
  v <- freq(r3)                # get the QA3 values
  
}

# Run the multicore process
x1<-mclapply(X=vifl, FUN=QA3.list, mc.cores=mc.cores)

# Makes the QA assessment for the time series and export to a table
x<-NULL
for(i in 1:length(x1)) {
  x<-rbind(x,x1[[i]])
}

x[is.na(x)] <- 999999
#x <- as.data.frame(x)
ag.x <- aggregate(count ~ value, data=x, FUN=sum)

q<-matrix(data=NA,nrow=nrow(ag.x),ncol=16)

for (i in 1:nrow(ag.x)) {
  q[i,]<-as.integer(intToBits(ag.x[i,1])[16:1])
  print(q[i,])
}

QC_Data<-as.data.frame(cbind(ag.x,q))

# Bits 0-1 QA
QC_Data$QA_word1[QC_Data$'15'==0 & QC_Data$'16'==0] <- 'VI_produced_good_quality'
QC_Data$QA_word1[QC_Data$'15'==0 & QC_Data$'16'==1] <- 'VI_produced_but_check_other_QA'
QC_Data$QA_word1[QC_Data$'15'==1 & QC_Data$'16'==0] <- 'Pixel_produced_but_most_probably_cloud'
QC_Data$QA_word1[QC_Data$'15'==1 & QC_Data$'16'==1] <- 'Pixel_not_produced_other_reasons_than_clouds'

# Bits 2-5 usefulness
QC_Data$QA_word2[QC_Data$'11'==0 & QC_Data$'12'==0 & QC_Data$'13'==0 & QC_Data$'14'==0] <- 'Highest_quality'
QC_Data$QA_word2[QC_Data$'11'==0 & QC_Data$'12'==0 & QC_Data$'13'==0 & QC_Data$'14'==1] <- 'Lower_quality'
QC_Data$QA_word2[QC_Data$'11'==0 & QC_Data$'12'==0 & QC_Data$'13'==1 & QC_Data$'14'==0] <- 'Decreasing_quality'
QC_Data$QA_word2[QC_Data$'11'==0 & QC_Data$'12'==1 & QC_Data$'13'==0 & QC_Data$'14'==0] <- 'Decreasing_quality'
QC_Data$QA_word2[QC_Data$'11'==1 & QC_Data$'12'==0 & QC_Data$'13'==0 & QC_Data$'14'==0] <- 'Decreasing_quality'
QC_Data$QA_word2[QC_Data$'11'==1 & QC_Data$'12'==0 & QC_Data$'13'==0 & QC_Data$'14'==1] <- 'Decreasing_quality'
QC_Data$QA_word2[QC_Data$'11'==1 & QC_Data$'12'==0 & QC_Data$'13'==1 & QC_Data$'14'==0] <- 'Decreasing_quality'
QC_Data$QA_word2[QC_Data$'11'==1 & QC_Data$'12'==1 & QC_Data$'13'==0 & QC_Data$'14'==0] <- 'Lowest_quality'
QC_Data$QA_word2[QC_Data$'11'==1 & QC_Data$'12'==1 & QC_Data$'13'==0 & QC_Data$'14'==1] <- 'Quality_so_low_NO_useful'
QC_Data$QA_word2[QC_Data$'11'==1 & QC_Data$'12'==1 & QC_Data$'13'==1 & QC_Data$'14'==0] <- 'L1B_data_faulty'
QC_Data$QA_word2[QC_Data$'11'==1 & QC_Data$'12'==1 & QC_Data$'13'==1 & QC_Data$'14'==1] <- 'NO_useful_or_NO_processed'

# Bits 6-7 Aerosol quantity
QC_Data$QA_word3[QC_Data$'9'==0 & QC_Data$'10'==0] <- 'Aer_climatology'
QC_Data$QA_word3[QC_Data$'9'==0 & QC_Data$'10'==1] <- 'Aer_low'
QC_Data$QA_word3[QC_Data$'9'==1 & QC_Data$'10'==0] <- 'Aer_average'
QC_Data$QA_word3[QC_Data$'9'==1 & QC_Data$'10'==1] <- 'Aer_high'

# Bit 8 Adjacent cloud detected
QC_Data$QA_word4[QC_Data$'8'==1] <- 'Adj_cloud_yes'
QC_Data$QA_word4[QC_Data$'8'==0] <- 'Adj_cloud_no'

# Bit 9 Atmosphere BRDF correction performed
QC_Data$QA_word5[QC_Data$'7'==1] <- 'BRDF_yes'
QC_Data$QA_word5[QC_Data$'7'==0] <- 'BRDF_no'

# Bit 10 Mixed clouds
QC_Data$QA_word6[QC_Data$'6'==1] <- 'Mix_cloud_yes'
QC_Data$QA_word6[QC_Data$'6'==0] <- 'Mix_cloud_no'

# Bits 11-13 Land-water flag
QC_Data$QA_word7[QC_Data$'3'==0 & QC_Data$'4'==0 & QC_Data$'5'==0] <- 'LWF_shallow_ocean'
QC_Data$QA_word7[QC_Data$'3'==0 & QC_Data$'4'==0 & QC_Data$'5'==1] <- 'LWF_land'
QC_Data$QA_word7[QC_Data$'3'==0 & QC_Data$'4'==1 & QC_Data$'5'==0] <- 'LWF_coastline_and_shoreline'
QC_Data$QA_word7[QC_Data$'3'==0 & QC_Data$'4'==1 & QC_Data$'5'==1] <- 'LWF_shallow_inland_water'
QC_Data$QA_word7[QC_Data$'3'==1 & QC_Data$'4'==0 & QC_Data$'5'==0] <- 'LWF_ephemeral_water'
QC_Data$QA_word7[QC_Data$'3'==1 & QC_Data$'4'==0 & QC_Data$'5'==1] <- 'LWF_deep_inland_water'
QC_Data$QA_word7[QC_Data$'3'==1 & QC_Data$'4'==1 & QC_Data$'5'==0] <- 'LWF_moderate_or_cont_ocean'
QC_Data$QA_word7[QC_Data$'3'==1 & QC_Data$'4'==1 & QC_Data$'5'==1] <- 'LWF_deep_ocean'

# Bit 14 Possible snow/ice
QC_Data$QA_word8[QC_Data$'2'==1] <- 'Snow_ice_yes'
QC_Data$QA_word8[QC_Data$'2'==0] <- 'Snow_ice_no'

# Bit 15 Possible shadow
QC_Data$QA_word9[QC_Data$'1'==1] <- 'Shadow_yes'
QC_Data$QA_word9[QC_Data$'1'==0] <- 'Shadow_no'

write.csv(QC_Data,out.table2,row.names=F)

