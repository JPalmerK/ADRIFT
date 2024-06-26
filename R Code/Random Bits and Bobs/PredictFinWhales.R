# Load the prediction grid


rm(list = ls())
library(ggplot2)
library(lubridate)
library(dplyr)
library(sp)
source('SpatialFxs.R')
###########################################################
# Load noise and GPS
############################################################


# Load data, drift GPS, and noise levels pre-process, and wind lease area

# Set the directory where your CSV files are located
csv_directory <- "F:\\GPS_CSV-20230923T045356Z-001\\MorroBay Mar 2023"

# Get a list of CSV files in the directory (adjust the pattern if needed)
csv_files <- list.files(path = csv_directory, 
                        pattern = "*.csv", full.names = TRUE)

# Combine the list of dataframes into a single dataframe
GPSdf <- do.call(rbind, lapply(csv_files, read.csv))

# Add UTC coords with the sp package
cord.dec = SpatialPoints(cbind(GPSdf$Longitude,GPSdf$Latitude),
                         proj4string=CRS("+proj=longlat"))
cord.dec = spTransform(cord.dec, CRS("+init=epsg:32610"))
GPSdf$UTMx =  coordinates(cord.dec)[,1]
GPSdf$UTMy =  coordinates(cord.dec)[,2]

# Convert to datetime, create date hour column
GPSdf$UTC=as.POSIXct(GPSdf$UTC,tz = 'UTC')
GPSdf$UTCDatehour = GPSdf$UTC
minute(GPSdf$UTCDatehour)<-0
second(GPSdf$UTCDatehour)<-0


# Add noise level data
csv_directory='F:\\GPS_CSV-20230923T045356Z-001\\MorroBay Mar 2023 Noise Files'
csv_files <- list.files(path = csv_directory, pattern = "*.csv", full.names = TRUE)
dataframes_list <- list()

# Loop through each CSV file load, change name
for (csv_file in csv_files) {
  # Read the CSV file
  df <- read.csv(csv_file, header = TRUE)
  
  # Extract the first and eighth columns
  df <- df[, c(1, 8)]
  colnames(df)[1]<-'UTC'
  
  # Extract the first 10 characters from the filename
  file_name <- substr(basename(csv_file), 1, 10)
  
  # Create a 'DriftName' column with the extracted filename
  df$DriftName <- file_name
  
  # Append the dataframe to the list
  dataframes_list[[file_name]] <- df
}

# Combine all dataframes into a single dataframe
noiseDf <- bind_rows(dataframes_list)
noiseDf$datetime_posix <- as.POSIXct(noiseDf$UTC, 
                                     format = "%Y-%m-%dT%H:%M:%OSZ",
                                     tz='UTC')

# Clean out data for drifts that don't have gps or noise levels
GPSdf= subset(GPSdf, DriftName %in% noiseDf$DriftName)
noiseDf= subset(noiseDf, DriftName %in% GPSdf$DriftName)


#######################################################
# Load prediction grids and variables
##########################################################
predGridLoc ='C:\\Data\\Prediction Grids\\Grids_for_Kaitlin'
predGrid = read.csv(paste0(predGridLoc, '\\', 'CCE_0.1deg_2018-07-01.csv'))
denGridd = read.csv('C:\\Data/Prediction Grids/CCE_SDMs_2018_Bp_BiWeekly_Preds.csv')

denGridd$lat = denGridd$mlat
denGridd$lon = denGridd$mlon-360
# Trim the dnesity and the prediction grid to the region of the
# drifts

predGridSub =subset(predGrid, lat<= 36 & lat>34.5 &
                      lon >  -122.5 & lon<= -121.5) 
denGridSub = subset(denGridd, mlat<= 36 & mlat>34.5 &
                      mlon > 237.5 & mlon<= 238.5)

# Plot check
ggplot(predGrid)+
  geom_tile(aes(x= lon, y= lat, fill = ild.mean))

ggplot(denGridSub)+
  geom_tile(aes(x=mlon-360, y = mlat, fill=X74.dens.2018.07.01))+
  geom_point(data= GPSdf, aes(x=Longitude, y= Latitude), color ='yellow')
##########################################################################
# Simulate whales within the array based on density likelihood


# normalize the density
denGridSub$NormDen = rescale(denGridSub$X74.dens.2018.07.01)

