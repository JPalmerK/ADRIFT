# Create thethes worksheets for humpback and gray whale detections


rm(list = ls())

# Load the functions
source("~/GitHub/ADRIFT/R Code/Random Bits and Bobs/Tethes.R")


DepDir = "C:/Users/kaitlin.palmer/Documents/GitHub/ADRIFT/R Code/Random Bits and Bobs"


# Create a deployment worksheet
wrkshtPath <-makeTethysDep(ProjectID = 'ADRIFT',DepID = '003', DepDir, 
                           gpsBaseDir = 'Z:\\METADATA\\ADRIFT')





#Function inputs
userID<-'KPalmer'
Project<-'ADRIFT'
DepID<-'003'
Software<-'Raven Pro'
Version<-'1.6'
PlotWin<-
  annLoc ='C:\\Users\\kaitlin.palmer\\Documents\\GitHub\\databackup\\SelectonTables'

#######################################################################
#Load detections and effort
#######################################################################


# Figure out the effot from the deployment sheet
AllDeployments<-xlsx::read.xlsx(file.path(DepDir, 'Deployment Details.xlsx'),
                                sheetName='deployDetails')

#Correct Date/Time formats
#Dates and times may be read in as characters if NAs are present
if(is.character(AllDeployments$Deployment_Date)){
  AllDeployments$Deployment_Date<-openxlsx::convertToDateTime(AllDeployments$Deployment_Date)}
if(is.character(AllDeployments$Recovery_Date)){
  AllDeployments$Recovery_Date<-openxlsx::convertToDateTime(AllDeployments$Recovery_Date)}
if(is.character(AllDeployments$Data_Start)){
  AllDeployments$Data_Start<-openxlsx::convertToDateTime(AllDeployments$Data_Start)}
if(is.character(AllDeployments$Data_End)){
  AllDeployments$Data_End<-openxlsx::convertToDateTime(AllDeployments$Data_End)}
#All dates and datetimes must be saved as POSIXct for Tethys to understand them
AllDeployments$Deployment_Date<-as.POSIXct(AllDeployments$Deployment_Date,'%m/%d/%Y %H:%M:%S',tz='UTC')
AllDeployments$Recovery_Date<-as.POSIXct(AllDeployments$Recovery_Date,'%m/%d/%Y% H:%M:%S',tz='UTC')
AllDeployments$Data_Start<-as.POSIXct(AllDeployments$Data_Start,"%m/%d/%Y %H:%M:%S",tz='UTC')
AllDeployments$Data_End<-as.POSIXct(AllDeployments$Data_End,"%m/%d/%Y %H:%M:%S",tz='UTC')

AllDeployments<-AllDeployments %>%
  mutate(Depth_Sensor=as.numeric(Depth_Sensor),
         Deployment_Latitude=as.numeric(Deployment_Latitude), 
         Deployment_Longitude=as.numeric(Deployment_Longitude), 
         Recovery_Latitude=as.numeric(Recovery_Latitude),
         Recovery_Longitude=as.numeric(Recovery_Longitude),
         SensorNumber_1=as.numeric(SensorNumber_1),
         SensorNumber_2=as.numeric(SensorNumber_2),
         SensorNumber_3=as.numeric(SensorNumber_3))



AllDeployments$Exported = 0

