#' Unsupervised Classification
#' 
#' Unsupervised clustering of Raster* data using kmeans clustering
#' 
#' Clustering is done using stats::kmeans. This can be done for all pixels of the image (clusterMap=FALSE), however this can be slow and is
#' not memory safe. Therefore if you have large raster data (> memory), as is typically the case with remote sensing imagery it is adviseable to choose clusterMap=TRUE (the default).
#' This means that a kmeans cluster map is calculated based on a random subset of pixels (nSamples). Then the distance of *all* pixels to the cluster centers 
#' is calculated in a stepwise fashion using raster::predict. Class assignment is based on minimum distance to the cluster centers.   
#' 
#' @param img Raster* object. 
#' @param nSamples integer. Number of random samples to draw to fit cluster map. Only relevant if clusterMap = FALSE.
#' @param nClasses integer. Number of classes.
#' @param nStarts  integer. Number of random starts for kmeans algorithm.
#' @param clusterMap logical. Fit kmeans model to a random subset of the img (see Details).
#' @param algorithm character. \link[stats]{kmeans} algorithm. One of c("Hartigan-Wong", "Lloyd", "MacQueen")
#' @param ... further arguments to be passed to \link[raster]{writeRaster}, e.g. filename
#' @export
#' @examples 
#' input <- brick(system.file("external/rlogo.grd", package="raster"))
#' 
#' ## Plot 
#' olpar <- par(no.readonly = TRUE) # back-up par
#' par(mfrow=c(1,2))
#' plotRGB(input)
#' 
#' ## Run classification
#' set.seed(25)
#' unC <- unsuperClass(input, nSamples = 100, nClasses = 5, nStarts = 5)
#' unC
#' 
#' ## Plots
#' colors <- rainbow(5)
#' plot(unC$map, col = colors, legend = FALSE, axes = FALSE, box = FALSE)
#' legend(1,1, legend = paste0("C",1:5), fill = colors,
#'        title = "Classes", horiz = TRUE,  bty = "n")
#' 
#' par(olpar) # reset par
unsuperClass <- function(img, nSamples = 1000, nClasses = 5, nStarts = 25, clusterMap = TRUE, algorithm = "Hartigan-Wong", ...){      
    if(atMax <- nSamples > ncell(img)) nSamples <- ncell(img)
    wrArgs <- list(...)
   
    if(!clusterMap | atMax && canProcessInMemory(img, n = 2)){
        trainData <- img[]
        complete  <- complete.cases(trainData)
        model     <- kmeans(trainData[complete,], centers = nClasses, nstart = nStarts, algorithm = algorithm)
        out   <- raster(img)
        out[] <- NA
        out[complete] <- model$cluster      
        if("filename" %in% names(wrArgs)) out <- writeRaster(out, ...)
    } else {
        if(!clusterMap) warning("Raster is > memory. Resetting clusterMap to TRUE")
        trainData <- sampleRandom(img, size = nSamples, na.rm = TRUE)
        model     <- kmeans(trainData, centers = nClasses, nstart = nStarts, algorithm = algorithm)
        out 	  <- .paraRasterFun(img, rasterFun=raster::predict, args = list(model=model, na.rm = TRUE), wrArgs = wrArgs)
    }
    structure(list(call = match.call(), model = model, map = out), class = c("unsuperClass", "RStoolbox"))
}

#' Predict method for kmeans objects
#' 
#' Prediction for kmeans models based on minimum distance to cluster centers
#' 
#' @param object \link[stats]{kmeans} object
#' @param newdata matrix 
#' @param ... further arguments. None implemented.
#' @method predict kmeans
#' @export 
predict.kmeans <- function(object, newdata, ...){
    stopifnot(colnames(newdata) %in% colnames(object$centers)) 
    newdata <- as.matrix(newdata)
    whichColMinC(newdata, centers=object$centers)
}


#' @method print unsuperClass
#' @export 
print.unsuperClass <- function(x, ...){
    cat("unsuperClass results\n")    
    cat("\n*************** Map ******************\n")
    cat("$map\n")
    show(x$map)
}


