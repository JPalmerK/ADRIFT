rm(list=ls())


library(lubridate)
library(stringr)
library(dplyr)
library(tidyr)


# Set the directory where your CSV files are located
csv_directory <- "C:\\Data\\CCC_Data_Nugget_Blue_Whales/CCC_Data_Nugget_Blue_Whales/"

# Get a list of CSV files in the directory (adjust the pattern if needed)
csv_files <- list.files(path = csv_directory, pattern = "*.csv", full.names = TRUE)

# Use lapply to read each CSV file into a list of dataframes
list_of_dataframes <- lapply(csv_files, read.csv)

# Combine the list of dataframes into a single dataframe
combined_dataframe <- do.call(rbind, list_of_dataframes)


# Assuming df is your DataFrame with an 'inputfile' column
combined_dataframe$Adrift_id <- str_extract(combined_dataframe$Input.file, "ADRIFT_\\d{3}")

# Convert to datetime
# combined_dataframe <- combined_dataframe %>%
#   mutate(Start.timeNew = gsub("\\s\\d{2}:\\d{2}(:\\d{2})?$", "", Start.time),
#          Start.timeNew = as.POSIXct(Start.time, format = "%m/%d/%Y %H:%M"))
combined_dataframe$Start.timeNew = as.POSIXct(combined_dataframe$UTC)
combined_dataframe$Date_and_Hour=  format(combined_dataframe$Start.timeNew,
                                          "%Y-%m-%d %H")

combined_dataframe$UTC1 = as.POSIXct(combined_dataframe$UTC, 
                                     format = "%m/%d/%Y %H:%M:%S", tz = 'UTC')

## Process Meta data

# Read in the meta
meta= read.csv('C:\\Data/DepDetailsMod.csv')
meta= meta[meta$Project== 'ADRIFT', c("Project", "DeploymentID",
                                      "Instrument_ID", "Deployment_Date", 
                                      "Deployment_Latitude", 
                                      "Deployment_Longitude", "Data_Start", "Data_End",
                                      "Data_ID")]
# Only keep adrift ID 
colnames(meta)[9]<-'Adrift_id'
meta= meta[meta$Adrift_id %in% unique(combined_dataframe$Adrift_id),]



meta$start_time=as.POSIXct(meta$Data_Start, format = "%m/%d/%Y %H:%M", tz = 'UTC')
meta$end_time = as.POSIXct(meta$Data_End,   format = "%m/%d/%Y %H:%M", tz = 'UTC')



# Calculate data duration


# Deployment Duration
meta <- meta %>%
  mutate(duration_hours = as.numeric(difftime(end_time, start_time, units = "hours")))
meta$duration_days= round(meta$duration_hours/24)

adriftNumbers = c(19:26,46:53, 79:84,101:108)

# Several bw drifts were browsed but not logged. 
completedDrifts <- paste0('ADRIFT_', sprintf("%03d", adriftNumbers))
meta= meta[meta$Adrift_id %in% completedDrifts,]


# Add the meta data to the observations dataframe
bwObs = merge(meta, combined_dataframe, by= "Adrift_id", all.x = TRUE, all.y = TRUE)
bwObs$Date = as.Date(floor_date(bwObs$start_time))
bwObs = bwObs[!is.na(bwObs$Project),]
bwObs$Call = as.factor(bwObs$Call)
bwObs$UTC1 = as.POSIXct(bwObs$UTC,
                        format = "%Y-%m-%d %H:%M:%S", tz = 'UTC')

# Create a timeseries for each drift 
AggDays = data.frame()

for(ii in 1:nrow(meta)){
  
  bwObsSub = subset(bwObs, Adrift_id== meta$Adrift_id[ii])
  

  # Create the time series
  tstart = meta$start_time[ii]
  tstop = meta$end_time[ii]
  minute(tstart)=0; second(tstart)=0;  minute(tstop)=0; second(tstop)=0
  drift = meta$Adrift_id[ii]
  
  
  driftDf = data.frame(bin = seq(tstart, tstop, by = '1 hour'))
  driftDf$Adrift_id=drift

  
  # Cut the 'time' variable into bins using the 'datehour' sequence
  bwObsSub$bin <- cut(bwObsSub$UTC1, 
                       breaks =seq(tstart, tstop, by = '1 hour'), 
                       include.lowest = TRUE)
  
  counts = bwObsSub %>% 
    count(Call, bin) %>% 
    pivot_wider(names_from = Call, 
                values_from = n,
                values_fill = 0)
  
  counts$bin = as.POSIXct(counts$bin,   format = "%Y-%m-%d %H:%M:%S", tz = 'UTC')
  aa = as.data.frame(
    merge(counts, driftDf, by = 'bin', all.y = TRUE))
  
  AggDays=dplyr::bind_rows(AggDays, aa)
  
}

