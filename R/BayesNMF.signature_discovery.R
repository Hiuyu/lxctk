############################################################################################
############################################################################################
#Copyright (c) 2016, Broad Institute

#Redistribution and use in source and binary forms, with or without
#modification, are permitted provided that the following conditions are
#met:

#    Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.

#    Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in
#    the documentation and/or other materials provided with the
#    distribution.

#    Neither the name of the Broad Institute nor the names of its
#    contributors may be used to endorse or promote products derived
#    from this software without specific prior written permission.

#THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
#"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
#LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
#A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
#HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
#SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
#LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
#DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
#THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
#(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
#OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
############################################################################################
############################################################################################

######################################################################################################
####### Mutation Signature Profiling using Bayesian NMF algorithms 
######################################################################################################
####### For details on the implementation 
####### see J Kim, Mouw K, P Polak et al, Somatic ERCC2 mutations are associated with a distinct genomic signature in urothelial tumors 
####### Nat. Genet. DOI: 10.1038/ng.3557
####### For details on the original algorithms 
####### see Tan, V.Y. & Fe??votte, C. Automatic relevance determination in nonnegative matrix factorization with the beta-divergence.
####### IEEE Trans. Pattern Anal. Mach. Intell. 35, 1592???1605 (2013).
######################################################################################################

##########################################################
###################### R functions  ######################
##########################################################

## Bayesian NMF algorithm with exponential priors for W and H
BayesNMF.L1KL <- function(V0,n.iter,a0,tol,K,K0,phi) {
        eps <- 1.e-50
        del <- 1.0
        active_nodes <- colSums(V0) != 0
        V0 <- V0[,active_nodes]
        V <- V0-min(V0) + eps
        Vmin <- min(V)
        Vmax <- max(V)
        N <- dim(V)[1]
        M <- dim(V)[2]
        W <- matrix(runif(N * K)*sqrt(Vmax),ncol=K)
        H <- matrix(runif(M * K)*sqrt(Vmax),ncol=M)
        V.ap <- W %*% H + eps
        I <- array(1,dim=c(N,M))

        C <- N + M + a0 + 1
        b0 <- sqrt((a0-1)*(a0-2)*mean(V,na.rm=T)/K0)
        lambda.bound <- b0/C
        lambda <- (colSums(W)+rowSums(H)+b0)/C
        lambda.cut <- 1.5*lambda.bound

        n.like <- list()
        n.evid <- list()
        n.error <- list()
        n.lambda <- list()
        n.lambda[[1]] <- lambda

        iter <- 2
        count <- 1
        while ((del >= tol) & (iter < n.iter)) {
                H <- H * (t(W) %*% (V/V.ap))/(matrix(rep(colSums(W)+phi/lambda,M),ncol=M) + eps)
                V.ap <- W %*% H + eps
                W <- W * ((V/V.ap) %*% t(H))/t(matrix(rep(rowSums(H)+phi/lambda,N),ncol=N) + eps)
                V.ap <- W %*% H + eps
                lambda <- (colSums(W) + rowSums(H) + b0) / C
                del <- max(abs(lambda-n.lambda[[iter-1]])/n.lambda[[iter-1]])
                like <- sum(V*log(V/V.ap)+V.ap-V)
                n.like[[iter]] <- like
                n.evid[[iter]] <- like+phi*sum((colSums(W)+rowSums(H)+b0)/lambda+C*log(lambda))
                n.lambda[[iter]] <- lambda
                n.error[[iter]] <- sum((V-V.ap)^2)
                if (iter %% 100 == 0) {
                        cat(iter,n.evid[[iter]],n.like[[iter]],n.error[[iter]],del,sum(colSums(W)!=0),sum(lambda>=lambda.cut),'\n')
                }
                iter <- iter+1
        }
        return(list(W,H,n.like,n.evid,n.lambda,n.error))
}

