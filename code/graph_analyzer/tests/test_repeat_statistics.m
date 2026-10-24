function report=test_repeat_statistics()
%TEST_REPEAT_STATISTICS Analytic moments, masks, independence and persistence.
t=tic; checks=0;
values=[1 2 3 4;NaN 2 4 NaN;NaN NaN NaN NaN;7 NaN NaN NaN;5 5 5 5];
valid=isfinite(values); options=struct('confidence_method','student_t','quantile_probabilities',[0 .25 .5 .75 1]);
propagate=mc.repeat_statistics(values,valid,options);
assert(isequal(propagate.count_valid,[4;2;0;1;4])); checks=checks+1;
assert(isequal(propagate.count_used,[4;0;0;0;4])); checks=checks+1;
assert(isequal(propagate.mean_valid,[true;false;false;false;true])); checks=checks+1;
assert(propagate.mean(1)==2.5&&abs(propagate.sample_std(1)-sqrt(5/3))<1e-14); checks=checks+1;
assert(isequal(propagate.quantiles(1,:),[1 1.75 2.5 3.25 4])); checks=checks+1;
critical=3.182446305284263; expected=critical*sqrt(5/3)/2;
assert(abs(propagate.ci_lower(1)-(2.5-expected))<1e-10&&abs(propagate.ci_upper(1)-(2.5+expected))<1e-10); checks=checks+1;
assert(propagate.ci_lower(5)==5&&propagate.ci_upper(5)==5&&propagate.sample_std(5)==0); checks=checks+1;
options.missing_policy='available_case'; available=mc.repeat_statistics(values,valid,options);
assert(isequal(available.count_used,[4;2;0;1;4])); checks=checks+1;
assert(available.mean(2)==3&&abs(available.sample_std(2)-sqrt(2))<1e-14); checks=checks+1;
assert(abs(available.ci_upper(2)-(3+12.7062047364321))<1e-9); checks=checks+1;
assert(~available.mean_valid(3)&&all(~available.quantile_valid(3,:))); checks=checks+1;
assert(available.mean(4)==7&&all(available.quantiles(4,:)==7)&&~available.sample_std_valid(4)&&~available.ci_valid(4)); checks=checks+1;
none=mc.repeat_statistics(values,valid); assert(all(~none.ci_valid)); checks=checks+1;
extreme=mc.repeat_statistics([-realmax realmax],[true true],struct('quantile_probabilities',[0 .5 1]));
assert(isequal(extreme.quantiles,[-realmax 0 realmax])&&all(extreme.quantile_valid)); checks=checks+1;
% Invalid values are excluded using masks, never replaced with zeros.
s=mc.repeat_statistics([1 100 3],[true false true],struct('missing_policy','available_case'));
assert(s.mean==2&&s.count_used==2); checks=checks+1;
for opts={struct('missing_policy','omit'),struct('quantile_probabilities',[.9 .1]),struct('confidence_level',1),struct('confidence_method','bootstrap'),struct('typo',1)}
    must_error(@()mc.repeat_statistics(values,valid,opts{1})); checks=checks+1;
