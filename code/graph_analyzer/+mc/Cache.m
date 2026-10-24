classdef Cache < handle
    %CACHE Per-context reusable algorithm results; never shared across graphs.
    properties
        data = struct()
    end
end
