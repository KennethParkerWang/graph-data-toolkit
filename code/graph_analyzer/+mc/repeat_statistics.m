function s=repeat_statistics(values,valid,options)
%REPEAT_STATISTICS Pointwise repeat statistics without Statistics Toolbox.
% Rows are matched observations; columns are independently seeded repeats.
% Quantiles: Hyndman-Fan type 7. SD: n-1. CI: optional pointwise Student t.
if nargin<3, options=struct(); end
defaults=struct('missing_policy','propagate','quantile_probabilities',[.025 .5 .975], ...
    'confidence_method','none','confidence_level',.95);
if ~isstruct(options)||~isscalar(options)||~isempty(setdiff(fieldnames(options),fieldnames(defaults)))
    error('mc:AggregateOptions','Unknown or invalid statistics options.');
end
for f=fieldnames(defaults)'
    if ~isfield(options,f{1}), options.(f{1})=defaults.(f{1}); end
end
if ~ismember(options.missing_policy,{'propagate','available_case'})||~ismember(options.confidence_method,{'none','student_t'})
    error('mc:AggregateOptions','missing_policy=propagate/available_case; confidence_method=none/student_t.');
end
probs=options.quantile_probabilities;
if ~isnumeric(probs)||~isreal(probs)||isempty(probs)||~isvector(probs)||any(~isfinite(probs(:)))||any(probs(:)<0|probs(:)>1)||any(diff(probs(:))<=0)
    error('mc:AggregateOptions','Quantile probabilities must be strictly increasing in [0,1].');
end
level=options.confidence_level;
if ~isnumeric(level)||~isreal(level)||~isscalar(level)||~isfinite(level)||level<=0||level>=1
    error('mc:AggregateOptions','confidence_level must lie strictly in (0,1).');
end
options.quantile_probabilities=double(probs(:)');
if ~isnumeric(values)||~isreal(values)||~ismatrix(values)||isempty(values)||~islogical(valid)||~isequal(size(values),size(valid))||any(~isfinite(values(valid)))
    error('mc:AggregateValues','Require nonempty numeric rows-by-repeats values and same-shape logical mask; valid values must be finite.');
end
[k,repeats]=size(values); q=numel(probs); counts=sum(valid,2);
s=struct('options',options,'raw_values',values,'raw_valid_mask',valid, ...
    'number_repeats',repeats,'count_valid',counts,'count_used',zeros(k,1), ...
    'mean',NaN(k,1),'mean_valid',false(k,1), ...
    'sample_std',NaN(k,1),'sample_std_valid',false(k,1), ...
    'quantiles',NaN(k,q),'quantile_valid',false(k,q), ...
    'ci_lower',NaN(k,1),'ci_upper',NaN(k,1),'ci_valid',false(k,1), ...
    'degrees_of_freedom',NaN(k,1));
for i=1:k
    n=counts(i);
    if n==0||(strcmp(options.missing_policy,'propagate')&&n~=repeats), continue; end
    x=double(values(i,valid(i,:))); s.count_used(i)=n;
    s.mean(i)=mean(x); s.mean_valid(i)=isfinite(s.mean(i));
    x=sort(x); h=1+(n-1)*options.quantile_probabilities;
    lo=floor(h); hi=ceil(h);
    weight=h-lo; left=x(lo); right=x(hi);
    % Convex interpolation avoids overflow of right-left across opposite signs.
    interpolated=(1-weight).*left+weight.*right;
    interpolated(weight==0)=left(weight==0);
    % Rounding cannot legitimately take a convex combination outside its bracket.
    s.quantiles(i,:)=min(right,max(left,interpolated));
    s.quantile_valid(i,:)=isfinite(s.quantiles(i,:));
    if n<2, continue; end % SD and mean CI cannot be estimated from one repeat.
    s.sample_std(i)=std(x,0); s.sample_std_valid(i)=isfinite(s.sample_std(i));
    s.degrees_of_freedom(i)=n-1;
    if strcmp(options.confidence_method,'student_t')
        nu=n-1; beta=betaincinv(1-level,nu/2,.5);
        critical=sqrt(nu*(1/beta-1));
        half_width=critical*s.sample_std(i)/sqrt(n);
        s.ci_lower(i)=s.mean(i)-half_width; s.ci_upper(i)=s.mean(i)+half_width;
        s.ci_valid(i)=isfinite(s.ci_lower(i))&&isfinite(s.ci_upper(i));
    end
end
end
