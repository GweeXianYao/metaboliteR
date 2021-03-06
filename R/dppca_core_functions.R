# DPPCA Method -------------------------------------------------------------

#' @importFrom stats sd rnorm dnorm runif quantile
#' @importFrom msm rtnorm
#' @importFrom mvtnorm rmvnorm dmvnorm
#' @importFrom LearnBayes rigamma
#' @import brms
#' @importFrom tidyr gather
#' @importFrom MCMCpack procrustes

#  Data  -------------------------------------------------------------

pareto_scale = function(index,data){
  data_scaled<- sweep(data[[index]],2,colMeans(data[[index]]),"-")
  data_scaled <- sweep(data_scaled,2,sqrt(apply(data_scaled,2,sd)),"/")
  out = list();
  out[[paste0("M",index)]] <- data_scaled
  return(out)
}

ppca_initial_values = function(index, q, data){
  ppca = PPCA(data[[index]], q_min = q, q_max = q)
  Sig = ppca$sigma2
  U = ppca$score$score
  H =diag( diag(var(t(ppca$score$score)) ))
  W = ppca$loadings
  output = list(Sig = Sig,
                U = U, H=H, W=W)
  return(output)
}


#  Gibbs U -------------------------------------------------------------
gibbs_U = function(data, eta, W, H){

  M = length(data)
  Sig <- exp(eta)

  single_U = function(m,W,Sig,H,data){

    n = nrow(data[[1]])
    q = dim(W[[1]])[2]

    v.u <- solve((t(W[[m]])%*%W[[m]])/Sig[m] + solve(H[[m]]))
    m.u <- v.u%*%(t(W[[m]])%*%t(data[[m]]))/Sig[m]
    U<- t(rmvnorm(n, rep(0, q), v.u)) + m.u;
    return(list(U=U))
  }

  U = sapply(seq(1,M,1), single_U, W, Sig, H, data)
  return(U)

}

#  Gibbs W -------------------------------------------------------------

gibbs_W = function(data, eta, omega_inv, U){

  M = length(data)
  Sig <- exp(eta)

  single_W = function(m, omega_inv, U, Sig, data){

    p = ncol(data[[1]]); q = dim(U[[1]])[1]

    v.l <- solve(omega_inv[[m]] + (U[[m]]%*%t(U[[m]]))/Sig[m])
    m.l <- (v.l/Sig[m])%*%(U[[m]]%*%data[[m]])
    W<- rmvnorm(p, rep(0,q), v.l) + t(m.l)
    return(list(W=W))
  }

  W = sapply(seq(1,M,1), single_W, omega_inv, U, Sig, data)
  return(W)

}

#  M-H eta -------------------------------------------------------------

MH_eta = function(eta, U, W, v2, phi, nu, data, eta_accept){

  M = length(W); n = nrow(data[[1]]); p = ncol(data[[1]])

  single_eta = function(m,eta, U, W, v2, phi, nu, data, eta_accept){

    eta_current = eta[m]; eta_accept_current = eta_accept[m]

    e_im = function(m,U,W,data){
      data[[m]] - t(U[[m]])%*%t(W[[m]])}
    e = e_im(m,U,W,data)
    ete = sum(diag(e%*%t(e)))
    ete

    if(m ==1){
      b = v2
      a =  nu + phi*(eta[2] - nu)
    } else if(m ==M){
      b = v2
      a = nu + phi*(eta[m-1] - nu)
    } else{
      b = v2/(1+phi^2)
      a = nu + (phi*((eta[m-1] - nu) + (eta[m+1] - nu)))/(1 + phi^2)
    }

    d = (b^(-1) + 0.5*ete*exp(-a))^(-1)
    c = d*(a/b + (ete/2)*exp(-a)*(1+a) - (n*p)/2 )

    eta_new = rnorm(1, mean  =  c, sd = sqrt(d))

    logaccept1 <- sum(dmvnorm(e, rep(0, p), exp(eta_new)*diag(p),log=TRUE)) + dnorm(eta_new, a, sd = sqrt(b),log = TRUE) + dnorm(eta[m],c,sd = sqrt(d), log = TRUE)
    logaccept2 <- sum(dmvnorm(e, rep(0, p), diag(exp(eta[m]), nrow = p), log =TRUE)) + dnorm(eta[m], a, sd = sqrt(b), log = TRUE) + dnorm(eta_new,c,sd = sqrt(d), log = TRUE)

    logaccept <- logaccept1 - logaccept2
    if(log(runif(1)) <= logaccept) {
      eta_current <- eta_new
      eta_accept_current = eta_accept_current + 1
    }

    output = list(eta = eta_current, eta_accept = eta_accept_current)
    return(output)
  }

  out = sapply(seq(1,M,1), single_eta,eta, U, W, v2, phi, nu, data, eta_accept, simplify = FALSE)
  eta = unlist(lapply(out,"[[", "eta"))
  eta_accept =  unlist(lapply(out,"[[", "eta_accept"))

  return(list(eta = eta, accepted = eta_accept))

}

