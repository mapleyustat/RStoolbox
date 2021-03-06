% Generated by roxygen2 (4.1.0): do not edit by hand
% Please edit documentation in R/unsuperClass.R
\name{unsuperClass}
\alias{unsuperClass}
\title{Unsupervised Classification}
\usage{
unsuperClass(img, nSamples = 1000, nClasses = 5, nStarts = 25,
  clusterMap = TRUE, algorithm = "Hartigan-Wong", ...)
}
\arguments{
\item{img}{Raster* object.}

\item{nSamples}{integer. Number of random samples to draw to fit cluster map. Only relevant if clusterMap = FALSE.}

\item{nClasses}{integer. Number of classes.}

\item{nStarts}{integer. Number of random starts for kmeans algorithm.}

\item{clusterMap}{logical. Fit kmeans model to a random subset of the img (see Details).}

\item{algorithm}{character. \link[stats]{kmeans} algorithm. One of c("Hartigan-Wong", "Lloyd", "MacQueen")}

\item{...}{further arguments to be passed to \link[raster]{writeRaster}, e.g. filename}
}
\description{
Unsupervised clustering of Raster* data using kmeans clustering
}
\details{
Clustering is done using stats::kmeans. This can be done for all pixels of the image (clusterMap=FALSE), however this can be slow and is
not memory safe. Therefore if you have large raster data (> memory), as is typically the case with remote sensing imagery it is adviseable to choose clusterMap=TRUE (the default).
This means that a kmeans cluster map is calculated based on a random subset of pixels (nSamples). Then the distance of *all* pixels to the cluster centers
is calculated in a stepwise fashion using raster::predict. Class assignment is based on minimum distance to the cluster centers.
}
\examples{
input <- brick(system.file("external/rlogo.grd", package="raster"))

## Plot
olpar <- par(no.readonly = TRUE) # back-up par
par(mfrow=c(1,2))
plotRGB(input)

## Run classification
set.seed(25)
unC <- unsuperClass(input, nSamples = 100, nClasses = 5, nStarts = 5)
unC

## Plots
colors <- rainbow(5)
plot(unC$map, col = colors, legend = FALSE, axes = FALSE, box = FALSE)
legend(1,1, legend = paste0("C",1:5), fill = colors,
       title = "Classes", horiz = TRUE,  bty = "n")

par(olpar) # reset par
}