## Bayesian NMF algorithm with hlaf-normal priors for W and H
BayesNMF.L2KL <- function(V0,n.iter,a0,tol,K,K0,phi) {
        eps <- 1.e-50
        del <- 1.0
        active_nodes <- colSums(V0) != 0
        V0 <- V0[,active_nodes]
        V <- V0-min(V0)
        Vmax <- mean(V)
        N <- dim(V)[1]
        M <- dim(V)[2]

        W <- matrix(runif(N * K)*Vmax,ncol=K)
        H <- matrix(runif(M * K)*Vmax,ncol=M)
        V.ap <- W%*%H+eps

        C <- (N+M)/2+a0+1
        b0 <- 3.14*(a0-1)*mean(V)/(2*K0)
        lambda <- (0.5*colSums(W*W)+0.5*rowSums(H*H)+b0)/C
        lambda.bound <- b0/C
        lambda.cut <- b0/C*1.25

        I <- array(1,dim=c(N,M))
        n.like <- list()
        n.evid <- list()
        n.error <- list()
        n.lambda <- list()
        n.lambda[[1]] <- lambda
        iter <- 2
        count <- 1
        while ((del >= tol) & (iter < n.iter)) {
                H <- H*(t(W)%*%(V/V.ap)/(t(W)%*%I+phi*H/matrix(rep(lambda,M),ncol=M)+eps))^0.5
                V.ap <- W%*%H+eps
                W <- W*((V/V.ap)%*%t(H)/(I%*%t(H)+phi*W/t(matrix(rep(lambda,N),ncol=N))+eps))^0.5
                lambda <- (0.5*colSums(W*W)+0.5*rowSums(H*H)+b0)/C
                V.ap <- W%*%H+eps
                del <- max(abs(lambda-n.lambda[[iter-1]])/n.lambda[[iter-1]])
                like <- sum(V * log((V+eps)/(V.ap+eps)) + V.ap - V)
                n.like[[iter]] <- like
                n.evid[[iter]] <- like + phi*sum((0.5*colSums(W^2)+0.5*rowSums(H^2)+b0)/lambda+C*log(lambda))
                n.lambda[[iter]] <- lambda
                n.error[[iter]] <- sum((V-V.ap)^2)
                if (iter %% 100 == 0) {
                        cat(iter,n.evid[[iter]],n.like[[iter]],n.error[[iter]],del,sum(colSums(W)!=0),sum(lambda>=lambda.cut),'\n')
                }
                iter <- iter+1
        }
        return(list(W,H,n.like,n.evid,n.lambda,n.error))
}

######### Handling hypermutant samples; See J Kim et al Nat. Genet. DOI: 10.1038/ng.3557 for details.
get.lego96.hyper <- function(lego96) {
	x <- lego96
	for (i in 1:100) {
	        SNV <- colSums(x)
	        q1 <- quantile(SNV,prob=1/4)
	        q3 <- quantile(SNV,prob=3/4)
	        sample.hyper <- colnames(x)[SNV > (median(SNV)+1.5*(q3-q1))]
	        if (length(sample.hyper)==0) break
	       	lego96.hyper <- as.matrix(x[,(colnames(x) %in% sample.hyper)])
	       	colnames(lego96.hyper) <- sample.hyper
	       	lego96.nonhyper <- x[,!(colnames(x) %in% sample.hyper)]
	        lego96.hyper1 <- apply(lego96.hyper,2,function(x) x/2)
	        lego96.hyper2 <- lego96.hyper1
	        colnames(lego96.hyper1) <- paste(colnames(lego96.hyper1),1,sep="__")
	        colnames(lego96.hyper2) <- paste(colnames(lego96.hyper2),2,sep="__")
	        x <- cbind(lego96.nonhyper,lego96.hyper1,lego96.hyper2)
	}
	return(x)
}