AggDays[is.na(AggDays)]=0

colnames(AggDays)[1]<-'DateTime'
AggDays$BlueWhale_detection = ifelse(AggDays[,2]+AggDays[,3]+AggDays[,4]>0,1,0)
AggDays[is.na(AggDays)]=0

colnames(AggDays)[2:4]<-c('BlueWhale_A', 'BlueWhale_B', 'BlueWhale_D')

##############################################################################
# Do the same for the humpbacks

# Read in the meta

# Read in the meta
meta= read.csv('C:\\Data/DepDetailsMod.csv')
meta= meta[meta$Project== 'ADRIFT', c("Project", "DeploymentID",
                                      "Instrument_ID", "Deployment_Date", 
                                      "Deployment_Latitude", 
                                      "Deployment_Longitude", "Data_Start", "Data_End",
                                      "Data_ID")]
# Only keep adrift ID 
colnames(meta)[9]<-'Adrift_id'

meta$start_time=as.POSIXct(meta$Data_Start, format = "%m/%d/%Y %H:%M", tz = 'UTC')
meta$end_time = as.POSIXct(meta$Data_End,   format = "%m/%d/%Y %H:%M", tz = 'UTC')



# Calculate data duration


# Deployment Duration
meta <- meta %>%
  mutate(duration_hours = as.numeric(difftime(end_time, start_time, units = "hours")))
meta$duration_days= round(meta$duration_hours/24)

# Set the directory where your CSV files are located
csv_directory <- "C:\\Users\\kaitlin.palmer\\Documents\\GitHub\\databackup\\SelectonTables"

# Get a list of CSV files in the directory (adjust the pattern if needed)
csv_files <- list.files(path = csv_directory, pattern = "*ADRIFT", full.names = TRUE)
csv_files_data=csv_files[-c(13,14,15)] 

completedDrifts = sub(pattern = "(.*)\\..*$", replacement = "\\1", basename(csv_files))
adriftNumbers = c(19:26,46:53, 79:83,101:108)

# Several bw drifts were browsed but not logged. 
completedDrifts <- paste0('ADRIFT_', sprintf("%03d", adriftNumbers))


  
selTable = data.frame()

for(ii in 1:length(csv_files_data)){
  aa =read.table(csv_files_data[ii], sep = '\t', header = TRUE)
  if(nrow(aa)>0){
  aa$Adrift_id =sub(pattern = "(.*)\\..*$", replacement = "\\1",
                    basename(csv_files_data[ii]))

  selTable=dplyr::bind_rows(selTable, aa)}
 
}

selTable$UTC = as.POSIXct(selTable$Begin.Date.Time,   format = "%Y/%m/%d %H:%M:%S", tz = 'UTC')
selTable = merge(meta, selTable, by= "Adrift_id", all.x = TRUE, all.y = TRUE)

selTable$Species[selTable$Species %in% c('HmpSng', 'HmpSn', 'HumpSNG',
                                         'HmSng','HumpSng','HumpSng','HmpsNG',
                                         'hmpSng')] ='HmpSng'
selTable$Species[selTable$Species %in% c('HmpsOC', 'HmpSOC', 'Hmpsoc','HmpSic',
                                         'hmpSoc','HumpSoc')] ='HmpSoc'
selTable$Species[selTable$Species %in% c('Hump','hmp', 'hump')] ='Hmp'

# Remove all empty species rows
selTable = selTable[selTable$Species %in% c('Hmp', 'HmpSng', 'HmpSoc'),]


meta= meta[meta$Adrift_id %in% completedDrifts,]

