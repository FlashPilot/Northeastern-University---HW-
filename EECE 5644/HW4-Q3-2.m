clear all, close all, clc;

filenames{1, 1} = '3096_color.jpg';
filenames{1, 2} = '42049_color.jpg';

Kvalues = [2, 3, 4, 5, 6, 7, 8, 9, 10]; % desired numbers of clusters

for imageCounter = 1 : 2 %size(filenames,2)
    imdata = imread(filenames{1, imageCounter}); 
    figure(1), subplot(size(filenames, 2), 1 + 1, (imageCounter - 1) * (1 + 1) + 1), imshow(imdata);

    [R, C, D] = size(imdata); 
    N = R * C; 
    imdata = double(imdata);
    rowIndices = (1 : R)' * ones(1, C); 
    colIndices = ones(R, 1) * (1 : C);
    features = [rowIndices(:)'; colIndices( : )']; % initialize with row and column indices

    for d = 1 : D
        color = imdata(:, :, d); % pick one color at a time
        features = [features; color( : )'];
    end
    
    minf = min(features, [], 2); 
    maxf = max(features, [], 2);
    ranges = maxf - minf;
    x = diag(ranges .^ (-1)) * (features - repmat(minf, 1, N)); % each feature normalized to the unit interval [0,1]
    
    d = size(x, 1); % feature dimensionality
    
    Nc = length(x);
    
    order = cross_validate(x, length(x));
    GMModel = fitgmdist(x', order, 'RegularizationValue', 1e-10);
    alpha = GMModel.ComponentProportion; %calculated alhpha
    mu = (GMModel.mu)'; %calculated mu
    sigma = GMModel.Sigma; %calculated sigma
    %[alpha, mu, Sigma] = EMforGMM(order, x, Nc);
    %pdf = evalGMM(x, alpha, mu, Sigma);
    
%     cluster1pdf = alpha(1) * evalGaussian(X1, mu(:, 1), Sigma(:, :, 1));
%     cluster2pdf = alpha(2) * evalGaussian(X1, mu(:, 2), Sigma(:, :, 2));
    for i = 1 : order
        clusterpdf(i, :) = alpha(i) * evalGaussian(x, mu(:, i), sigma(:, :, i));
    end
    
    %MAP
    %p_condition = [cluster1pdf; cluster2pdf];
    %[~, labels] = max(p_condition, [], 1);
    [~, labels] = max(clusterpdf, [], 1);

    labelImage = reshape(labels, R, C);
    %figure(1), subplot(size(filenames, 2), length(Kvalues) + 1, (imageCounter - 1) * (length(Kvalues) + 1) + 1 + 1), imshow(uint8(labelImage * 255 / order));
    figure(1), subplot(size(filenames, 2), 1 + 1, (imageCounter - 1) * (1 + 1) + 1 + 1), imshow(uint8(labelImage * 255 / order));
    title(strcat({'Clustering with K = '}, num2str(order)));
end   

function best_GMM = cross_validate(X, N)
    % Order-select using cross-validation
    % Performs EM algorithm to estimate parameters and evaluete performance
    % on each data set B times, with 1 through M GMM models considered
    K = 10; 
    M = 10;

    perfarray = zeros(K, M); %save space
    dummy = ceil(linspace(0, N, K+1));

    for k = 1 : K
        indPartitionLimits(k, :) = [dummy(k) + 1, dummy(k + 1)];
    end

    for k = 1 : K
        indValidate = (indPartitionLimits(k, 1) : indPartitionLimits(k, 2));

        if k == 1
            indTrain = (indPartitionLimits(k, 2) + 1 : N);
        elseif k == K
            indTrain = (1 : indPartitionLimits(k, 1) - 1);
        else
            %indTrain = [1 : indPartitionLimits(k - 1, 2) indPartitionLimits(k + 1, 1) : N];
            indTrain = [1 : indPartitionLimits(k - 1, 2) indPartitionLimits(k + 1, 1) : N];
        end

        dValidate= X(:, indValidate); % Using folk k as validation set
        %YValidate = Y(:, indValidate); 
        dTrain = X(:, indTrain); % using all other folds as training set
        %YTrain = Y(:, indTrain);
        NTrain = length(indTrain); 
        %NValidate = length(indValidate);

        % Select GMM parameters for each order
        for m = 1 : M
            % Non?Built?In: run EM algorith to estimate parameters
            GMModel = fitgmdist(dTrain',m,'RegularizationValue',1e-10);
            alpha = GMModel.ComponentProportion;%calculated alhpha
            mu = (GMModel.mu)';%calculated mu
            sigma = GMModel.Sigma;%calculated sigma
            %log-likelihood performence

            % Calculate log?likelihood performance with new parameters
            perf_array(k, m) = sum(log(evalGMM(dValidate, alpha, mu, sigma)));
            %keyboard;
        end
    end

    % Calculate average performance for each M and find best
    avg_perf = sum(perf_array) / K;
    %best_GMM = find(avg_perf == max(avg_perf), 1);
    %best_GMM = find(avg_perf == max(avg_perf), 1);
    [~, best_GMM] = max(avg_perf);

end

function [alpha_e,mu,Sigma] = EMforGMM(M,x,N)
    %M:order, x:dataset, N:number of x, Valset: validateset
    % Generates N samples from a specified GMM,
    % then uses EM algorithm to estimate the parameters
    % of a GMM that has the same number of components
    % as the true GMM that generates the samples.

    delta = 0.2; % tolerance for EM stopping criterion
    regWeight = 1e-2; % regularization parameter for covariance estimates
    d = size(x,1);

    % Initialize the GMM to randomly selected samples
    alpha_e = ones(1,M)/M;
    %shuffle the dataset 
    shuffledIndices = randperm(N);
    mu = x(:,shuffledIndices(1:M)); % pick M random samples as initial mean estimates

    [~,assignedCentroidLabels] = min(pdist2(mu',x'),[],1); % assign each sample to the nearest mean
    for m = 1:M % use sample covariances of initial assignments as initial covariance estimates
        Sigma(:,:,m) = cov(x(:,find(assignedCentroidLabels==m))') + regWeight*eye(d,d);
    end
    %Run EM algorithm
    t = 0; 
    Converged = 0; % Not converged at the beginning
    % while ~Converged
    for i=1:10000    %Calculate GMM distribution according to parameters
        for l = 1:M
            temp(l,:) = repmat(alpha_e(l),1,N).*evalGaussian(x,mu(:,l),Sigma(:,:,l));
        end
        plgivenx = temp./sum(temp,1);
        alphaNew = mean(plgivenx,2);
        w = plgivenx./repmat(sum(plgivenx,2),1,N);
        muNew = x*w';
        for l = 1:M
            v = x-repmat(muNew(:,l),1,N);
            u = repmat(w(l,:),d,1).*v;
            SigmaNew(:,:,l) = u*v' + regWeight*eye(d,d); % adding a small regularization term
        end
        Dalpha = sum(abs(alphaNew-alpha_e'));
        Dmu = sum(sum(abs(muNew-mu)));
        DSigma = sum(sum(abs(abs(SigmaNew-Sigma))));
        Converged = ((Dalpha+Dmu+DSigma)<delta); % Check if converged
        alpha_e = alphaNew; mu = muNew; Sigma = SigmaNew;
        t = t+1; 
        i=i+1;
    end
end

function gmm = evalGMM(x, alpha, mu, Sigma)
    % Evaluates GMM on the grid based on parameter values given 
    gmm = zeros(1, size(x, 2));
    for m = 1 : length(alpha)
        gmm = gmm + alpha(m) * evalGaussian(x, mu(:, m), Sigma(:, :, m));
    end
end