######### Visualizing the activity of signatures
plot.activity.barplot <- function(H.mid,H.norm,scale,tumor.type) {
        .theme_ss <- theme_bw(base_size=14) +
                theme(axis.text.x = element_text(angle = 90, vjust = 0.5, size=8*scale, family="mono"),
                axis.text.y = element_text(hjust = 0.5,size=12*scale, family="mono"),
                axis.text = element_text(size = 12*scale, family = "mono"))
        ordering <- order(colSums(H.mid),decreasing=T)
        H.mid.nr <- dim(H.mid)[1] # added by LiXC
        H.mid <- H.mid[,ordering]
        rownames(H.mid) <- paste("W",seq(1:nrow(H.mid)),sep="")
        H.norm <- H.norm[,ordering]
        rownames(H.norm) <- paste("W",seq(1:nrow(H.norm)),sep="")
	sample.ordering <- colnames(H.mid)
        x1 <- melt(H.mid)
        x2 <- melt(H.norm)
        colnames(x1) <- c("Signature","Sample","Activity")
        colnames(x2) <- c("Signature","Sample","Activity")
        x1[,"class0"] <- c("Counts")
        x2[,"class0"] <- c("Fractions")
        df2 <- rbind(x1,x2)
        df2$class0 <- factor(df2$class0,c("Counts","Fractions"))
	df2$Sample <- factor(df2$Sample,sample.ordering)
        scale <- 1
        p = ggplot(df2,aes(x=factor(Sample),y=Activity,fill=factor(Signature)))
        p = p+geom_bar(stat="identity",position='stack',color='black',alpha=0.9)
        if (H.mid.nr < 17) { 
          p = p + scale_fill_manual(values=c("red","cyan","yellow","blue","magenta","gray50","orange","darkgreen","brown","black",rainbow(10)[4:10]))
        } else { # In case the signature number is larger than colors provided above. LiXC
          p = p + scale_fill_manual(values = 1:H.mid.nr)
        }
        p = p + facet_grid(class0 ~ ., scale = "free_y")
        p = p + ggtitle(paste("Siganture Activities in",tumor.type,sep=" "))
        p = p + theme(plot.title=element_text(lineheight=1.0,face="bold",size=14*scale))
        p = p + xlab("Samples") + ylab("Signature Activities")
        p = p + theme(axis.title.x = element_text(face="bold",colour="black",size=14*scale))
        p = p + theme(axis.title.y = element_text(face="bold",colour="black",size=14*scale))
        p = p + theme(axis.text.x = element_text(angle=90,vjust=0.5,size=8*scale,face="bold",colour="black"))
        p = p + theme(axis.text.y = element_text(size=10*scale,face="bold",colour="black"))
        p = p + theme(legend.title=element_blank())
        p = p + .theme_ss
        p = p + theme(legend.position="top")
        return(p)
}

######### Collecting data from several independent runs
get.stats.simulation <- function(tumor,n.iter,method,a0,OUTPUT) { # method and a0 are missing in the original code. LiXC
        W.ALL <- list()
        H.ALL <- list()
        K.ALL <- list()
        lambda.ALL <- list()
        evid.ALL <- list()
        for (i in 1:n.iter) {
                x <- load(paste(OUTPUT,paste(method,a0,i,"RData",sep="."),sep=""))
                W <- res[[1]]
                H <- res[[2]]
                evid <- res[[4]]
                evid <- evid[[length(evid)]]
                lambda <- res[[5]]
                lambda <- lambda[[length(lambda)]]
                lambda.min <- min(lambda)
                lambda <- lambda-lambda.min
                lambda.norm <- lambda/sum(lambda)
                index <- lambda.norm > 0.01
                K <- sum(index)
                W.ALL[[i]] <- W
                H.ALL[[i]] <- H
                lambda.ALL[[i]] <- lambda
                K.ALL[[i]] <- K
                evid.ALL[[i]] <- evid
        }
        return(list(W.ALL,H.ALL,lambda.ALL,K.ALL,evid.ALL))
}