selTableout = data.frame()
for(ii in 1:nrow(meta)){
  
  # Create the time series
  tstart = meta$start_time[ii]
  tstop = meta$end_time[ii]
  minute(tstart)=0; second(tstart)=0;  minute(tstop)=0; second(tstop)=0
  drift = meta$Adrift_id[ii]
  
  
  driftDf = data.frame(bin = seq(tstart, tstop, by = '1 hour'))
  driftDf$Adrift_id=drift

  selTableSub = subset(selTable, Adrift_id== meta$Adrift_id[ii])
  if(nrow(selTableSub)>1){
  
  # Cut the 'time' variable into bins using the 'datehour' sequence
  selTableSub$bin <- cut(selTableSub$UTC, 
                      breaks =seq(tstart, tstop, by = '1 hour'), 
                      include.lowest = TRUE)
  selTableSub$Species = as.factor(selTableSub$Species)
  
  counts = selTableSub %>% 
    count(Species, bin) %>% 
    pivot_wider(names_from = Species, values_from = n,
                values_fill = 0)
  
  counts$bin = as.POSIXct(counts$bin,   format = "%Y-%m-%d %H:%M:%S", tz = 'UTC')
  
  aa = as.data.frame(
    merge(counts, driftDf, by = 'bin', all.y = TRUE))
  
  selTableout=dplyr::bind_rows(selTableout, aa)}else{
    selTableout=dplyr::bind_rows(selTableout, driftDf)
  }
  
}

selTableout[is.na(selTableout)]=0
selTableout[,c(3:5)]=as.numeric(selTableout[,c(3:5)]>=1)
selTableout$Humpback_detection = ifelse(selTableout[,3]+selTableout[,4]+
                                     selTableout[,5]>0,1,0)

colnames(selTableout)[3:5]<- c('Humpback_unknown', 'Humpback_song', 'Humpback_non_song')

Hmp_blue = merge(selTableout, AggDays, by.x= c('Adrift_id', 'bin'), 
           by.y = c('Adrift_id','DateTime'), all=TRUE)

colnames(Hmp_blue)[2]<-'DateTime'
Hmp_blue$Month = month(Hmp_blue$DateTime, label = TRUE)

Hmp_blue=Hmp_blue[,c(1,2,11,3,4,5,6,7,8,9,10)]


#######################################################################
# Adrift numbers to keep
adriftNumbers = c(1:11, 13:14,16, 46:53, 19:26, 79:84, 101:108)
adriftNumbers = c(19:26,46:53, 79:84,101:108)

# Several bw drifts were browsed but not logged. 
AdriftNames <- paste0('ADRIFT_', sprintf("%03d", adriftNumbers))

# Remove all drifts that aren't in the CCCes list 
AdriftDrifts = subset(Hmp_blue, Adrift_id %in% AdriftNames)



# List of drifts for which we don't have data
BW_drifts = unique(AggDays$Adrift_id)
HB_drifts = unique(selTableout$Adrift_id)



NoDataBW = AdriftNames[!(AdriftNames %in% HB_drifts)]
NoDataHB = AdriftNames[!(AdriftNames %in% HB_drifts)]


NoDatSpecies = c(rep('BlueWhale', length(NoDataBW)), 
                 rep('Humpback', length(NoDataHB)))



# Ok, not including blue whale data for adrift IDs where there were no calls


noAdriftData  = data.frame(Adrift_id = AdriftNames)
noAdriftData$HB_browsed = ifelse( AdriftNames %in% HB_drifts, 'yes', 'no')
noAdriftData$Blue_browsed = ifelse( AdriftNames %in% BW_drifts, 'yes', 'no')

ndeteHmp = aggregate(data = Hmp_blue, Humpback_detection~Adrift_id, 
                                             FUN = sum)

ndeteBlu = aggregate(data = Hmp_blue, BlueWhale_detection~Adrift_id, 
                     FUN = sum)

noAdriftData=merge(noAdriftData, ndeteHmp, by ='Adrift_id', all.x = TRUE)
noAdriftData=merge(noAdriftData, ndeteBlu, by ='Adrift_id', all.x = TRUE)


nLen = aggregate(data = Hmp_blue, Month~Adrift_id, 
                     FUN = length)

colnames(nLen)[2]<-'Deployment_TotalHours'

noAdriftData=merge(noAdriftData, nLen, by ='Adrift_id', all.x = TRUE)



