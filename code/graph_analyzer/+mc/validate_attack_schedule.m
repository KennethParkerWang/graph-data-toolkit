function validate_attack_schedule(p)
%VALIDATE_ATTACK_SCHEDULE Stored scheduling rules without registry resolution.
% Safe for legacy records whose ranking metric version is no longer installed.
required={'version','target','deletion_mode','batch_size','stop_fraction','rounding'};
if ~isstruct(p)||~isscalar(p)||~all(isfield(p,required))
    error('mc:InvalidProtocol','Missing scheduling fields.');
end
choice(p.version,{'1.0.0','1.1.0'},'version');
choice(p.target,{'node','edge'},'target');
choice(p.deletion_mode,{'single','batch','fraction_grid'},'deletion_mode');
choice(p.rounding,{'floor','ceil','nearest'},'rounding');
v=p.batch_size;
if ~isnumeric(v)||~isreal(v)||~isscalar(v)||~isfinite(v)||v<1||v~=fix(v)
    error('mc:InvalidProtocol','batch_size must be a positive integer.');
end
f=p.stop_fraction;
if ~isnumeric(f)||~isreal(f)||~isscalar(f)||~isfinite(f)||f<0||f>1
    error('mc:InvalidProtocol','stop_fraction must lie in [0,1].');
end
if strcmp(p.deletion_mode,'single')&&p.batch_size~=1
    error('mc:InvalidProtocol','Single deletion requires batch_size=1.');
end
if strcmp(p.version,'1.0.0')&&isfield(p,'attack_fractions')
    error('mc:InvalidProtocol','attack_fractions is not a v1.0.0 field.');
end
if strcmp(p.version,'1.1.0')&&~isfield(p,'attack_fractions')
    error('mc:InvalidProtocol','Normalized v1.1.0 requires attack_fractions.');
end
if strcmp(p.deletion_mode,'fraction_grid')
    if ~strcmp(p.version,'1.1.0'), error('mc:InvalidProtocol','fraction_grid requires version=1.1.0.'); end
    grid=p.attack_fractions;
    if ~isnumeric(grid)||~isreal(grid)||isempty(grid)||~isvector(grid)||any(~isfinite(grid(:))) ...
            ||any(grid(:)<0|grid(:)>f)||any(diff(grid(:))<0)||grid(end)~=f
        error('mc:InvalidProtocol','attack_fractions must be nondecreasing within [0,stop_fraction] and end at stop_fraction.');
    end
    if p.batch_size~=1, error('mc:InvalidProtocol','fraction_grid requires unused batch_size=1.'); end
elseif isfield(p,'attack_fractions')&&~isempty(p.attack_fractions)
    error('mc:InvalidProtocol','attack_fractions applies only to fraction_grid.');
end
end
function choice(value,allowed,name)
if ~(ischar(value)||(isstring(value)&&isscalar(value)))||~ismember(char(value),allowed)
    error('mc:InvalidProtocol','Invalid %s.',name);
end
end