######### Visualizing the profile of signatures
plot.lego.observed.barplot <- function(mat,title) {
        scale <- 1.5
        .theme_ss <- theme_bw(base_size=20) +
                theme(axis.text.x = element_text(angle = 90, vjust = 0.5, size=10*scale, family="mono"),
                axis.text.y = element_text(hjust = 0.5,size=12*scale, family="mono"),
                axis.text = element_text(size = 16*scale, family = "mono"))
        p = ggplot(mat)
        p = p + geom_bar(aes_string(x="context3",y="signature",fill="base.sub"),stat="identity",position="identity",colour="gray50")
        p = p + facet_grid(class ~ base.sub, scale = "free_y")
        p = p + .theme_ss
        p = p + scale_fill_manual(values=c("cyan","red","yellow","purple","green","blue","black","gray")) #p = p + scale_fill_brewer(palette = "Set1")
        p = p + guides(fill=FALSE) #p = p + theme(legend.position = "none")
        p = p + ggtitle(title)
        p = p + xlab("Motifs") + ylab("Contributions")
        p = p + theme(axis.title.x = element_text(face="bold",colour="black",size=14*scale))
        p = p + theme(axis.title.y = element_text(face="bold",colour="black",size=14*scale))
        return(p)
}

get.df.solution <- function(W,H,lambda,tumor) {
        lambda <- lambda[[length(lambda)]]
        lambda.min <- min(lambda)
        lambda <- (lambda-lambda.min)/max(lambda)
        norm.lambda <- lambda/sum(lambda)
        index <- lambda > 0.01
        x <- colSums(W)/max(colSums(W))
        index <- x > 0.01
        K <- sum(index)
        if (K != 1) {
                W <- W[,index]
                H <- H[index,]
                norm.W <- t(apply(W,1,function(x) x/sum(x)))
                norm.H <- apply(H,2,function(x) x/sum(x))
        }
        colnames(W) <- paste("W",seq(1:ncol(W)),sep="")
        rownames(H) <- paste("H",seq(1:ncol(W)),sep="")

        context96 <- rownames(W)[1:96]
        context96 <- sub("->","",context96)
        context96 <- gsub("[.]","",context96)
        index96 <- c(order(substring(context96,1,2),decreasing=F))
        W.SNP <- as.vector(W[index96,])
        seq <- c(context96[index96])
        context4 <- rep(seq,K)
        context3 <- paste(substring(context4,3,3),"-",substring(context4,4,4),sep="")
        base.sub <- paste(substring(context4,1,1),"->",substring(context4,2,2),sep="")
        signature.class <- as.vector(t(matrix(t(rep(1:K,96)),nrow=K)))
        signature.class <- paste("W",signature.class,sep="")
        df <- data.frame(W.SNP,context4,context3,base.sub,signature.class,rep(tumor,nrow(W)*ncol(W)))
        colnames(df) <- c("signature","context4","context3","base.sub","class","tumor")
        return(df)
}
##########################################################
##########################################################
##########################################################

# source code borrow from SomaticSignatures::mutationContext
mutationContext <- function (vr, ref, k = 3, strand = FALSE, unify = TRUE, check = FALSE) 
{
  if (!all(ref(vr) %in% DNA_BASES & alt(vr) %in% DNA_BASES)) 
    stop("Only SNV substitutions are currently supported.")
  if (k%%2 != 1) 
    stop("'k' must be odd.")
  mid = (k + 1)/2
  gr = granges(vr)
  ranges = resize(gr, k, fix = "center")
  context = getSeq(ref, ranges)
  ref_base = DNAStringSet(ref(vr))
  alt_base = DNAStringSet(alt(vr))
  if (check) {
    ref0 = subseq(context, mid, mid)
    idx_invalid = (ref0 != ref_base)
    if (any(idx_invalid)) 
      warning(sprintf("References do not match in %d cases", sum(idx_invalid)))
  }
  if (strand) {
    s = strand(gr)
    if (any(s == "*")) 
      stop("The strand must be explicit, in order to read the correct strand.")
    idx_minus = (s == "-")
    context[idx_minus] = reverseComplement(context[idx_minus])
    s[idx_minus] = "+"
    strand(gr) = s
  }
  if (unify) {
    idx_complement = ref_base %in% c("A", "G")
    context[idx_complement] = reverseComplement(context[idx_complement])
    ref_base[idx_complement] = reverseComplement(ref_base[idx_complement])
    alt_base[idx_complement] = reverseComplement(alt_base[idx_complement])
  }
  subseq(context, mid, mid) = "."
  alteration = xscat(ref_base, alt_base)
  vr$alteration = alteration
  vr$context = context
  return(vr)
}

