library(here)
library(reliabilitydiag)
library(doParallel)
library(dplyr)

source(here("replication_supplement/rel_diag_classic.R"))

# Multiple hours of runtime.
# Only run if necessary to confirm reproducibility.

M <- 1000
n.set <- 2^seq(6,13)
k.set <- c(10, 50, Inf)
alpha.set <- c(1)

dist.x.set <- c("unif", "rectangular", "beta-unif")
ratio.beta.unif <- 4
beta.param.2 <- 10

bins.list <- list(5,10,50,"Q-n(1/6)","Q-n(2/6)","Q-n(3/6)")

core.max <- 70
cl <- makeCluster(min(parallel::detectCores()-1, M, core.max) )
registerDoParallel(cl)
start.time <- Sys.time()
res.df.MC <- foreach(
  i_MC = 1:M,
  .combine=rbind,
  .packages=c("RelDiag", "dplyr", "tibble"),
  .export=c("rel.diag.classic")
)%dopar%{
  set.seed(i_MC) # set seed for reproducibility
  res.df <- tibble()

  for (n in n.set){
    for (k in k.set){
      for (dist.x in dist.x.set){
        if (k==Inf){
          if (dist.x=="rectangular"){
            x <- 1/3*(sqrt(15*runif(n)+1) - 1)
          } else if (dist.x=="beta-unif") {
            x <- c(
              rbeta(floor(n*(ratio.beta.unif-1)/ratio.beta.unif),1,beta.param.2),
              runif(ceiling(n/ratio.beta.unif)))
          } else {
            x <- runif(n)
          }
        } else {
          if (dist.x=="rectangular"){
            prob.unnormalized <- seq(1,4,length.out=k)
            prob <- prob.unnormalized/sum(prob.unnormalized)
            x <-(sample(1:k, n, replace=TRUE, prob=prob) - 0.5)/k
          } else if (dist.x=="beta-unif") {
            pdf <- (ratio.beta.unif-1)/ratio.beta.unif *
              dbeta( ((1:k)-0.5)/k ,1,beta.param.2) +
              1/ratio.beta.unif * dunif(((1:k)-0.5)/k)
            prob <- pdf/sum(pdf)
            x <- (sample(1:k, n, replace=TRUE, prob=prob) - 0.5)/k
          } else {
            x <- (sample(1:k, n, replace=TRUE) - 0.5)/k
          }
        }

        for (alpha in alpha.set){
          p <- x^alpha
          y <- rbinom(n, 1, p)

          # PAV Reliability Diagram
          rel <- reliabilitydiag(X=p, y=y, region.level = NA)
          CEP.df <- with(rel$X, merge(cases, bins, by.x="bin_id"))
          CEP.df <- CEP.df %>% mutate(CEPtrue = x^alpha)
          MSE <- with(CEP.df, mean((CEP_pav-CEPtrue)^2))

          if (!is.null(MSE)){
            res.df <- rbind(
              res.df,
              tibble(
                Measure="MSE",
                RelDiag.Type="PAV",
                MC.rep=i_MC,
                n=n,
                m.bins="PAV",
                alpha=alpha,
                dist.x=dist.x,
                k=k,
                Value=MSE))
          }

          # "Classic" Reliability Diagrams
          for (bins.index in 1:length(bins.list)){

            if (class(bins.list[[bins.index]]) == "numeric"){
              m.bins <- bins.list[[bins.index]]
            } else if (bins.list[[bins.index]] == "n(1/6)") {
              m.bins <- floor(n^(1/6))
            } else if (bins.list[[bins.index]] == "n(2/6)") {
              m.bins <- floor(n^(2/6))
            } else if (bins.list[[bins.index]] == "n(3/6)") {
              m.bins <- floor(n^(3/6))
            } else if (bins.list[[bins.index]] == "n(4/6)") {
              m.bins <- floor(n^(4/6))
            } else if (bins.list[[bins.index]] == "Q-n(1/6)") {
              bins.amount <- max(3,floor(n^(1/6)))
              m.bins <- unique(
                c(0,quantile(x, (1:(bins.amount-1))/bins.amount),1)
              )
            } else if (bins.list[[bins.index]] == "Q-n(2/6)") {
              bins.amount <- max(3,floor(n^(2/6)))
              m.bins <- unique(
                c(0,quantile(x, (1:(bins.amount-1))/bins.amount),1)
              )
            } else if (bins.list[[bins.index]] == "Q-n(3/6)") {
              bins.amount <- max(3,floor(n^(3/6)))
              m.bins <- unique(
                c(0,quantile(x, (1:(bins.amount-1))/bins.amount),1)
              )
            }

            RelDiag.Bins <- tryCatch(
              rel.diag.classic(y, x, bins=m.bins),
              error=function(e) NULL)
            df <- with(RelDiag.Bins, merge(df, df.bins, by="bin.index")) %>%
              as.tibble() %>%
              arrange(FC)
            CEP.df.classic <- df %>%
              summarize(x = FC, CEPtrue =x^alpha, CEP.est = bin.freq )
            MSE.classic <- with(CEP.df.classic, mean((CEP.est-CEPtrue)^2))

            if (!is.null(RelDiag.Bins)){
              if (class(bins.list[[bins.index]])=="numeric"){
                res.df <- rbind(
                  res.df,
                  data.frame(
                    Measure="MSE",
                    RelDiag.Type="Bins.fixed",
                    MC.rep=i_MC,
                    n=n,
                    m.bins=as.character(bins.list[[bins.index]]),
                    alpha=alpha,
                    dist.x=dist.x,
                    k=k,
                    Value=MSE.classic))
              } else if (class(bins.list[[bins.index]])=="character" &
                         substring(bins.list[[bins.index]],1,1)=="Q"){
                res.df <- rbind(
                  res.df,
                  data.frame(
                    Measure="MSE",
                    RelDiag.Type="Bins.Q.n",
                    MC.rep=i_MC,
                    n=n,
                    m.bins=substring(bins.list[[bins.index]],3),
                    alpha=alpha,
                    dist.x=dist.x,
                    k=k,
                    Value=MSE.classic))
              } else {
                res.df <- rbind(
                  res.df,
                  data.frame(
                    Measure="MSE",
                    RelDiag.Type="Bins.n",
                    MC.rep=i_MC,
                    n=n,
                    m.bins=as.character(bins.list[[bins.index]]),
                    alpha=alpha,
                    dist.x=dist.x,
                    k=k,
                    Value=MSE.classic))
              }
            }
          }
        }
      }
    }
  }

  res.df
}
stopCluster(cl)
end.time <- Sys.time()
(run.time <- end.time-start.time)

saveRDS(
  res.df.MC,
  file = here(
    "replication_paper/data/sim_Rel_Efficiency_MainArticle_20201015.rds"
  )
)
