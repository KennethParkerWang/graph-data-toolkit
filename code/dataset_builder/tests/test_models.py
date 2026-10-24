from copy import deepcopy

import numpy as np
import pytest

from dataset_builder.examples.framework_records import framework_samples
from dataset_builder.models import PipelineError


def test_unambiguous_positions_and_original_ids_are_checked():
    sample = framework_samples()[3]
    curve = deepcopy(sample.targets["curve_demo"])
    curve.axis_positions["removed_count"] = np.arange(2)
    with pytest.raises(PipelineError, match="positions length"):
        curve.validate()
    node = deepcopy(sample.features["node_demo"])
    node.node_ids = np.arange(1, 3)
    with pytest.raises(PipelineError, match="node_ids length"):
        node.validate()


def test_original_id_ranges_and_empty_graph_edges():
    sample = framework_samples()[0]
    sample.features["node_demo"].node_ids = np.arange(2, sample.graph.num_nodes + 2)
    with pytest.raises(PipelineError, match="exceeds original graph"):
        sample.validate()
    empty = framework_samples()[2]
    empty.validate()
    assert empty.graph.model_edges(True)[0].shape == (2, 0)


def test_bad_graph_endpoints_rejected():
    sample = framework_samples()[0]
    sample.graph.edge_list[0, 1] = sample.graph.num_nodes + 1
    with pytest.raises(PipelineError, match="endpoint"):
        sample.validate()
