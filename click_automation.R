pkgTest <- function(x)
{
  if (!require(x,character.only = TRUE))
  {
    install.packages(x,dep=TRUE)
    if(!require(x,character.only = TRUE)) stop("Package not found")
  }
}

pkgs <- c("jsonlite","readxl","dplyr","RSelenium","futile.logger")
sapply(pkgs, pkgTest)

flog.appender(appender.file('ticker-scraper.log'), name='ticker-scraper')


copy_rename_files <- function(tmpPath, destPath, appendName, fileType) {
  #check files exist in temp directory
  if(length(dir(tmpPath, all.files=TRUE)) > 0) {
    
    tmpPath <- gsub("\\\\", "/", tmpPath)
    destPath <- gsub("\\\\", "/", destPath)
    
    sapply(paste0(tmpPath, list.files(tmpPath)),FUN=function(eachPath){
      
      #rename - add datetimestamp
      eachPathDTS <- gsub(pattern=fileType,
                          replacement=paste0(appendName, gsub(":",".",gsub(" ","_",Sys.time())), fileType),
                          eachPath,
                          ignore.case = FALSE)
      
      file.rename(from=eachPath,to=eachPathDTS)
      
      #move
      finalPath <- sub(pattern=tmpPath,
                       replacement=destPath,
                       eachPathDTS,
                       ignore.case = FALSE,
                       fixed = TRUE)
      file.copy(from=eachPathDTS,to=finalPath)
    })

    return(TRUE)
    
  } else {
    flog.warn("No files downloaded",
              name='ticker-scraper')
    print("No files downloaded")
    
    return(FALSE)
  }

}

#loop through each row and download data
download_files <- function(remote_selenium, clicks_file, append_to_name, destPath, screenshotLogging = FALSE){
  #browser()
  count <- 0
  while (count < 5) {
    Sys.sleep(2 + (3*runif(1)))
    try(remote_selenium$navigate(clicks_file%>%pull(urls)))
    Sys.sleep(2 + (3*runif(1)))
    count <- count + 1
      
    if (screenshotLogging == TRUE){
      remote_selenium$screenshot(file = paste0("selenium_screenshot-",
                                               clicks_file%>%pull(step),
                                               gsub(":",".",gsub(" ","_",Sys.time())),
                                               ".png"))
    }
    
    sendKeysToElement <- clicks_file%>%pull(sendKeysToElement)
    if (!is.na(sendKeysToElement)){
      sendKeysToElement <- jsonlite::fromJSON(sendKeysToElement)
  
      for(sendKey in sendKeysToElement){
        el_using <- sendKey$using
        el_value <- sendKey$value
        el_send_key <- sendKey$sendKey
  
        el <- remote_selenium$findElement(using = el_using, value = el_value)
        el$sendKeysToElement(list(el_send_key))
      }
      
      
    }
    
    #browser()
    #trigger the button clicks if any present, in the order they are present in the json
    buttonClicks <- clicks_file%>%pull(css_button)
    if (buttonClicks != "" & !is.na(buttonClicks)){
      buttonClicks <- jsonlite::fromJSON(buttonClicks)
      
      for(buttonClick in buttonClicks){
        el_button <- buttonClick[1,]
        
        webElem <- try(remote_selenium$findElement(using = "css", el_button), TRUE)
        try(webElem$clickElement(), TRUE)
      }
    }
    
    #trigger css export button
    webElem <- try(remote_selenium$findElement(using = "css", clicks_file%>%pull(final_click)), TRUE)
    if (remote_selenium$status == 7) {
      try(remote_selenium$dismissAlert)
    } else {
      webElem$clickElement()
      count <- 10
    }
  
    perform_download <- clicks_file%>%pull(perform_download)
    if (perform_download==TRUE) {
      #after downloading each file, get the name of the file from docker
      #then copy that over to local machine
      # then delete all files in the download folder
  
      #copy file from docker to local machine
      sourcePath <- ":/home/seluser/Downloads/."
      tmpPath <- paste0(tempdir(), "\\" , rnorm(1), "\\")
      dir.create(tmpPath)
      copyFile <- paste0(sourcePath, " ", tmpPath)
  
      #pause to let docker catch up
      Sys.sleep(3)
  
      #copy files
      cmdToRun <- paste0("docker cp ",containerID, copyFile)
      try(
        dockerError <- system(cmdToRun)
      )
      
      #get name of files before we rename them so we can delete
      # them from the docker container that is running
      downloaded_files <- list.files(tmpPath)
  
      #rename files in tmpPath folder with timestamp after each one
      copy_rename_files(tmpPath = tmpPath,
                        destPath = destPath,
                        appendName = append_to_name,
                        fileType = ".csv")
      
      #loop through all files in tempDirectory and remove
      for (file in downloaded_files){
        #delete downloaded files
        cmdToRun <- paste0('docker exec ',
                           containerID,
                           ' rm -rf "',
                           substr(sourcePath, 2, nchar(sourcePath) -1 ),
                           file,
                           '"')
        try(
          dockerError <- system(cmdToRun)
        )
      }
    }

    Sys.sleep(2 + (3*runif(1)))
  }
}

#if old one still running, shut it down; we do this to make sure there are no lingering files
containerID <- system("docker container ls", intern = TRUE)
if (length(containerID) >= 2) {
  #loop through all and kill off anything on port 4445
  
  containerID <- containerID[2:length(containerID)]
  for (row_no in length(containerID)) {
    if (grepl("0.0.0.0:4445->4444", containerID[row_no])) {
      ID <- strsplit(containerID, split="        ")[[row_no]][1]
      
      #stop and kill container
      dockerStop <- system(paste0("docker stop ", ID), intern = TRUE)
      dockerRM <- system(paste0("docker rm ", ID), intern = TRUE)
      
    }
  }

}

#start a new container
startDocker <- system("docker run -d -p 4445:4444 selenium/standalone-chrome", intern = TRUE)
containerID <- system("docker container ls", intern = TRUE)
containerID <- strsplit(containerID, split="        ")[[2]][1]

Sys.sleep(3)

#Connect to docker container 
remDr <- RSelenium::remoteDriver(remoteServerAddr = "localhost",
                                 port = 4445L,
                                 browserName = "chrome")
remDr$open()


clicks <- read_excel("C:\\Box Sync\\R-scripts\\scraper\\click_automation\\clicks1.xlsx", sheet="url")
destination <- "C:\\Users\\keith_bailey\\Documents\\MarketData2\\"

for (df_row in  1:nrow(clicks)){
  download_files(remote_selenium = remDr,
                 clicks_file = clicks[df_row,],
                 append_to_name = clicks$append_to_name[df_row],
                 destPath = destination,
                 screenshotLogging = TRUE)
  
}

#stop and kill container
dockerStop <- system(paste0("docker stop ", containerID), intern = TRUE)
dockerRM <- system(paste0("docker rm ", containerID), intern = TRUE)
if (dockerRM != containerID){
  print("docker not shut down properly")
}
system("docker container ls")
