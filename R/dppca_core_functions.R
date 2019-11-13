# DPPCA Method -------------------------------------------------------------

#' @importFrom stats sd rnorm dnorm
#' @importFrom msm rtnorm
#' @importFrom mvtnorm dmvnorm rmvnorm
#' @importFrom LearnBayes rigamma


#  Gibbs U -------------------------------------------------------------
gibbs_U = function(data, eta, W, H){

  M = length(data)
  Sig <- exp(eta)

  single_U = function(m,W,Sig,H,data){
    n = nrow(data[[1]])
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

  M = length(W);

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

MH_lambda = function(lambda,mu,Phi,V,U, accept_lambda){

  gen_lambda_j = function(m, j, lambda, mu, Phi, U){
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

  l = mapply(gen_lambda_j, m = sort(rep(seq(1,M,1),q)), j = rep(seq(1,q,1), M), MoreArgs = list(lambda = lambda, mu =mu, Phi=Phi, U=U), SIMPLIFY = FALSE)

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

gibbs_nu = function(sigma2_nu, phi, eta, v2){

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
  mu = sapply(seq(1,q,1),single_nu,sigma2_nu, Phi,V,lambda );
  return(mu)

}

#  M-H Phi -------------------------------------------------------------

MH_Phi = function(mu_Phi,sigma2_Phi, Phi, V, lambda, mu, accept_Phi){

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