#  M-H lambda -------------------------------------------------------------

MH_lambda = function(lambda,mu,Phi,V,U, accept_lambda,data){

  M = length(data);

  gen_lambda_j = function(m, j, lambda, mu, Phi, U, data){

    M = length(data); n = nrow(data[[1]])

    if(m ==1){
      a = mu[j] + Phi[j]*(lambda[[m]][2] - mu[j])
      b = V[j]
    } else if(m ==M){
      a = mu[j] + Phi[j]*(lambda[[m-1]][j] - mu[j])
      b = V[j]
    } else{
      a = mu[j] + Phi[j]*(lambda[[m-1]][j] - mu[j] + lambda[[m+1]][j] - mu[j])/(1+Phi[j]^2)
      b = V[j]/(1+Phi[j]^2)
    }

    sum_uqm <- U[[m]][j,]%*%U[[m]][j,]

    d = (1/b + sum_uqm/2*exp(-a))^(-1)
    c = d*(a/b + 0.5*sum_uqm*exp(-a)*(1+a) - n/2)

    lambda_new = rnorm(1,c,sd = sqrt(d))

    #Accept or not accept the value:
    logaccept1 <- sum(dnorm(U[[m]][j,],0,sd = sqrt(exp(lambda_new)),log=TRUE)) + dnorm(lambda_new,a,sd = sqrt(b),log=TRUE) + dnorm(lambda[[m]][j],c,sd = sqrt(d),log=TRUE)
    logaccept2 <- sum(dnorm(U[[m]][j,],0,sd = sqrt(exp(lambda[[m]][j])),log=TRUE)) + dnorm(lambda[[m]][j],a,sd = sqrt(b),log=TRUE) + dnorm(lambda_new,c,sd = sqrt(d),log=TRUE)

    logaccept <- logaccept1 - logaccept2

    lambda <- lambda[[m]][j]; accept_lambda = accept_lambda[m,j]

    if(log(runif(1)) <= logaccept)
    {
      lambda <- lambda_new
      accept_lambda <- accept_lambda + 1
    }
    output = list(lambda = lambda, acception = accept_lambda)
    return(output)
  }

  q = dim(U[[1]])[1]
  l = mapply(gen_lambda_j, m = sort(rep(seq(1,M,1),q)), j = rep(seq(1,q,1), M), MoreArgs = list(lambda = lambda, mu =mu, Phi=Phi, U=U,data=data), SIMPLIFY = FALSE)

  ls = unlist(lapply(l, "[[", "lambda"))
  accepted = matrix(unlist(lapply(l, "[[", "acception")), nrow = M, ncol = q, byrow = TRUE)

  #put in the correct format
  list_lambda = function(l,q){
    linf = seq(1,length(l),q); lsup = linf+q-1
    l_list = sapply(seq(1,length(linf),1), function(k) list(l[linf[k]:lsup[k]]) )
    return(l_list)
  }

  lambda = list_lambda(ls, q)
  out = list(lambda = lambda, accepted = accepted)
  return(out)

}

#  Gibbs v2 -------------------------------------------------------------

gibbs_v2 = function(alpha, beta, eta, phi, nu){

  M = length(eta)

  alpha_star = (M+alpha)/2

  aux = sapply(seq(1,M-1,1), function(m) (eta[m+1]- phi*eta[m] - nu*(1-phi))^2 )
  aux = sum(aux)
  beta_star = 0.5*(beta+ (eta[1]-nu)^2*(1-phi^2) + aux)

  v2 = LearnBayes::rigamma(1, alpha_star, beta_star)
  return(v2)

}

#  Gibbs nu -------------------------------------------------------------

