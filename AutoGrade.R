library("jpeg")
library("RCurl")
library("fields")


hue2rgb <- function(p, q, t)
{
  t[t<0] <- t[t<0] + 1
  t[t>1] <- t[t>1] - 1
  return.value <- p
  return.value[t<(1/6)] <- (p+(q-p)*6*t)[t<(1/6)]
  return.value[t<(1/2) & t>=(1/6)] <- (q)[t<(1/2) & t>=(1/6)]
  return.value[t<(2/3) & t>=(1/2)] <- (p+(q-p)*(2/3-t)*6)[t<(2/3) & t>=(1/2)]
  return(return.value)
}

hsl2rgb <- function(hsl)
{
  h <- hsl[,1]
  s <- hsl[,2]
  l <- hsl[,3]
  q = ifelse(l < 0.5, l * (1 + s), l + s - l * s)
  p = 2 * l - q
  r <- hue2rgb(p,q,h+1/3)
  g <- hue2rgb(p,q,h)
  b <- hue2rgb(p,q,h-1/3)
  return(cbind(r,g,b))
}

rgb2hsl <- function(rgb)
{
  max <- apply(rgb,1,function(x)x[which.max(x)])
  min <- apply(rgb,1,function(x)x[which.min(x)])
  h <- s <- l <- (max + min) / 2
  
  h[max==min] <- s[max==min] <- 0

  d <- max - min
  s[l > 0.5] <- (d / (2 - max - min))[l > 0.5]
  s[l <= 0.5] <- (d / (max + min))[l <= 0.5]
  s[is.na(s)] <- ((max+min)/2)[is.na(s)]
  
  h[max==rgb[,1]] <- ((rgb[,2] - rgb[,3]) / d + (ifelse(rgb[,2] < rgb[,3], 6, 0)))[max==rgb[,1]]
  h[max==rgb[,2]] <- ((rgb[,3] - rgb[,1]) / d + 2)[max==rgb[,2]]
  h[max==rgb[,3]] <- ((rgb[,1] - rgb[,2]) / d + 4)[max==rgb[,3]]
  h[is.na(h)] <- ((max+min)/2)[is.na(h)]
  h <- h/6
  
  return(cbind(h, s, l))
}

getMatch <- function(k1, k2, l, iter)
{
  n.col <- nrow(k1)
  match.vec <- apply(rdist(k1, k2),1,which.min)
  match.vec[duplicated(match.vec)] <- setdiff(1:n.col, match.vec)
  for(ii in 1:iter)
  {
    n.sample <- sample(seq(2,round(n.col/2),by=2),1)
    switch.ind <- sample(1:n.col, n.sample)
    match.vec.cand <- match.vec
    match.vec.cand[switch.ind] <- match.vec.cand[rev(switch.ind)]
    current.mse <- mean((k1[match.vec]-k2)^l)
    cand.mse <- mean(abs((k1[match.vec.cand]-k2))^l)
    if(cand.mse < current.mse)
    {
      match.vec <- match.vec.cand
    }
  }
  k1 <- k1[match.vec,]
  translation.matrix <- k1-k2
  return(list(k1=k1,k2=k2,match.vec=match.vec,translate.matrix=translation.matrix))
}

paletteMatch <- function(image1,image2,n.col=10,l=2,weight.exp=1,iter=100,luminance=T,saturation=T,match.original=F)
{
  image1.temp <- image1
  image1 <- image1[round(seq(1,nrow(image1),length.out=50)),round(seq(1,ncol(image1),length.out=50)),]
  image2 <- image2[round(seq(1,nrow(image2),length.out=50)),round(seq(1,ncol(image2),length.out=50)),]
  col.1 <- apply(image1,3,as.vector)
  col.2 <- apply(image2,3,as.vector)
  k.1 <- kmeans(col.1,n.col)
  k.2 <- kmeans(col.2,n.col)
  match.vec <- getMatch(k.1$centers, k.2$centers, l, iter)
  
  image1 <- image1.temp
  col.1 <- apply(image1,3,as.vector)
  weights <- rdist(col.1, k.1$centers)^weight.exp
  weights <- (weights^-1)/rowSums(weights^-1)
  r.shift <- weights %*% match.vec$translate.matrix[,1]  
  g.shift <- weights %*% match.vec$translate.matrix[,2]
  b.shift <- weights %*% match.vec$translate.matrix[,3]

  col.new <- col.1
  new.1 <- image1.temp
  col.new[,1] <- col.new[,1]-r.shift
  col.new[,2] <- col.new[,2]-g.shift
  col.new[,3] <- col.new[,3]-b.shift
  col.new[col.new<0] <- 0
  col.new[col.new>1] <- 1
  
  if(luminance==T | saturation==T)
  {
    hsl.new <- rgb2hsl(col.new)
  }
  if(luminance==T)
  {
    hsl.1 <- rgb2hsl(col.1)
    hsl.new[,3] <- hsl.1[,3]
  }
  if(saturation==T)
  {
    hsl.2 <- rgb2hsl(col.2)
    hsl.2.mean <- mean(hsl.2[,2])
    hsl.2.sd <- sd(hsl.2[,2])
    hsl.new.mean <- mean(hsl.new[,2])
    hsl.new.sd <- sd(hsl.new[,2])
    hsl.new[,2] <- hsl.new[,2] - hsl.new.mean
    hsl.new[,2] <- hsl.new[,2] / hsl.new.sd * hsl.2.sd
    hsl.new[,2] <- hsl.new[,2] + hsl.2.mean
  }
  if(luminance==T | saturation==T)
  {
#     col.new <- t(apply(hsl.new,1,function(x)hsl2rgb(x[1],x[2],x[3])))
    col.new <- hsl2rgb(hsl.new)
  }

  new.1[,,1] <- col.new[,1]
  new.1[,,2] <- col.new[,2]
  new.1[,,3] <- col.new[,3]
  new.1[new.1>1] <- 1
  new.1[new.1<0] <- 0

  
  return(list(new.1, match.vec))
}

plotPalette <- function(image1,image2, ...)
{
  match.image.1 <- paletteMatch(image1,image2, ...)
  match.image.2 <- paletteMatch(image2,image1, ...)
  n.col <- length(match.image.1[[2]]$match.vec)
  plot(0,0,type="n",
       xlab="",ylab="",main="",
       xaxt="n",yaxt="n",frame=F,
       xaxs="i",yaxs="i",
       xlim=c(0,12),ylim=c(0,n.col))
  rasterImage(image1,0,n.col/2,5,n.col)
  rasterImage(match.image.1[[1]],7,n.col/2,12,n.col)
  rasterImage(match.image.2[[1]],0,0,5,n.col/2)
  rasterImage(image2,7,0,12,n.col/2)
  
  rect(rep(5,n.col),0:(n.col-1),rep(6,n.col),1:n.col,border=rgb(match.image.1[[2]]$k1),col=rgb(match.image.1[[2]]$k1))
  rect(rep(6,n.col),0:(n.col-1),rep(7,n.col),1:n.col,border=rgb(match.image.1[[2]]$k2),col=rgb(match.image.1[[2]]$k2))
}

img.1 <- readJPEG("D:/users/ben/downloads/frozen.jpg")
img.2 <- readJPEG("D:/users/ben/downloads/wes.jpg")

par(mar=c(0,0,0,0))
plotPalette(img.1,img.2,n.col=6,l=1,weight.exp=1/30,iter=1000,luminance=F,saturation=F)

