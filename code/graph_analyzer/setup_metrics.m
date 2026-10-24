function root = setup_metrics()
%SETUP_METRICS Register metrics and shared task storage; use graph-v1 as given.
root=fileparts(mfilename('fullpath')); addpath(root);
addpath(fullfile(fileparts(root),'graph_builder','io'));
end