gibbs_nu = function(sigma2_nu, phi, eta, v2, data){
  M = length(data)
  sig.nu <- 1/(((M-1)*(1 - phi)*(1 - phi) + (1 - phi^2))/v2 + 1/sigma2_nu)
  num <- (1 + phi)*eta[1] + sum(eta[-1] - phi*eta[-M])
  den <- (1 + phi) + (M-1)*(1-phi) + v2/((1 - phi)*sigma2_nu)
  mu.nu <- num/den

  nu = rnorm(1, mu.nu,sqrt(sig.nu) )
  return(nu)
}

#  M-H phi -------------------------------------------------------------

MH_phi = function(mu_phi, sigma2_phi,eta, nu, v2, phi ,accept_phi){
  M = length(eta)

  aux = sapply(seq(1,M-1,1), function(m) (eta[m]- nu)^2 )
  aux = sum(aux)
  b = v2*sigma2_phi*((v2 - sigma2_phi*(eta[1] - nu)^2 + sigma2_phi*aux )^(-1))
  aux2 = sapply(seq(1,M-1,1), function(m) (eta[m+1]- nu)*(eta[m]-nu) )
  aux2 = sum(aux2)
  a = b*(1/v2)*(1/sigma2_phi)*(sigma2_phi*aux2 + v2*mu_phi)

  phi_new = msm::rtnorm(1, mean = a, sd =sqrt(b), lower=-1, upper =1)

  r = sqrt(1 - phi_new^2)/sqrt((1 - phi^2))

  if(runif(1) <= r)
  {
    phi <- phi_new
    accept_phi <- accept_phi+1
  }

  out = list(phi = phi, accepted = accept_phi)
  return(out)

}

#  Gibbs V -------------------------------------------------------------

gibbs_V = function(alpha_V,beta_V,lambda,Phi, mu){

  single_V = function(j,alpha_V,beta_V,lambda,Phi, mu){
    M = length(lambda)
    ll = unlist(lapply(lambda, "[[", j))

    A <- (alpha_V+M)/2
    ht <- ll[-1] - Phi[j]*ll[-M] - (1 - Phi[j])*mu[j]
    B <- (beta_V + (ll[1] - mu[j])*(ll[1] - mu[j])*(1 - (Phi[j]^2)) + t(ht)%*%ht)/2
    V <- rigamma(1,A,B)
    return(V)
  }
  q = length(lambda[[1]])
  V = sapply(seq(1,q,1), single_V, alpha_V, beta_V, lambda, Phi,mu)
  return(V)

}

#  Gibbs mu -------------------------------------------------------------

gibbs_mu = function(sigma2_mu, Phi,V,lambda){

  single_nu = function(j, sigma2_mu, Phi,V,lambda){

    M = length(lambda)
    ll = unlist(lapply(lambda, "[[", j))

    sig.mu <- 1/(((M-1)*(1 - Phi[j])*(1 - Phi[j]) + (1 - Phi[j]^2))/V[j] + 1/sigma2_mu)
    num <- (1 + Phi[j])*lambda[[1]][j] + sum(ll[-1] - Phi[j]*ll[-M])
    den <- (1 + Phi[j]) + (M-1)*(1 - Phi[j]) + V[j]/((1 - Phi[j])*sigma2_mu)
    mu.mu <- num/den
    mu <- rnorm(1, mu.mu, sqrt(sig.mu)); return(mu)

  }
  q = length(lambda[[1]])
  mu = sapply(seq(1,q,1),single_nu,sigma2_mu, Phi,V,lambda );
  return(mu)

}

#  M-H Phi -------------------------------------------------------------

MH_Phi = function(mu_Phi,sigma2_Phi, Phi, V, lambda, mu, accept_Phi){

  M = length(lambda)

  single_Phi = function(j, mu_Phi,sigma2_Phi,Phi, V, lambda, mu){

    Phi = Phi[j]
    accept_Phi = accept_Phi[j]

    ll = unlist(lapply(lambda, "[[", j))

    phi.sig <- (V[j]*sigma2_Phi)/(V[j] + sigma2_Phi*(t(ll[-M] - mu[j])%*%(ll[-M] - mu[j]) - (ll[1] - mu[j])*(ll[1] - mu[j])))

    phi.mu <- phi.sig * (sigma2_Phi*t(ll[-1] - mu[j])%*%(ll[-M] - mu[j]) + V[j]*mu_Phi)/
      (V[j]*sigma2_Phi)

    phi.star <- rtnorm(1,phi.mu, sqrt(phi.sig), lower=-1, upper=1)

    log.r <- (0.5*log(1 - (phi.star^2))) - (0.5*log(1- Phi^2 ))

    if(log(runif(1)) < log.r)
    {
      Phi <- phi.star
      accept_Phi <- accept_Phi + 1
    }

    out = list(Phi = Phi, accepted = accept_Phi);
    return(out)
  }
  q = length(lambda[[1]])
  out = sapply(seq(1,q,1), single_Phi, mu_Phi, sigma2_Phi,Phi, V, lambda, mu, simplify = FALSE)

  Phi = unlist(lapply(out, "[[", "Phi"))

  accepted = matrix(unlist(lapply(out, "[[", "accepted")), ncol =q)

  output = list(Phi=Phi, accepted = accepted)
  return(output)

}