createSimWhales = function(denGridSub){

  
  # Make whales and figure out times
  denGridSub$Finwhales = rbinom(prob =denGridSub$NormDen, 
                                size = 1, n = nrow(denGridSub))
  
  
  sim.calls = denGridSub[denGridSub$Finwhales==1, c('lat', 'lon')]
  sim.calls= sim.calls[!is.na(sim.calls$lat),]
  colnames(sim.calls)<-c('Lat', 'Lon')
  sim.calls$Lat = jitter(sim.calls$Lat)
  sim.calls$Lon = jitter(sim.calls$Lon)
  
  # Simulate Source Levels(https://academic.oup.com/icesjms/article/76/1/268/5115402)
  # source, level, noise level, frequen(ies), and SNR threshold
  f=100:300
  SL_max=182.6
  SL_min = 197.4
  SNRthresh=2
  h=100
  SLmean =190.5-10#subtracting 10 since we are in the wrong noise band
  SLstdev = 7.4
  
  sim.calls$SL = rnorm(SLmean, SLstdev, n=nrow(sim.calls)) 
  sim.calls$UTC = sample(seq(min(GPSdf$UTC)+hours(12), 
                               max(GPSdf$UTC)-hours(12), 
                               by="1 mins"), nrow(sim.calls))
  
  sim.calls$MaxSNR=NaN
  sim.calls$GridCenterLat=NaN
  sim.calls$GridCenterLon=NaN
  sim.calls$rNearestInstrument=NaN
  sim.calls$NearestInstrumentLat =NaN
  sim.calls$NearestInstrumentLon =NaN
  sim.calls$AllDetInstLat= NaN
  sim.calls$AllDetInstLon= NaN
  sim.calls$AllDetInstID = NaN
  return(sim.calls)

}

# TDOA ERROR in seconds
PositionError = 1152/1500 # 80th percentile of the GPS error
SSPError = (1500*.2)/1500 # 20% error in speed of sound
TDOA_error = SSPError+PositionError

# Allowable SNR error

SLmean =190.5-10#subtracting 10 since we are in the wrong noise band
SLstdev = 7.4
SNR_error = SLstdev*1.5+TL(TDOA_error)

########################################################
# Prediction grid
######################################################

acceptedLocs = list()
whaleGridTemplate = expand.grid(Lat = seq(min(denGridSub$lat),
                                          max(denGridSub$lat), 
                                          length.out =80),
                                Lon = seq(min(denGridSub$lon), 
                                          max(denGridSub$lon), 
                                          length.out =80),
                                DriftName = unique(GPSdf$DriftName))

whaleGridTemplate$cellId =paste0(whaleGridTemplate$Lat,
                                               whaleGridTemplate$Lon)


##################################################################
# Run the simulation
####################################################################
DriftNames = unique(GPSdf$DriftName)
figs =list()

p<-ggplot()+
  xlim(c(-123.5, -121.))+
  ylim(c(35.25,36))+
  theme_bw()

whaleGridTemplate$Counts = 0
whaleGridTemplate$NWhales = 0
whaleGridTemplate$AreaMonitored = 0

AreaMonitored=0

sim.calls = createSimWhales(denGridSub)
sim.callsAll = sim.calls

