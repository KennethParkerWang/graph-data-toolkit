function guard = gg_seed(seed)
%GG_SEED Create a repeatable random stream and restore the caller on exit.
validateattributes(seed, {'numeric'}, ...
    {'real','finite','scalar','integer','>=',0,'<=',2^32-1}, ...
    mfilename, 'seed');
previous_state = rng;
guard = onCleanup(@() rng(previous_state));
rng(full(double(seed)), 'twister');
end