#  Posterior manipulation  -------------------------------------------------------------

rotate_W_U = function(W_chain,U_chain, W_reference){

  chain_length = length(W_chain)      #element of original chain
  M = length(W_chain[[1]])            #multiple time points
  p = dim(W_chain[[1]][[1]])[1];
  q = dim(U_chain[[1]][[1]])[1]; n = dim(U_chain[[1]][[1]])[2];

  U_rotated = rep(list(rep(list(matrix(NA, nrow = n, ncol = q)),M)), chain_length)
  W_rotated = rep(list(rep(list(matrix(NA, nrow = q, ncol = p)),M)), chain_length)

  #rotation:
  for(i in 1:chain_length){
    for(m in 1:M){
      proc = MCMCpack::procrustes(W_chain[[i]][[m]],W_reference[[m]], translation=FALSE, dilation=FALSE)
      W_rotated[[i]][[m]] <- proc$X.new
      aux = c(t(proc$R)%*%(U_chain[[i]][[m]]))
      U_rotated[[i]][[m]] <- matrix(aux,ncol =q, byrow = FALSE)
    }
  }

  return(list(W_rotated = W_rotated, U_rotated = U_rotated))

}

posterior_U = function(m, rotated_U, post_burn_in, post_thin){

  #further burn in and thinning applied

  rotated_U = tail(rotated_U, -post_burn_in)
  rotated_U = rotated_U[ c( TRUE,rep(FALSE, post_thin)) ]

  U_m = lapply(rotated_U, "[[", m)
  U_post = apply(simplify2array(U_m), c(1,2), function(x) quantile(x, 0.5))

  return(list(U_post = U_post))
}

posterior_W = function(m, rotated_W, post_burn_in, post_thin){

  #further burn in and thinning applied

  rotated_W = tail(rotated_W, -post_burn_in)
  rotated_W = rotated_W[ c( TRUE,rep(FALSE, post_thin)) ]

  W_m = lapply(rotated_W, "[[", m)
  W_post = apply(simplify2array(W_m), c(1,2), function(x) quantile(x, 0.5))

  return(list(W_post = W_post))
}

rotate_post_scores=function(U_post, W_post){
  M = length(U_post)
  q = dim(U_post[[1]])[2]; n = dim(U_post[[1]])[1];
  U_post_rot = list(rep(matrix(NA, nrow = q, ncol = n),M))

  for(m in 1:M){
    template <- W_post[[1]]
    if(m==1){
      U_post_rot[[m]] <- t(U_post[[1]])
    } else {
      #res <- vegan::procrustes(W_post[[m]], template, translation=FALSE, dilation=FALSE)
      res <- MCMCpack::procrustes(W_post[[m]], template, translation=FALSE, dilation=FALSE)
      U_post_rot[[m]] <- t(res$R)%*%t(U_post[[m]])
    }
  }
  return(list(U_post_rot = U_post_rot))
}

sig_loadings = function(time, PC, W, cred_level){
  alpha = 1-cred_level
  W_m = lapply(W, "[[", time)

  W_inf = apply(simplify2array(W_m), c(1,2), function(x) quantile(x, alpha/2))
  W_upp = apply(simplify2array(W_m), c(1,2), function(x) quantile(x, 1-alpha/2))
  W_est = apply(simplify2array(W_m), c(1,2), function(x) quantile(x, 0.5))

  p = dim(W_est)[1]
  store_sig = list();
  for(i in 1:p){
    sig = ifelse((sign(W_inf[i, PC]) != sign(W_upp[i, PC])) == TRUE, 0, 1)
    if(sig ==1){
      store <- list(matrix(c(rownames(W_inf)[i], W_est[i, PC], W_inf[i, PC],  W_upp[i, PC]), nrow =1))
      store_sig = c(store_sig, store)
    }
  }

  store_sig = data.frame(matrix(unlist(store_sig), ncol = 4, byrow = TRUE))
  names(store_sig) = c("spectral_bin", "estimate", "lower", "upper")
  store_sig$estimate = as.numeric(as.character(store_sig$estimate))
  store_sig$lower = as.numeric(as.character(store_sig$lower))
  store_sig$upper = as.numeric(as.character(store_sig$upper))
  return(store_sig)
}