constructMotifs3 <- function() {
  
  alteration = expand.grid(ref = DNA_BASES, alt = DNA_BASES)
  alteration = subset(alteration, ref != alt & ref %in% c("C", "T"))
  alteration = sort(paste0(alteration$ref, alteration$alt))
  motifs = expand.grid(s = DNA_BASES, p = DNA_BASES, a = alteration)
  motifs = sprintf("%s %s.%s", motifs$a, motifs$p, motifs$s)
  
  return(motifs)
}

motifMatrix <- function (vr, group = "sampleNames", normalize = TRUE) 
{
  voi <- if (group %in% names(mcols(vr))) {
    mcols(vr)[, group]
  }
  else {
    df = as(unname(vr), "data.frame")
    if (!(group %in% colnames(df))) {
      stop(sprintf("Column '%s' not present in input object.", group))
    }
    df[, group]
  }
  motif = factor(paste(vr$alteration, vr$context), levels = constructMotifs3())
  y = as(table(motif, voi), "matrix")
  dimnames(y) = unname(dimnames(y))
  if (normalize) {
    y = t(t(y)/colSums(y))
  }
  return(y)
}



# x: a data.frame or oncotator output file with at least 5 columns, i.e. 'chr', 'start', 'end', 'ref', 'alt' and 'sampleid'
# tumor.type: a character string
# hyper: Default = FALSE ; TRUE - to reduce the effect of hyper-mutant samples in the signature discovery
# fafile: bwa indexed reference fasta file
# out.dir: output dir
# prior: prior for Bayesian NMF, i.e. L1KL or L2KL
# hyperCutoff: mutation number to define hypermutated samples. If this is set (e.g. 500), 
#+------------ samples with > hyperCutoff mutations will be excluded. I might recommended to set hyper=TRUE if there are hypermutated samples.

# An example:
# library(data.table)
# d <- fread("cut -f5,6,7,10,11,13,16,287  /ifshk5/PC_HUMAN_AP/PMO/F13TSHNCKF0797_HUMdjpX/lixc/TCGA/Oncotator/PANCAN_Mutation_with_Unknown_chrM_annotation_removed_uniq_attached_hypermutated_info.maf | grep -v ^#")
# setDf(d)
# x <- subset(d, Variant_Type=="SNP" & Is_HyperMutated=="No", c("Chromosome","Start_position","End_position", "Reference_Allele", "Tumor_Seq_Allele2", "Tumor_Sample_Barcode"))
# colnames(x) = c("chr","start","end","ref","alt","sampleid")
# BayesNMF.mutation.signature(x, "PANCAN_nonhypermutated")

## Comment on running BayesNMF.mutation.signature on phase 1 precision medicine with both L1KL and L2KL priors.
## For the liver cancer, L2KL produced 3 signatures: (1) ERCC2 signature (broad patterns of base substitutions see doi:10.1038/ng.3557);
##+(2) Aristolochic acid signature; (3) age-related signature (i.e. *CpG); whereas L1KL produced 2 signatures: (2) and mixture of (1) and (3).
## For kidney and lung cancers, L1KL and L2KL priors produced exactly the same signatures.
## In summary, L2KL produced better result for liver cancer than L1KL and with comparable results for kidney and lung cancers.

