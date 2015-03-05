#' Linear image normalization 
#' 
#' performs linear shifts of value ranges either to match another image
#' or to any other min and max value.
#' 
#' @param x Raster* object. Image to normalise.
#' @param y Raster* object. Reference image.
#' @param xmin Numeric. Min value of x.
#' @param xmax Numeric. Max value of x.
#' @param ymin Numeric. Min value of y.
#' @param ymax Numeric. Max value of y.
#' @param forceMinMax Logical. Forces update of min and max data slots in x or y.
#' 
#' @seealso \link{histMatch}
#' @export
normImage <- function(x, y, xmin, xmax, ymin, ymax, forceMinMax = FALSE) {
    if(forceMinMax)  x <- setMinMax(x)
    if(!missing(y) && forceMinMax)  y <- setMinMax(y)
    if(missing("ymin")) ymin <- y@data@min
    if(missing("ymax")) ymax <- y@data@max
    if(missing("xmin"))	xmin <- x@data@min 
    if(missing("xmax")) xmax <- x@data@max
    scal <- (ymax - ymin)/(xmax-xmin) 
    .paraRasterFun(x, rasterFun = calc,  args = list(fun = function(x) {(x - xmin) * scal + ymin}))      
}              