#  Fitting LMMs  -------------------------------------------------------------
fit_cubic = function(data_met, alpha){

  n = length(unique(data_met$individual))
  beta1_i = rep(NA,n)
  beta2_i = rep(NA,n)
  beta3_i = rep(NA,n)

  for(i in 1:n){
    data_i = data_met[data_met$individual==i,]
    lm = lm(measurement ~ -1 + time + time2 + time3,data = data_i)
    beta1_i[i] = lm$coefficients[1]
    beta2_i[i] = lm$coefficients[2]
    beta3_i[i] = lm$coefficients[3]
  }

  beta1_0 = mean(beta1_i); sigma1_0= sd(beta1_i)
  beta2_0 = mean(beta2_i); sigma2_0 = sd(beta2_i)
  beta3_0 = mean(beta3_i); sigma3_0 = sd(beta3_i)

  stanvar = stanvar(beta1_0 ,"beta1_0") +   stanvar(sigma1_0 ,"sigma1_0") +
    stanvar(beta2_0, "beta2_0") + stanvar(sigma2_0,"sigma2_0") +
    stanvar(beta3_0 ,"beta3_0") +   stanvar(sigma3_0 ,"sigma3_0")

  model3 <- brms::brm(data = data_met,
                      family = gaussian,
                      measurement ~ 1 + time + time2 + time3 + (1 | individual), # random intercept by individual
                      prior = c(prior_string("normal(0, 10)", class = "Intercept"),  #prior for the intercept
                                prior_string("normal(beta1_0, sigma1_0)", coef = "time"), #prior for betas
                                prior_string("normal(beta2_0, sigma2_0)", coef = "time2"), #prior for betas
                                prior_string("normal(beta3_0, sigma3_0)", coef = "time3"), #prior for betas
                                prior_string("cauchy(0, 1)", class = "sd"), #sd of random effects
                                prior_string("cauchy(0, 1)", class = "sigma")), #overall variability
                      iter = 10000, warmup = 500, chains = 1, cores = 1, thin = 10,
                      control = list(adapt_delta = .975, max_treedepth = 20),
                      seed = 190831, open_progress = FALSE, stanvars = stanvar)

  cubic = quantile(model3$fit@sim$samples[[1]][["b_time3"]], c(alpha/2, 1-alpha/2))
  sig_cube = as.numeric(sign(cubic[1]) == sign(cubic[2]))
  beta_cube = quantile(model3$fit@sim$samples[[1]][["b_time3"]], 0.5)
  beta_quad = quantile(model3$fit@sim$samples[[1]][["b_time2"]], 0.5)
  beta_lin = quantile(model3$fit@sim$samples[[1]][["b_time"]], 0.5)
  beta0 =  quantile(model3$fit@sim$samples[[1]][["b_Intercept"]], 0.5)
  return(list(significant = sig_cube,
              beta_cube = beta_cube,
              beta_quad = beta_quad,
              beta_lin = beta_lin,
              beta0 = beta0))
}