for(jj in 1:150){
  
  sim.callsAll=rbind(sim.calls, sim.callsAll)
  # # Plot check
  # ggplot(data =denGridSub, aes(x=lon, y = lat))+
  #   geom_tile(aes(fill=X74.dens.2018.07.01))+
  #   geom_point(data= sim.calls, aes(x=Lon, y = Lat,size = SL))
  
  for(ii in 1:nrow(sim.calls)){
  # Preallocate the grid
  # Create 8 grids to show where the whale might be
  whaleGrid = whaleGridTemplate
  
  
  # Recieved level dataframe
  RLdf = data.frame(DriftName = as.factor(DriftNames))
  
  for(drift in DriftNames){
    GPSsub = subset(GPSdf, DriftName == drift)
    NLsub =  subset(noiseDf, DriftName==drift)
    
    UTMflon <- approxfun(GPSsub$UTC, GPSsub$Longitude)
    UTMflat <- approxfun(GPSsub$UTC, GPSsub$Latitude)
    
    NL_FUN <-  approxfun(NLsub$datetime_posix, NLsub$TOL_500)
    
    ##############################################################
    # Calculate the range from the whale to the GPS, TDOA and RL
    ############################################################
    
    # Lat/lon/ of the drift when the call was produced
    RLdf$Lon[RLdf$DriftName==drift] =UTMflon(sim.calls$UTC[ii])
    RLdf$Lat[RLdf$DriftName==drift] = UTMflat(sim.calls$UTC[ii])
    RLdf$NoiseLevel[RLdf$DriftName==drift] = NL_FUN(sim.calls$UTC[ii])
    
    
    # Spatial Uncertainty, GPS- estimate the speed at a the call arrival time
    # then how far it could drift
    idxMindiff = which.min(abs((sim.calls$UTC[ii])- (GPSsub$UTC)))
    Time_drift = seconds(GPSsub$UTC[idxMindiff]-seconds(sim.calls$UTC[ii]))
    
    # Likely an overestimate of the error
    whaleGrid$rElipsoid[whaleGrid$DriftName==drift] = 
      haversine_dist(whaleGrid$Lon[whaleGrid$DriftName==drift],
                     whaleGrid$Lat[whaleGrid$DriftName==drift],
                     RLdf$Lon[RLdf$DriftName==drift], 
                     RLdf$Lat[RLdf$DriftName==drift])
  }
  
  # Range from the whale to the hydrophone in kms  (truth)
  RLdf$range_havers = haversine_dist(sim.calls$Lon[ii],
                                     sim.calls$Lat[ii],
                                     RLdf$Lon, RLdf$Lat)
  
  RLdf$ArrialTimeHavers =  sim.calls$UTC[ii]+(RLdf$range_havers/1500)
  RLdf$SNRHavers= sim.calls$SL[ii]-TL(RLdf$range_havers)-RLdf$NoiseLevel
  
  # Call detected or not
  RLdf$Detected = ifelse(RLdf$SNRHavers>12,1,0)
  RLdf$DetecteColor = ifelse(RLdf$SNRHavers>12,'green','maroon')
  
  
  # estimate the drifter location from the available data
  whaleGrid= merge(whaleGrid, 
                   RLdf[,c('ArrialTimeHavers','DriftName',
                           'SNRHavers', 'NoiseLevel', 'Detected')], 
                   by.y='DriftName')
  
  # The expected SNR at each grid location- the mean SL, minus the NL at that time
  # minus the transmission loss between the whale location and the grid location
  whaleGrid$ExpectedSNR_havers = SLmean-TL(whaleGrid$rElipsoid)-
    whaleGrid$NoiseLevel
  
  whaleGrid$AreaMonitored = ifelse(whaleGrid$ExpectedSNR_havers>12,
                                   1,0)

  # ggplot()+
  #   geom_tile(data = whaleGrid, 
  #             aes(x = Lon, y=Lat, 
  #                 fill=AreaMonitored))
  # For detected calls, we know that the SNR must be within the acceptable range
  # the acceptable range is the 
  whaleGrid$SNRok_havers[whaleGrid$Detected==1]=
    ifelse(whaleGrid$ExpectedSNR_havers[whaleGrid$Detected==1]+SNR_error  >= 
             whaleGrid$SNRHavers[whaleGrid$Detected==1] &
             (whaleGrid$ExpectedSNR_havers[whaleGrid$Detected==1]-SNR_error) <= 
             whaleGrid$SNRHavers[whaleGrid$Detected==1], 1,0)
  
  
  
  # For not detected calls the SNR must be lower than the minimum expected SNR
  whaleGrid$SNRok_havers[whaleGrid$Detected==0]=
    ifelse(whaleGrid$ExpectedSNR_havers[whaleGrid$Detected==0]<=SNR_error,1,0)
  
  # Count up the cells that were OK by all buoys
  aggData = aggregate(data = whaleGrid, SNRok_havers~cellId, FUN=sum)
  
  colnames(aggData)[2]<-'Count'
  
  # Which grid locs were 'ok' by all receivers?
  whaleGrid = merge(whaleGrid, aggData, by = 'cellId', all.x=TRUE)
  
  #RLDFDetected = subset(RLdf, Detected==1)
  
  # Pull out the accepted locations, usefule for all calls even if for units
  # where animal wasn't detected also nix anything more than 50kms out
  accepted_locs = subset(whaleGrid, Count == nrow(RLdf))
  
  ########################################################
  # Create n-1 tdoa trids, nix data outside the expected TDOA values
  ########################################################
  if(sum(RLdf$Detected)>1){
    
    # All TDOA combinations
    combinations = combn(RLdf$DriftName[RLdf$Detected==1], 2,simplify = TRUE)
    
    for(kk in 1:ncol(combinations)){
      
      # Pull out the grids for each drift
      grid1 = subset(accepted_locs, DriftName==combinations[1, kk])
      grid2 = subset(accepted_locs, DriftName==combinations[2, kk])
      
      # Caluclate the expected TDOA
      grid1$TDOA = (grid1$rElipsoid-grid2$rElipsoid)/1500
      
      
      #Observed TDOA between the pairs
      OBS_tdoa = RLdf$ArrialTimeHavers[RLdf$DriftName==combinations[1,kk]]-
        RLdf$ArrialTimeHavers[RLdf$DriftName==combinations[2,kk]]
      
      
      # Pick out the locations that are OK within the TDOA grid
      grid1$ok =(grid1$TDOA>(OBS_tdoa-TDOA_error) & 
                   grid1$TDOA<=(OBS_tdoa+TDOA_error))
      
      # Trim the accepted locations
      accepted_locs= subset(accepted_locs, 
                            cellId %in% grid1$cellId[grid1$ok==TRUE])
      
    }
    
    
    # Add the SNR, and grid center
    sim.calls$MaxSNR[ii]=max(RLdf$SNRHavers[RLdf$Detected==1])
    sim.calls$GridCenterLat[ii]=min(accepted_locs$Lat, na.rm = TRUE)+
      diff(abs(range(accepted_locs$Lat,na.rm = TRUE)))/2
    sim.calls$GridCenterLon[ii]=min(accepted_locs$Lon, na.rm = TRUE)+
      diff(abs(range(accepted_locs$Lon, na.rm = TRUE)))/2
    
    # Distance to the nearest instrument
    sim.calls$rNearestInstrument[ii]=min(RLdf$range_havers[RLdf$Detected==1])
    sim.calls$NearestInstrumentLat[ii] = RLdf$Lat[which.max(RLdf$SNRHavers)]
    sim.calls$NearestInstrumentLon[ii] = RLdf$Lon[which.max(RLdf$SNRHavers)]
    
    # Distance to all instruments
    sim.calls$AllDetInstLat[ii] =  list(RLdf$Lat[RLdf$Detected==1])
    sim.calls$AllDetInstLon[ii] = list(RLdf$Lon[RLdf$Detected==1])
    sim.calls$AllDetInstID[ii] = list(RLdf$DriftName[RLdf$Detected==1])
    
    # Create a figure
    figs[[ii]]=p+
      geom_path(data = GPSdf[GPSdf$UTC<= sim.calls$UTC[ii],], 
                aes(x=Longitude, y=Latitude, group = DriftName), color='black')+
      geom_point(data = RLdf, 
                 aes(x=Lon, y=Lat, group = DriftName, shape = DriftName, 
                     color= as.factor(Detected)))+
      geom_point(data = accepted_locs, aes(x=Lon, y=Lat), color = 'gray60')+
      geom_point(data=sim.calls[ii,], 
                 aes(Lon, Lat), size=3, color='red')
    
    # Save the accepted locations
    acceptedLocs[[ii]]<-accepted_locs
  }
  #print(ii)
  }
  
  # Add the accepted locs to ghe grid counts
  ids = whaleGridTemplate$cellId %in% accepted_locs$cellId
  
  # Could the whale have been there?
  whaleGridTemplate$Counts[ids]= whaleGridTemplate$Counts[ids]+1
  
  # How many times was each cell monitored?
  AreaMonitored=AreaMonitored+ 
    aggregate(data = whaleGrid, 
              AreaMonitored~cellId, FUN=sum)[,2]
  
  # Total number of whale calls
  whaleGridTemplate$NWhales = whaleGridTemplate$NWhales + nrow(sim.calls)
  sim.calls = createSimWhales(denGridSub)
  
  
  print(jj)
  }



