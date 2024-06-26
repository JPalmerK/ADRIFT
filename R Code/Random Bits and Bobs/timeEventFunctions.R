library(dplyr)
library(PamBinaries)
library(lubridate)
library(PAMpal)

# v 2.0 updated 5/31

makeBinRanges <- function(x, progress=TRUE) {
    tStart <- Sys.time()
    if(progress) {
        pb <- txtProgressBar(min=0, max=length(x), style=3)
        pbIx <- 0
    }
    result <- bind_rows(lapply(x, function(b) {
        b <- loadPamguardBinaryFile(b, skipLarge = TRUE, skipData = TRUE,convertDate = FALSE)
        out <- list(numStart=b$fileInfo$fileHeader$dataDate,
                    numEnd = b$fileInfo$fileFooter$dataDate)
        out$start <- convertPgDate(out$numStart)
        out$end <- convertPgDate(out$numEnd)
        out$diff <- out$numEnd - out$numStart
        out$file <- b$fileInfo$fileName
        if(progress) {
            pbIx <<- pbIx + 1
            setTxtProgressBar(pb, value=pbIx)
        }
        out
    })
    )
    result <- distinct(result, start, end, .keep_all=TRUE)
    result$interval <- interval(result$start, result$end)
    tEnd <- Sys.time()
    # cat('Time elapsed:', round(as.numeric(difftime(tEnd, tStart, units='mins')), 2), 'minutes')
    result
}

makeTimeRanges <- function(start, end=20, length='2/2', units=c('secs', 'mins', 'hours')) {
    if(is.character(length)) {
        splitLen <- strsplit(length, '/')[[1]]
        onLen <- as.numeric(splitLen[1])
        if(length(splitLen) == 1) {
            offLen <- 0
        } else {
            offLen <- as.numeric(splitLen[2])
        }
    } else {
        onLen <- length
        offLen <- 0
    }
    units <- match.arg(units)
    unitScale <- switch(units,
                        'secs' = 1,
                        'mins' = 60,
                        'hours' = 3600)
    onLen <- onLen * unitScale
    offLen <- offLen * unitScale
    if(inherits(end, 'POSIXct')) {
        totLength <- as.numeric(difftime(end, start, units='secs'))
    } else {
        totLength <- end * unitScale
    }
    startSecs <- seq(from=0, to=totLength, by=onLen + offLen)
    if(startSecs[length(startSecs)] == totLength) {
        startSecs <- startSecs[-length(startSecs)]
    }
    result <- data.frame(start = start + startSecs)
    result$end <- result$start + onLen
    result$interval <- interval(result$start, result$end)
    result
}

checkOverlap <- function(x, y, early=FALSE) {
    if(early) {
        overlap <- rep(0, nrow(x))
        for(i in seq_along(overlap)) {
            isOverlap <- int_overlaps(x$interval[i], y$interval)
            if(!any(isOverlap)) {
                overlap[i] <- 0
                next
            }
            overlap[i] <- sum(int_length(intersect(x$interval[i], y$interval[isOverlap])), na.rm=TRUE)
            if(i > 1 &&
               overlap[i] != overlap[i-1]) {
                break
            }
        }
        x$overlap <- overlap
    } else {
        x$overlap <- sapply(x$interval, function(i) {
            isOverlap <- int_overlaps(i, y$interval)
            if(!any(isOverlap)) {
                return(0)
            }
            sum(int_length(intersect(i, y$interval[isOverlap])), na.rm=TRUE)
        })
    }
    x$overlapPct <- x$overlap / int_length(x$interval)
    x
}