end
must_error(@()mc.repeat_statistics([1 NaN],[true true])); checks=checks+1;
must_error(@()mc.repeat_statistics(values,double(valid))); checks=checks+1;
root=fileparts(fileparts(mfilename('fullpath')));
save(fullfile(root,'validation','repeat_statistics_reference.mat'),'values','valid','propagate','available','-v7');
% Four saved seeded paths, with synthetic identities and all original repeats.
A=sparse(ones(1,3),2:4,1,4,4); c=mc.context(A+A',false);
identity=struct('graph_id',repmat('e',1,64),'topology_hash',repmat('f',1,64),'origin_graph_id',repmat('e',1,64));
p=struct('version','1.1.0','deletion_mode','fraction_grid','attack_fractions',[0 .25 .5 .75 1], ...
    'strategy','random','sample_fractions',[0 .1 .2 .25 .5 .75 1]);
base=fullfile(root,'validation',['repeat_statistics_',char(java.util.UUID.randomUUID())]); mkdir(base);
records=struct([]); seeds=[11 29 43 71];
for j=1:4
    opts=struct('protocol',p,'seed',seeds(j),'repeat_index',j,'summaries',{{'robustness_schneider'}});
    o=mc.build_run(c,identity,{'largest_component_size','global_efficiency','node_count'},opts);
    r=mc.save_run(base,o,'repeats_test'); if isempty(records), records=r; else, records(end+1)=r; end %#ok<AGROW>
end
a=mc.aggregate_repeats(base,records,'largest_component_size',struct('confidence_method','student_t'));
assert(a.statistics.number_repeats==4&&all(a.statistics.count_valid==4)); checks=checks+1;
assert(isequal(a.axes.removed_count,(0:4)')&&isequal(a.axes.actual_removed_fraction,(0:4)'/4)); checks=checks+1;
assert(isequal(a.statistics.mean,mean(a.statistics.raw_values,2))); checks=checks+1;
assert(numel(a.inputs)==4&&all(ismember([a.inputs.attack_seed],seeds))); checks=checks+1;
reverse=mc.aggregate_repeats(base,records(end:-1:1),'largest_component_size',struct('confidence_method','student_t'));
assert(strcmp(a.aggregate_id,reverse.aggregate_id)&&isequaln(a.statistics,reverse.statistics)); checks=checks+1;
b=mc.aggregate_repeats(base,records,'global_efficiency',struct('missing_policy','available_case'));
assert(all(b.statistics.count_valid(4:5)==0)&&all(~b.statistics.mean_valid(4:5))); checks=checks+1;
b=mc.aggregate_repeats(base,records,'largest_component_size',struct('source','sampled'));
assert(isequal(b.axes.removed_count,[0;0;0;1;2;3;4])&&isequal(b.statistics.mean(1),b.statistics.mean(2))); checks=checks+1;
b=mc.aggregate_repeats(base,records,'robustness_schneider',struct('source','summaries','confidence_method','student_t'));
assert(size(b.statistics.raw_values,1)==1&&abs(b.statistics.mean-mean(sum(a.statistics.raw_values(2:end,:),1)/16))<1e-14); checks=checks+1;
singleton=mc.aggregate_repeats(base,records(1),'largest_component_size',struct('confidence_method','student_t'));
assert(all(singleton.statistics.mean_valid)&&all(~singleton.statistics.ci_valid)&&all(~singleton.statistics.sample_std_valid)); checks=checks+1;
must_error(@()mc.aggregate_repeats(base,[records(1);records(1)],'largest_component_size')); checks=checks+1;
must_error(@()mc.aggregate_repeats(base,records,'degree')); checks=checks+1;
wrong=struct('metric_id','largest_component_size','parameters',struct('component_mode','strong'));
must_error(@()mc.aggregate_repeats(base,records,wrong)); checks=checks+1;
% Same seed and different repeat ID is still not an independent repeat.
opts=struct('protocol',p,'seed',seeds(1),'repeat_index',99,'summaries',{{'robustness_schneider'}});
o=mc.build_run(c,identity,{'largest_component_size','global_efficiency','node_count'},opts); duplicate=mc.save_run(base,o,'repeats_test');
must_error(@()mc.aggregate_repeats(base,[records(1);duplicate],'largest_component_size')); checks=checks+1;
opts.seed=123; foreign=identity; foreign.graph_id=repmat('a',1,64);
o=mc.build_run(c,foreign,{'largest_component_size','global_efficiency','node_count'},opts); other=mc.save_run(base,o,'repeats_test');
must_error(@()mc.aggregate_repeats(base,[records(1);other],'largest_component_size')); checks=checks+1;
o=mc.build_run(c,identity,{'largest_component_size'},struct()); deterministic=mc.save_run(base,o,'repeats_test');
must_error(@()mc.aggregate_repeats(base,deterministic,'largest_component_size')); checks=checks+1;
tampered=records; tampered(1).file_sha256=repmat('0',1,64);
must_error(@()mc.aggregate_repeats(base,tampered,'largest_component_size')); checks=checks+1;
[saved,resumed]=mc.save_repeat_summary(base,a); assert(~resumed); checks=checks+1;
loaded=load(mc.safe_path(base,saved.path),'aggregate'); assert(isequaln(loaded.aggregate,a)); checks=checks+1;
[same,resumed]=mc.save_repeat_summary(base,a); assert(resumed&&strcmp(same.file_sha256,saved.file_sha256)); checks=checks+1;
bad=a; bad.statistics.mean(2)=123; must_error(@()mc.validate_repeat_summary(bad)); checks=checks+1;
bad=a; bad.inputs(1).attack_seed=999; must_error(@()mc.validate_repeat_summary(bad)); checks=checks+1;
bad=a; bad.axes.observation_index=[]; must_error(@()mc.validate_repeat_summary(bad)); checks=checks+1;
bad=a; bad.axes.actual_removed_fraction(:)=99; must_error(@()mc.save_repeat_summary(base,bad)); checks=checks+1;
bad=a; bad.statistics=mc.repeat_statistics(a.statistics.raw_values+100,a.statistics.raw_valid_mask,a.statistics.options);
must_error(@()mc.save_repeat_summary(base,bad)); checks=checks+1;
bad=a; bad.observation_status{1}='failed'; must_error(@()mc.save_repeat_summary(base,bad)); checks=checks+1;
% Confirm saved per-repeat files survive derived publication unchanged.
for j=1:4, mc.verify_record(base,records(j)); checks=checks+1; end
[~,fixture_name]=fileparts(base);
report=struct('checks',checks,'seconds',toc(t),'status','passed','fixture_root',['validation/',fixture_name],'aggregate_record',saved);
mc.write_text_atomic(fullfile(root,'validation','repeat_statistics_test_report.json'),jsonencode(report,'PrettyPrint',true),true);
end
function must_error(fn)
failed=false; try, fn(); catch, failed=true; end
assert(failed,'Expected validation failure.');
end