ggplot(data = whaleGridTemplate)+geom_tile(aes(y=Lat, x=Lon, fill = Counts))

# Plot the surfaces- we see the areas where we are certain there are not whales
dataOut = subset(whaleGridTemplate, DriftName == 'ADRIFT_051')

dataOut$Monitored = AreaMonitored
dataOut$Count_Monitered = dataOut$Counts/dataOut$Monitored


# Plot the effort- wait, this looks like the underlying density plot. This isn't
# the area monitored, it's the area monitored when there is a detection
ggplot(denGridSub)+
  geom_tile(aes(x=mlon-360, y = mlat, fill=X74.dens.2018.07.01))+
  geom_point(data= GPSdf, aes(x=Longitude, y= Latitude), size=0.5, color ='yellow')+
  ggtitle('Fin Whale Density Surface and Plots')

# This is the area monitored when there are detections
ggplot(data = dataOut)+geom_tile(aes(y=Lat, x=Lon, fill = Monitored ))+
  geom_point(data= GPSdf, aes(x=Longitude, y= Latitude), size=0.5, color ='yellow')

# This is the counts divided by the data
ggplot(data = dataOut)+geom_tile(aes(y=Lat, x=Lon, fill = Count_Monitered ))+
  geom_point(data= GPSdf, aes(x=Longitude, y= Latitude), size=0.5, color ='yellow')
  