fit_squared = function(data_met, alpha){

  n = length(unique(data_met$individual))
  beta1_i = rep(NA,n); beta2_i = rep(NA,n)

  for(i in 1:n){
    data_i = data_met[data_met$individual==i,]
    lm = lm(measurement ~ -1 + time + time2,data = data_i)
    beta1_i[i] = lm$coefficients[1]
    beta2_i[i] = lm$coefficients[2]
  }

  beta1_0 = mean(beta1_i); sigma1_0= sd(beta1_i)
  beta2_0 = mean(beta2_i); sigma2_0 = sd(beta2_i)

  stanvar = stanvar(beta1_0 ,"beta1_0") +   stanvar(sigma1_0 ,"sigma1_0") +
          stanvar(beta2_0, "beta2_0") + stanvar(sigma2_0,"sigma2_0")

  model2 <- brms::brm(data = data_met,
                      family = gaussian,
                      measurement ~ 1 + time + time2  + (1 | individual), # random intercept by individual
                      prior = c(prior_string("normal(0, 10)", class = "Intercept"),  #prior for the intercept
                                prior_string("normal(beta1_0, sigma1_0)", coef = "time"), #prior for betas
                                prior_string("normal(beta2_0, sigma2_0)", coef = "time2"), #prior for betas
                                prior_string("cauchy(0, 1)", class = "sd"), #sd of random effects
                                prior_string("cauchy(0, 1)", class = "sigma")), #overall variability
                      iter = 10000, warmup = 500, chains = 1, cores = 1, thin = 10,
                      control = list(adapt_delta = .975, max_treedepth = 20),
                      seed = 190831, open_progress = FALSE, stanvars = stanvar)

  quad = quantile(model2$fit@sim$samples[[1]][["b_time2"]], c(alpha/2, 1-alpha/2))
  sig_quad = as.numeric(sign(quad[1]) == sign(quad[2]))

  beta_quad = quantile(model2$fit@sim$samples[[1]][["b_time2"]], 0.5)
  beta_lin = quantile(model2$fit@sim$samples[[1]][["b_time"]], 0.5)
  beta0 =  quantile(model2$fit@sim$samples[[1]][["b_Intercept"]], 0.5)

  return(list(significant = sig_quad,
              beta_square = beta_quad,
              beta_lin = beta_lin,
              beta0 = beta0))

}

fit_linear = function(data_met, alpha){

  #fit linear regression
  n = length(unique(data_met$individual))
  beta1_i = rep(NA,n);

  for(i in 1:n){
    data_i = data_met[data_met$individual==i,]
    lm = lm(measurement ~ -1 + time,data = data_i)
    beta1_i[i] = lm$coefficients[1]
  }

  beta1_0 = mean(beta1_i); sigma1_0= sd(beta1_i)
  stanvar = stanvar(beta1_0 ,"beta1_0") +   stanvar(sigma1_0 ,"sigma1_0")

  model1 <- brms::brm(data = data_met,
                      family = gaussian,
                      measurement ~ 1 + time + (1 | individual), # random intercept by individual
                      prior = c(prior_string("normal(0, 10)", class = "Intercept"),  #prior for the intercept
                                prior_string("normal(beta1_0, sigma1_0)", coef = "time"), #prior for betas
                                prior_string("cauchy(0, 1)", class = "sd"), #sd of random effects
                                prior_string("cauchy(0, 1)", class = "sigma")), #overall variability
                      iter = 10000, warmup = 500, chains = 1, cores = 1, thin = 10,
                      control = list(adapt_delta = .975, max_treedepth = 20),
                      seed = 190831, open_progress = FALSE, stanvars = stanvar)

  lin = quantile(model1$fit@sim$samples[[1]][["b_time"]], c(alpha/2, 1-alpha/2))
  sig_lin = as.numeric(sign(lin[1]) == sign(lin[2]))
  beta_lin = quantile(model1$fit@sim$samples[[1]][["b_time"]], 0.5)
  beta0 =  quantile(model1$fit@sim$samples[[1]][["b_Intercept"]], 0.5)

  return(list(significant = sig_lin,
              beta_lin = beta_lin,
              beta0 = beta0))

}

LMMs_data = function(top, data){
  # this function is to get the original data of the metabolites identifyed as top
  if(class(top) != "top_loadings"){
    print("Function expects an object of class top_loadings.")
  } else {

  M = length(data)
  bins = lapply(top, "[[", "spectral_bin")
  bins = unique(unlist(bins))

  K= length(bins) #number of bins identified
  M = length(data)

  get_series= function(k, data, bins){
    bin = bins[k]
    index = which(colnames(data[[1]])==bin)
    n = nrow(data[[1]])
    serie_list =  lapply(data, "[",, j = index)
    series_matrix = t(matrix(unlist(serie_list),ncol = n, byrow = TRUE))
    #series_matrix = apply(series_matrix, 2, paretoscale)
    series_wide = data.frame(series_matrix)
    series_wide$individual = seq(1,n,1)

    series_long = gather(series_wide, "time", "measurement", "X1":"X8", factor_key=TRUE)
    series_long$time = gsub("X","", series_long$time)
    series_long$time = as.numeric(as.character(series_long$time))
    series_long$time2 = series_long$time^2
    series_long$time3 = series_long$time^3


    return(series_long)
  }

  series = sapply(seq(1,K,1),get_series, data, bins, simplify = FALSE)
  return(list(series = series, bins = bins))
  }
}











