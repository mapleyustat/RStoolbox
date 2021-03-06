#' Topographic Illumination Correction
#' 
#' @param img Raster*. Imagery to correct
#' @param dem Raster*. Either a digital elevation model as a RasterLayer or a RasterStack/Brick with pre-calculated slope and aspect (see \link[raster]{terrain}) in which case the layers must be named 'slope' and 'aspect'.
#' @param metaData Character, ImageMetaData. Either a path to a Landsat meta-data file (MTL) or an ImageMetaData object (see \link{readMeta}) 
#' @param solarAngles Numeric vector containing sun azimuth and sun zenith (in radians and in that order). Not needed if metaData is provided   
#' @param method Character. One of c("cos", "avgcos", "minnaert", "C", "stat", "illu"). Choosing 'illu' will return only the local illumination map.
#' @param stratMethod Character. One of c("noStrat", "stratEqualBins", "stratQuantiles").
#' @param stratImg RasterLayer by which to stratify by, e.g. NDVI. Defaults to 'slope'
#' @param nStrat Integer. Number of bins or quantiles to stratify by. If a bin has less than 50 samples it will be merged with the next bin.
#' @param illu Raster*. Optional pre-calculated ilumination map. Run topCor with method="illu" to calculate one.
#' @export 
topCor <- function(img, dem, metaData, solarAngles, method = "C", stratImg, stratMethod = "noStrat", nStrat = 5, illu){
    
    stopifnot(method %in% c("cos", "avgcos", "minnaert", "C", "stat", "illu"), stratMethod %in% c("stat", "noStrat", "stratEqualBins", "stratQuantiles"))
    
    ## Metadata 
    if(!missing("solarAngles")) {
        if(length(solarAngles)!=2) stop ("If metaData is used to provide solar azimuth and solar zenith it must be a numeric vector of length 2: c(azimuth, zenith)")
        sa <- solarAngles[1]
        sz <- solarAngles[2]
    } else { 
        if(missing("metaData")) stop("You must specify either solarAngles or metaData")
        if(inherits(metaData, "character"))   metaData <- readMeta(metaData)
        sz <- (90-metaData$SOLAR_PARAMETERS[2])*pi/180
        sa <-  metaData$SOLAR_PARAMETERS[1]*pi/180        
    }  
    
    ## Terrain
    if(any(!names(dem) %in% c("slope", "aspect"))) {
        compareRaster(img, dem)
        .vMessage("Calculate slope and aspect")
        topo <- terrain(dem, c("slope", "aspect"))
    } else {
        compareRaster(img, illu)
        .vMessage("Using pre-calculated slope and aspect")
    }
    slope <- topo[["slope"]]
    aspect <- topo[["aspect"]]
    
    ## Illumination
    if(missing(illu)){
        .vMessage("Calculate illumination map")
        illu  <- raster::overlay(topo, fun = function(slope, aspect, sazimuth = sa, szenith = sz){
                    cos(szenith) * cos(slope) + sin(szenith) * sin(slope) * cos(sazimuth - aspect)
                })
        names(illu) <- "illu"
    } else {
        .vMessage("Using pre-calculated illumination map")
    }
    if(method=="illu") return(illu)
    
    .vMessage("Correct imagery")
    if (method == "cos") {
        ## valid range: <55°
        ## Eq 3 in Riano2003
        ## Lambertian assumption
        return(Lh <- img * (cos(sz) / illu))  
    }
    if (method == "avgcos") {
        ## Eq 4 in Riano2003
        ## Lambertian assumption
        avgillu <- cellStats(illu, mean)
        return(Lh <- img + img * (avgillu-illu) / avgillu)  
    }
    if(method =="minnaert") {
        ## Eq 5 in Riano2003
        ## Lambertian assumption if k == 1
        ## Non-lambertian if 0 <= k < 1   
        if(missing(stratImg)) {stratImg <- "slope"}
        ks <- .kestimate(img, illu, slope, method = stratMethod, stratImg = stratImg, n = nStrat, sz=sz)
        
        ks$k <- lapply(ks$k, function(x){
                    x[x[,2] < 0, 2] <- 0
                    x[x[,2] > 1, 2] <- 1
                    x
                })
        Lh <- lapply(1:nlayers(img), function(layer){ overlay(stack(img[[layer]], illu, slope), fun = function(img, illu, strat, groups = ks$groups, k = ks$k) {
                                sc <- cut(strat, breaks = groups, labels = FALSE)
                                k <- k[[layer]][sc,2]       
                                Lh <- img * c(cos(sz)/ illu)^k 
                            })
                })
        Lh <- stack(Lh)       
        names(Lh) <- names(img)
        
        return(Lh)
    }    
    if(method ==  "stat") {
        ## Eq 8 in Riano2003        
        ks <- .kestimate(img, illu, slope, method = "stat")
        sub <- stack(lapply(ks$k, function(x){
                            x[,2] * illu
                        }))
        return(Lh <- img - sub)
    }
    if(method == "C") {
        ks <- .kestimate(img, illu, slope, method = "stat")
        mult <- stack(lapply(ks$k, function(x){
                            ck <- x[,1]/x[,2] 
                            (cos(sz) + ck) /  (illu + ck)
                        })) 
        return(Lh <-  img * mult)   
    }
    if(FALSE && method == "minnaMod"){
        ## Richter 2009
        if(sz < 45*pi/180) {
            beta_t <- sz + 20*pi/180
        } else if(sz > 55*pi/180) {
            beta_t <- sz + 10*pi/180        
        } else {
            beta_t <- sz + 15*pi/180
        }
        
        ## Vegetation classes: 1 = non-veg, 2 = veg
        bvis = c(0.5,  ## non-vegetation
                3/4)  ## vegetation (wavelength < 720nm)
        bir = c(0.5,  ## non-vegetation
                1/3)  ## vegetation (wavelength > 720nm)
   
        minnaMod <- function(x, beta_tx, b_lut) {
            b 	 <- b_lut[x[,2]]
            mult <- (x[,1]/beta_tx)^b
            mult[mult > 0.25] <- 0.25
            mult
        }
        
     multvis <- calc(stack(illu, stratImg), fun = function(x) minnaMod(x, b_lut = bvis, beta_tx = beta_t))
     multir  <- calc(stack(illu, stratImg), fun = function(x) minnaMod(x, b_lut = bir, beta_tx = beta_t))
      
     select <- illu > beta_t 
     visBands <- 1:4    
     visCo <- img[visBands]
     visCo[select] <- img[[visBands]][select]  * multvis[select]
    }
        
}