#######################################################################
# Odontocetes
######################################################################

# Load Anne's odontocoete data

AdriftDrifts$DateTimeIdx = paste0(AdriftDrifts$Adrift_id, AdriftDrifts$DateTime)

odont = read.csv('C:\\Users\\kaitlin.palmer\\Downloads\\DataNuggets_Odontocete+Ships_HourlyPresence.csv')
odont$DateTime = as.POSIXct(odont$DateTimeNotFucked, format = "%Y-%m-%d %H:%M:%S")
odont$DateTime= as.character(odont$DateTime)
odont$DateTimeIdx = paste0(odont$Adrift_id, odont$DateTimeNotFucked)

odont$dup = duplicated(odont$DateTimeIdx)
odontrimmed = odont[odont$dup==FALSE, ]
odontrimmed = odontrimmed[odontrimmed$DateTimeIdx %in% AdriftDrifts$DateTimeIdx,]

odontrimmed$DateTime = odontrimmed$DateTimeNotFucked

AdriftTrimmed = AdriftDrifts[AdriftDrifts$DateTimeIdx %in% odontrimmed$DateTimeIdx,]




aa = merge(odontrimmed, AdriftTrimmed, by = c('DateTimeIdx'), all.x =TRUE, all.y=FALSE)

AllData = aa[,c(2,3,11,4:6,12:19)]
AllData[is.na(AllData)]=0
colnames(AllData)[c(1,2)]<- c("Adrift_id", "DateTime")

write.csv(AllData, 'All_data_HrlyPres.csv', row.names = FALSE)


# Create summaries
AllData$Date = as.Date(AllData$DateTime)
colnames(AllData)
SummaryData = aggregate(data = AllData, Pacific_white_sided_dolphin~
                          Adrift_id+Date+Month, FUN = sum)

SummaryData = cbind(SummaryData,
                    aggregate(data = AllData, Sperm_whale~
                          Adrift_id+Date+Month, FUN = sum)[,4])


SummaryData = cbind(SummaryData,
                    aggregate(data = AllData, Ship~
                                Adrift_id+Date+Month, FUN = sum)[,4])

SummaryData = cbind(SummaryData,
                    aggregate(data = AllData, Humpback_unknown~
                                Adrift_id+Date+Month, FUN = sum)[,4])
SummaryData = cbind(SummaryData,
                    aggregate(data = AllData, Humpback_song~
                                Adrift_id+Date+Month, FUN = sum)[,4])
SummaryData = cbind(SummaryData,
                    aggregate(data = AllData, Humpback_non_song~
                                Adrift_id+Date+Month, FUN = sum)[,4])
SummaryData = cbind(SummaryData,
                    aggregate(data = AllData, Humpback_detection~
                                Adrift_id+Date+Month, FUN = sum)[,4])
SummaryData = cbind(SummaryData,
                    aggregate(data = AllData, BlueWhale_A~
                                Adrift_id+Date+Month, FUN = sum)[,4])
SummaryData = cbind(SummaryData,
                    aggregate(data = AllData, BlueWhale_B~
                                Adrift_id+Date+Month, FUN = sum)[,4])
SummaryData = cbind(SummaryData,
                    aggregate(data = AllData, BlueWhale_D~
                                Adrift_id+Date+Month, FUN = sum)[,4])
SummaryData = cbind(SummaryData,
                    aggregate(data = AllData, BlueWhale_detection~
                                Adrift_id+Date+Month, FUN = sum)[,4])

colnames(SummaryData)[4:14]<- colnames(AllData)[4:14]

write.csv(SummaryData, 'DataNuggests_Daily_Summary.csv', row.names = FALSE)





# Fill the blue whale columns with NAN for not included drifts
AdriftDrifts[!(AdriftDrifts$Adrift_id == noAdriftData$Adrift_id),c(8:11)]

notBrowsedBW =noAdriftData$Adrift_id[noAdriftData$Blue_browsed=='no']


AdriftDrifts[AdriftDrifts$Adrift_id %in% notBrowsedBW,c(8:11)]<-0

write.csv(AdriftDrifts, 'Adrift_Species_HourlyDetections.csv')
write.csv(noAdriftData, 'SpeciesSummary_byDrift.CSV')