BayesNMF.mutation.signature <- function(x, tumor.type, hyper=FALSE, fafile=NULL, out.dir="OUTPUT_lego96", prior="L1KL", hyperCutoff=NULL) {

suppressMessages(library(data.table))
suppressMessages(library(gplots))
suppressMessages(library(ggplot2))
suppressMessages(library(reshape2))
suppressMessages(library(BSgenome))
suppressMessages(library(VariantAnnotation))
  
##-----------Check for input data format---------------##
message("Check for input data format.")
if (is.data.table(x) || is.data.frame(x)) {
  if (!all(colnames(x) %in% c("chr","start","end","ref","alt","sampleid"))) {
    message("The following colname(s) not found in input data.table:")
    cat(setdiff(c("chr","start","end","ref","alt","sampleid"), colnames(x)), "\n", file=stderr())
    stop("Please check your input data.")
  }
  x <- subset(x, ref %in% c("A","C","G","T") & alt %in% c("A","C","G","T")) ## removing indels
} else if (file.exists(x)) { ## oncotator annotated file
  x <- suppressWarnings(fread(x))
  x <- subset(x, Variant_Type=="SNP", c("Chromosome","Start_position","End_position", "Reference_Allele", "Tumor_Seq_Allele2", "Tumor_Sample_Barcode"))
  colnames(x) <- c("chr","start","end","ref","alt","sampleid")
  if (!all(grepl("^chr", x$chr))) x$chr <- paste("chr",x$chr, sep="")
} else {
  stop("The input mutation data must be either a data.frame, data.table or a valid oncotator output file.")
}
##-----------End of checking for input data format---------------##

##-----------Removing hypermutated samples----------------##
if (!is.null(hyperCutoff)) {
  totalMutationNum <- table(x$sampleid)
  hyperMutatedSamples <- names(totalMutationNum)[totalMutationNum > hyperCutoff]
  x <- subset(x, !(sampleid %in% hyperMutatedSamples))
  message("Removed hypermutated samples:")
  print(hyperMutatedSamples, file=stderr())
}
##--------------------------------------------------------##

#message("##################### Extract mutation contexts ###################\n")
if (!is.null(fafile)) {
  fa <- FaFile(fafile)
} else {
  library(BSgenome.Hsapiens.UCSC.hg19)
  fa <- BSgenome.Hsapiens.UCSC.hg19
}

vr <- VRanges(seqnames=x$chr, range=IRanges(start=x$start, end=x$end), ref=x$ref, alt=x$alt, sampleNames=x$sampleid)
message("Chromosomes extracted from input mutated data:")
cat(seqlevels(vr), "\n")
if (any(seqlevels(vr) %in% seqlevels(fa)) == FALSE) {
  message("Chromosomes extracted from reference:")
  cat(seqlevels(fa), "\n")
  if (!is.null(fa)) {
    close(fa)
  }
  stop("There is no intersection between chromosomes from input mutated data and reference sequence.")
}

#########################################################
motifs <- mutationContext(vr, fa)
if (!is.null(fafile)) close(fa)

lego96 <- motifMatrix(motifs, group = "sampleNames", normalize = FALSE)
rownames(lego96) <- sub("\\.","",sub(" ","",rownames(lego96)))
#rm(motifs, vr)
message("Finished preparing lego96 mutation matrix for mutation signature analysis.")

#CURRENT <- paste(getwd(),'/',sep="")
#SOURCE <- paste(CURRENT,"SOURCE/",sep="")
#PARAMETER <- SOURCE
#source(paste(SOURCE,"get.context96_annotated.from.maf.R",sep=""))
#source(paste(SOURCE,"get.util.signature.R",sep=""))
#source(paste(SOURCE,"plot.signature.tools.Alexsandrov.R",sep=""))

CURRENT <- paste(getwd(),"/",sep="")
OUTPUT <- paste(CURRENT,sprintf("%s/",out.dir),sep="")
#system(paste("mkdir",OUTPUT,sep=" "))
if (!file.exists(OUTPUT)) dir.create(OUTPUT)

############## INPUT ######################################
## lego96 - mutation counts matrix (96 by # of samples) 
## This matrix should contain mutation counts along 96 tri-nucleotide mutation contexts (rows) across samples (columns). 
## Rownames of the lego matrix should be 4-letters ex) CGTA (C to G mutation at 5'-TCA-3'contexts) (see the acoompanied example lego matrix).
###########################################################

#message("\n#####################################################")
#message("############## BayesNMF parameters")
#message("############## n.iter = number of independent simulations")
#message("############## Kcol = number of initial signatures")
#message("############## tol = tolerance for convergence")
#message("############## a0 = hyper-parameter\n")
n.iter <- 10 
Kcol <- 96   
tol <- 1.e-07
a0 <- 10

#message("##################################")
#message("############### Choose pirors for W and H")
#message("############### Default = L1KL (expoential priors); L2KL (half-normal priors)")
#message("##################################\n")
#prior <- "L1KL" 
if (prior=="L1KL") {
	method <- paste("L1KL.lego96",tumor.type,sep=".")
} else {
	method <- paste("L2KL.lego96",tumor.type,sep=".")
}
##################################

##################################
############## Default = FALSE ; TRUE - to reduce the effect of hyper-mutant samples in the signature discovery
##################################
#hyper <- FALSE
if (hyper) {
	lego96 <- get.lego96.hyper(lego96)
	method <- paste(method,"hyper",sep=".")
}
##################################

#message("##########################################################")
#message("###################### Running the algorithms ############")
#message("##########################################################\n")
message("Running the algorithms.")
for (i in 1:n.iter) {
  message(sprintf("Iteration - %s.", i))
	if (prior=="L1KL") {
		res <- BayesNMF.L1KL(as.matrix(lego96),100000,a0,tol,Kcol,Kcol,1.0)
	} else {
		res <- BayesNMF.L2KL(as.matrix(lego96),100000,a0,tol,Kcol,Kcol,1.0)
	}
	save(res,file=paste(OUTPUT,paste(method,a0,i,"RData",sep="."),sep=""))
}

#message("##########################################################")
#message("###################### Analysis ##########################")
#message("##########################################################\n")
message("Analyzing BayesNMF results...")
res.WES <- get.stats.simulation(tumor.type,n.iter,method,a0,OUTPUT)

message("Plotting frequency figure.")
#message(sprintf("Method - %s\n",method))
pdf(file=paste(OUTPUT,paste(method,a0,"signature.freq.pdf",sep="."),sep=""),width=4,height=5)
s1 <- 1.5
s2 <- 2.0
par(mfrow=c(1,1))
par(mar=c(5,5,2,1))
barplot(table(unlist(res.WES[[4]])),cex=s1,cex.axis=s1,cex.main=s1,cex.names=s1,cex.lab=s1,xlab="# of signatures",ylab="Freq.",main=paste(tumor.type,sep="."))
dev.off()

#message("##########################################################")
#message("############## select the best solution (maximum posteria solution) for given K")
#message("##########################################################\n")
message("Select the best solution (maximum posteria solution) from given K.")
tmpK <- unlist(res.WES[[4]])
unique.K <- sort(unique(tmpK))
n.K <- length(unique.K)
MAP <- list()
for (i in 1:n.K) {
        tmpX <- res.WES[[5]]
        tmpX[tmpK != unique.K[i]] <- 0
        MAP[[i]] <- which.min(tmpX)
}

tmpK <- unlist(res.WES[[4]])
unique.K <- sort(unique(tmpK))
n.K <- length(unique.K)
MAP <- list()
for (i in 1:n.K) {
        tmpX <- res.WES[[5]]
        tmpX[tmpK != unique.K[i]] <- 0
        MAP[[i]] <- which.min(tmpX)
}
MAP <- unlist(MAP)
names(MAP) <- unique.K
MAP.nontrivial <- MAP[names(MAP)!=1]
##########################################################
##########################################################

n.K <- length(MAP.nontrivial)
message(sprintf("n.K = %s.", n.K))
if (n.K > 0) { 
for (j in 1:n.K) {
        load(paste(OUTPUT,paste(method,a0,MAP.nontrivial[[j]],"RData",sep="."),sep=""))
        W <- res[[1]]
        H <- res[[2]]
        W1 <- W
        H1 <- H
        W.norm <- apply(W,2,function(x) x/sum(x))
        for (i in 1:ncol(W)) {
                H1[i,] <- H1[i,]*colSums(W)[i]
                W1[,i] <- W1[,i]*rowSums(H)[i]
        }
        lambda <- res[[5]]
        df <- get.df.solution(W1,H,lambda,tumor.type)
        K <- length(table(df$class))

        ############# Signature plot
        width <- 16
        height <- ifelse(K==1,3,K*2)
        pdf(file=paste(OUTPUT,paste(method,a0,paste("MAP",K,sep=""),"signature.pdf",sep="."),sep=""),width=width,height=height)
                p <- plot.lego.observed.barplot(df,paste("Mutation Signatures in ",tumor.type,sep=""))
                plot(p)
        dev.off()

        index.nonzero <- colSums(W) != 0
        lambda <- unlist(res[[5]][length(res[[5]])])
        lambda <- lambda/min(lambda)
        lambda <- lambda[index.nonzero]
        names(lambda) <- paste("W",seq(1:length(lambda)),sep="")
        K <- sum(index.nonzero)
        if (K != 1) {
                W0.tumor <- W[,index.nonzero]
                H0.tumor <- H[index.nonzero,]
                x <- W0.tumor
                y <- H0.tumor
                x.norm <- apply(x,2,function(x) x/sum(x))
                W1.tumor <- x.norm
                for (j in 1:K) y[j,] <- y[j,]*colSums(x)[j]
                H1.tumor <- y
                y.norm <- apply(y,2,function(x) x/sum(x))
                H2.tumor <- y.norm
        } else {
                stop("No non-trivial solutations; All simulations converged to a trivial solution with one signature")
        }

        ############# Reconstructing the activity of signatures
        W.mid <- W1.tumor
        H.mid <- H1.tumor
        H.norm <- H2.tumor
        if (length(grep("__",colnames(H.mid))) != 0) {
                hyper <- colnames(H.mid)[grep("__",colnames(H.mid))]
                H.hyper <- H.mid[,colnames(H.mid) %in% hyper]
                H.nonhyper <- H.mid[,!(colnames(H.mid) %in% hyper)]
                sample.hyper <- colnames(H.hyper)
                sample.hyper <- sapply(sample.hyper,function(x) strsplit(x,"__")[[1]][[1]])
                unique.hyper <- unique(sample.hyper)
                n.hyper <- length(unique.hyper)
                x.hyper <- array(0,dim=c(nrow(H.hyper),n.hyper))
                for (i in 1:n.hyper) {
                        x.hyper[,i] <- rowSums(H.hyper[,sample.hyper %in% unique.hyper[i]])
                }
                colnames(x.hyper) <- unique.hyper
                rownames(x.hyper) <- rownames(H.mid)
                H.mid <- (cbind(H.nonhyper,x.hyper))
                H.norm <- apply(H.mid,2,function(x) x/sum(x))
        }
	W.norm <- apply(W.mid,2,function(x) x/sum(x))

	#message("##########################################################")
  #message("      ############# W.norm = extracted signatures normalized to one")
	#message("############# H.mid = activity of signatures across samples (expected mutations associated with signatures)")
	#message("############# H.norm = normalized signature activity")
	#message("##########################################################")
	      # WH <- list(W.norm,H.mid,H.norm)
        WH <- list(W.mid=W.mid, W.norm=W.norm,H.mid=H.mid,H.norm=H.norm)
        save(WH,file=paste(OUTPUT,paste(method,a0,paste("MAP",K,sep=""),"WH.RData",sep="."),sep=""))

        message("Plotting activity plot.")
	p1 <- plot.activity.barplot(H.mid,H.norm,1.0,tumor.type)
	pdf(file = paste(OUTPUT,paste(method,a0,"activity.barplot1",K,"pdf",sep="."),sep=""),width=15,height=12)
	        plot(p1)
	dev.off()
}
}
message("Successfully finished analyzing mutation signature.")
}