#' Parameter estimation
#' @noRd 
#' @keywords internal
.kestimate <- function(img, illu, slope, stratImg = "slope", method = "noStrat", n = 5, minN = 50, sz) {
    
    stopifnot(method %in% c("stat", "noStrat", "stratEqualBins", "stratQuantiles"))
    ## Following Lu 2008 sample pre selection
    set.seed(10)
    strat <- if(inherits(stratImg, "character")) NULL else {names(stratImg) <- "strat"; stratImg} 
    sr 	  <- as.data.frame(sampleRandom(stack(img, illu, slope, strat), size = 10000))
    
    if(method != "stat") sr  <- sr[sr$slope > 2*pi/180 & sr$illu >= 0,]
    if(method != "noStrat" & inherits(stratImg, "character")) {
        sr$strat <- sr[,stratImg]
        stratImg <- slope
    }
    
    if(method %in% c("stat","noStrat")){
        groups <- 0:1
        assoc <- rep(1, length(nrow(sr)))
    } else {
        .vMessage("Begin strafification")
        if(method == "stratQuantiles") {
            ## Quantile method
            groups <- quantile(stratImg, probs = 0:n/n)
        } 
        if(method == "stratEqualBins") {
            ## Equal method
            mi <- minValue(stratImg)
            ma <- maxValue(stratImg)
            groups <- seq(mi, ma, by = (ma - mi)/n)
        }    
        assoc  <- cut(sr$strat, breaks = groups, labels = FALSE, include.lowest = TRUE)
        gMax   <- tail(groups, 1)
        gMin   <- groups[1]
        tab    <- tabulate(assoc, nbins = (length(groups)-1))
        tooFew <- which(tab < minN) + 1
        while(length(tooFew)){
            tooFew[tooFew == 1] <- 2
            tooFew[tooFew == length(groups)] <- length(groups) -1
            groups <- groups[-tooFew]
            groups <- unique(c(gMin, groups, gMax))
            assoc  <- cut(sr$strat, breaks = groups, labels = FALSE, include.lowest = TRUE)
            tab    <- tabulate(assoc, nbins = (length(groups)-1))
            tooFew <- which(tab < minN) + 1
        }           
    }
    .vMessage("Estimate coefficients")
    x 	<- if(method == "stat") sr$illu else log(sr$illu/cos(sz))
    kl <- lapply(1:nlayers(img), function(i){
                if(method == "stat") {
                    y <- sr[,i] 
                } else {
                    stz <- sr[,i] < 0
                    if(any(stz)) {
                        warning("Resetting negative reflectances to zero!", call.=FALSE)
                        sr[stz,i] <- 1e-32
                    } 
                    sr[sr[,i] == 0,i] <- 1e-32
                    y <- log(sr[,i])
                }
                k <- lapply(1:(length(groups)-1), function(g){
                            select <- assoc == g
                            mod <- lm(y[select] ~ x[select])
                            k <- coefficients(mod)                            
                        })
                do.call("rbind", k)
            })
    return(list(groups = groups, k = kl))
}

