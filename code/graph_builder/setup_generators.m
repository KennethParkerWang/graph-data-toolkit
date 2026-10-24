function root_dir = setup_generators()
%SETUP_GENERATORS Add the generator folders to the MATLAB search path.
% Locate resources from this file, independently of the working directory.
root_dir = fileparts(mfilename('fullpath'));
addpath(root_dir);
addpath(fullfile(root_dir, 'common'));
addpath(fullfile(root_dir, 'directed'));
addpath(fullfile(root_dir, 'undirected'));
addpath(fullfile(root_dir, 'io'));
if isfolder(fullfile(root_dir, 'batch'))
    addpath(fullfile(root_dir, 'batch'));
end
end