######################################################################
# Figure out area monitored
######################################################################

# Create a prediction grid with lat, lon, time, drift, and noise
predGrid = expand.grid(DriftName =  unique(GPSdf$DriftName),
                       UTC = seq(min(GPSdf$UTC), max(GPSdf$UTC), by= '20 min'))
predGrid$Lat=NaN
predGrid$Lon =NaN
predGrid$NL = NaN

DriftNames = unique(predGrid$DriftName)

for(drift in DriftNames){
  
  GPSsub = subset(GPSdf, DriftName == drift)
  NLsub =  subset(noiseDf, DriftName==drift)
  
  UTMflon <- approxfun(GPSsub$UTC, GPSsub$Longitude)
  UTMflat <- approxfun(GPSsub$UTC, GPSsub$Latitude)
  NL_FUN <-  approxfun(NLsub$datetime_posix, NLsub$TOL_500)
  
  predGrid$NL[predGrid$DriftName==drift] = NL_FUN(predGrid$UTC[predGrid$DriftName==drift])
  predGrid$Lat[predGrid$DriftName==drift] = UTMflat(predGrid$UTC[predGrid$DriftName==drift])
  predGrid$Lon[predGrid$DriftName==drift] = UTMflon(predGrid$UTC[predGrid$DriftName==drift])
  
  print(drift)
}



# Step through the timestamps and make the predictions

# Preallocate the grid
whaleGridArea = expand.grid(Lat = seq(min(denGridSub$lat),
                                          max(denGridSub$lat), 
                                          length.out =80),
                                Lon = seq(min(denGridSub$lon), 
                                          max(denGridSub$lon), 
                                          length.out =80))

whaleGridArea$cellId =paste0(whaleGridArea$Lat,
                             whaleGridArea$Lon)
whaleGridArea$FinalCount = 0
whaleGridArea$rElipsoid=NaN
whaleGridArea$Detected=0

SNRthresh= 25

for(ii in 1:nrow(predGrid)){
  
  
#  for(ii in 1:110){


    
  if(!is.na(predGrid$Lat[ii]) & !is.na(predGrid$NL[ii])){

    # Range from each point to each Drift

      # Dist between the drift and the prediction grid cells
      whaleGridArea$rElipsoid = 
        haversine_dist(whaleGridArea$Lon,
                       whaleGridArea$Lat,
                       predGrid$Lon[ii], 
                       predGrid$Lat[ii])
      
      whaleGridArea$SNR = (SLmean+(SLstdev*1.5))- 
                          TL(whaleGridArea$rElipsoid)-
                          predGrid$NL[ii]
      whaleGridArea$Detected = ifelse(whaleGridArea$SNR>SNRthresh,1,0)
      whaleGridArea$FinalCount = whaleGridArea$FinalCount+
        whaleGridArea$Detected
      
      
  }
    if(any(is.na(whaleGridArea$FinalCount))){
      print(ii)
    }
}

  # Plot the effort grid
  ggplot(whaleGridArea)+geom_tile(aes(x =Lon, y=Lat, fill=FinalCount))+
    geom_point(data= GPSdf, aes(x=Longitude, y= Latitude), 
               size=0.5, color ='yellow')+
    ggtitle('Effort, n=Times spatial point was monitored')
  
  
  
  