makeTimeEvents <- function(start=NULL, end=NULL, length, units=c('secs', 'mins', 'hours'), bin, tryFix=TRUE, plot=TRUE, progress=TRUE) {
    if(is.PAMpalSettings(bin)) {
        bin <- bin@binaries$list
    }
    if(is.character(bin)) {
        binRange <- makeBinRanges(bin, progress)
    }
    if(is.data.frame(bin)) {
        binRange <- bin
    }
    if(is.null(start)) {
        start <- min(binRange$start)
    }
    if(is.null(end)) {
        end <- max(binRange$end)
    }
    # isCont <- median(as.numeric(difftime(
    #     binRange$end, binRange$start, units='secs'
    # )))
    # isCont <- isCont < 30
    # browser()
    if(isFALSE(tryFix)) {
        timeRange <- makeTimeRanges(start, end, length=length, units=units)
    } else {
        timeRange <- fixTimeRange(start=start, end=end, bin=binRange, length=length, units=units)
    }
    binFilt <- filter(binRange,
                      end >= timeRange$start[1],
                      start <= timeRange$end[nrow(timeRange)])
    binFilt <- checkOverlap(binFilt, timeRange)
    timeRange <- checkOverlap(timeRange, binFilt)
    if(plot) {
        nOut <- nrow(binRange) - nrow(binFilt)
        tDiff <- as.numeric(difftime(timeRange$start[2:nrow(timeRange)], timeRange$end[1:(nrow(timeRange)-1)], units=units))
        op <- par(mfrow=c(3,1))
        on.exit(par(op))
        hist(binFilt$overlapPct, breaks=seq(from=0, to=1, by=.02),
             xlim=c(0,1),
             main=paste0('Pct of each binary file in event \n(', nOut, ' files outside of time range)',
                         '\n(All 1 unless duty cycle mismatch btwn event/recorder)'))
        hist(timeRange$overlapPct, breaks=seq(from=0, to=1, by=.02), xlim=c(0,1),
             main='Pct of each event with binary data\n(Should all be 1)')
        if(max(tDiff) < 1) {
            breaks <- 'Sturges'
        } else {
            breaks <- 0:ceiling(max(tDiff))
        }
        hist(tDiff, breaks=breaks, main=paste0('Time between events (', units, ')'), xlim=c(0, max(tDiff) + 1))
    }
    list(timeRange=timeRange, binRange=binFilt, allBin=binRange)
}

fixTimeRange <- function(start=NULL, end=NULL, bin, length='2/8', units='mins') {
    if(is.null(start)) {
        start <- min(bin$start)
    }
    if(is.null(end)) {
        end <- max(bin$end)
    }
    bin <- bin[(bin$end >= start) & (bin$start <= end), ]
    time <- makeTimeRanges(start=start, end=end, length=length, units=units)
    time <- checkOverlap(time, bin, early=TRUE)
    # isCont <- median(as.numeric(difftime(
    #     bin$start, bin$end, units='secs'
    # )))
    # isCont <- isCont < 30
    # # if recs are cont we dont need to reset all the time
    # # it will sort itself out
    # if(isCont) {
    #     return(time)
    # }
    result <- list()
    newBin <- bin
    newTime <- time
    pb <- txtProgressBar(min=0, max=nrow(newTime), style=3)
    for(i in 1:nrow(time)) {
        # cat(paste0(nrow(newTime), ' rows remaining...\n'))
        if(nrow(newTime) <= 1) {
            result[[i]] <- newTime
            setTxtProgressBar(pb, value=nrow(time))
            break
        }
        # browser()
        change <- which(newTime$overlap[2:nrow(newTime)] != newTime$overlap[1:(nrow(newTime)-1)])
        if(length(change) == 0) {
            result[[i]] <- newTime
            setTxtProgressBar(pb, value=nrow(time))
            break
        }
        change <- min(change) + 1
        result[[i]] <- newTime[1:change, ]
        last <- newTime$end[change]
        lastIn <- last %within% newBin$interval
        if(any(lastIn)) {
            newBin <- newBin[min(which(lastIn)):nrow(newBin), ]
            if(nrow(newBin) == 0) {
                break
            }
            nextStart <- last
        } else {
            newBin <- newBin[newBin$start >= last, ]
            if(nrow(newBin) == 0) {
                break
            }
            nextStart <- min(newBin$start)
        }

        # nextBinTime <- min(newBin$start)
        newTime <- makeTimeRanges(start=nextStart, end=max(newBin$end), length=length, units=units)
        newTime <- checkOverlap(newTime, newBin, early=TRUE)
        setTxtProgressBar(pb, value = nrow(time) - nrow(newTime))
    }
    bind_rows(result)
}