for(ii in 1:nrow(AllDeployments)){
  
  
  #load deployment info
  depName = paste0(AllDeployments$Data_ID[ii])
  DriftFile = file.path(annLoc, paste0(depName, '.txt'))
  
  
  errorVal <-tryCatch(
    EventInfo<-read.table(file.path(annLoc, paste0(depName, '.txt')),
                          sep = '\t', header = TRUE),
    error=function(e) e
    
  )
  
  if(!inherits(errorVal, "error")){
    EventInfo<-read.table(file.path(annLoc, paste0(depName, '.txt')),
                          sep = '\t', header = TRUE)
    EventInfo$species<-as.factor(EventInfo$Species)
    EventInfo$UTC = as.POSIXct(EventInfo$Begin.Date.Time,   
                               format = "%Y/%m/%d %H:%M:%S", tz = 'UTC')
    
    # Only keep humpback detections
    EventInfo<- EventInfo[EventInfo$Species %in% 
                            c('HmpSng', 'Hmp', 'HmpSoc', 'gray', 'gray'),]
    
    #Translate species codes from Barlow to NOAA.NMFS.v1
    EventInfo$species<-recode_factor(EventInfo$species,HmpSng="Mn",Hmp="Mn",
                                     HmpSoc="Mn", Gray="Er")
    
    
    Effort<-AllDeployments%>%
      filter(Data_ID==depName)%>%
      select(Data_Start,Data_End)%>%
      rename(EffortStart=Data_Start,
             EffortEnd=Data_End)
    sppEffort = data.frame(Common.Name =c('Humpback Whale', 'Gray Whale'),
                           Species.Code = c('Mn', 'Er'),
                           Call = c('Call', 'Call'),
                           Granularity = c('Hourly Presence', 'Hourly Presence'),
                           Parameter.1 = c('Latitude', 'Latitude'),
                           Parameter.2 = c('Longitude', 'Longitude'))
    Effort = merge(Effort, sppEffort)
    
    # Load the GPS file
    gpsBaseDir = 'Z:\\METADATA\\'
    
    # Bool for name change
    if(AllDeployments$Project[ii] == 'CCES'){
      projDir = 'CCES_2018'
    }else{  projDir = AllDeployments$Project[ii]}
    
    # Bool for gps name scheme
    if(AllDeployments$Project[ii] == 'PASCAL'){
     gpsFolder = paste0(depName, '_GPS_SPOT')
    }else{    gpsFolder =paste0(depName, '_GPS')}
    
    gps = read.csv(file.path(gpsBaseDir, 
                             projDir, 
                             depName,
                             gpsFolder,
                             paste0(depName,'_GPS.csv')))
    
    
    gps$UTC=as.POSIXct(gps$UTC,tz = 'UTC')
    
    # Create prediction function to estimate drifter location when whale calls
    UTMflon <- approxfun(gps$UTC, gps$Longitude)
    UTMflat <- approxfun(gps$UTC, gps$Latitude)
    
    EventInfo$Latitude <- UTMflat(EventInfo$UTC)
    EventInfo$Longitude <- UTMflat(EventInfo$UTC)
    EventInfo$EndTime = EventInfo$UTC+seconds(EventInfo$End.Time..s.- EventInfo$Begin.Time..s.)
    
    
    
    
    
    #Create dataframes for each tab
    Detections<-EventInfo %>%
      select(Selection,species,UTC,EndTime,Latitude,Longitude)%>%
      mutate(across(where(is.character),as.numeric))%>%
      rename('Event Number'='Selection',	'Species Code'='species',	
             'Start time'='UTC','End time'='EndTime','Parameter 1'='Latitude',	
             'Parameter 2'='Longitude')
    
    MetaData<-data.frame(userID,Project,DepID,Software,Version,PlotWin) 
    MetaData<-cbind(MetaData,Effort)
    
    MetaData<-MetaData%>%
      rename('User ID'='userID',	'Deployment'='DepID',	
             'Spectrogram Parameters'='PlotWin',	'Effort Start'='EffortStart',
             'Effort End'='EffortEnd') 
    
    EffortSheet<-rename(Effort,'Common Name'='Common.Name',	
                        'Species Code'='Species.Code','Parameter 1'='Parameter.1',
                        'Parameter 2'='Parameter.2')
    
    #Create worksheet
    wb = createWorkbook()
    
    shtMetaData = addWorksheet(wb, "MetaData")
    shtEffort = addWorksheet(wb, "Effort")
    shtDetections = addWorksheet(wb, "Detections")
    #shtAdhocDetections = addWorksheet(wb, "AdhocDetections")
    
    writeData(wb,shtMetaData,MetaData)
    writeData(wb,shtEffort,EffortSheet)
    writeData(wb,shtDetections,Detections)
    #writeData(wb,shtAdhocDetections,AdhocDetections) 
    
    
    FileOut = file.path('C:\\Users\\kaitlin.palmer\\Documents\\GitHub\\databackup\\TethesFiles',
                        paste0(depName, '_Detections.xlsx'))
    saveWorkbook(wb,FileOut,overwrite=TRUE)
    AllDeployments$Exported[ii]=1
    }
}
