"""Load the per-class defaults table."""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path

DEFAULT_CONFIG_PATH = Path(__file__).with_name("road_classes.json")


@dataclass(frozen=True)
class ClassDefaults:
    lanes: int
    lanes_oneway: int
    speed_kph: int
    cluster_radius_m: float
    max_grade: float


@dataclass(frozen=True)
class ImportConfig:
    lane_width_m: float
    bbox_edge_margin_m: float
    bridge_clearance_m: float
    water_depth_m: float
    buildings: dict
    pedestrian: dict
    barriers: dict
    forks: dict
    clusters: dict
    drivable_classes: tuple[str, ...]
    pedestrian_classes: tuple[str, ...]
    excluded_highway_values: frozenset[str]
    excluded_service_values: frozenset[str]
    excluded_access_values: frozenset[str]
    parking: dict
    bridges: dict
    implied_oneway_classes: frozenset[str]
    major_classes: frozenset[str]
    likely_real_dead_end_classes: frozenset[str]
    defaults: dict[str, ClassDefaults] = field(default_factory=dict)
    source_path: str = ""

    def for_class(self, road_class: str) -> ClassDefaults:
        """Defaults for a road class; raises KeyError for classes not in the table."""
        return self.defaults[road_class]


def load_config(path: Path = DEFAULT_CONFIG_PATH) -> ImportConfig:
    """Read road_classes.json and check every drivable class has defaults."""
    raw = json.loads(path.read_text(encoding="utf-8"))
    defaults = {name: ClassDefaults(**values) for name, values in raw["defaults"].items()}
    cfg = ImportConfig(
        lane_width_m=float(raw["lane_width_m"]),
        bbox_edge_margin_m=float(raw["bbox_edge_margin_m"]),
        bridge_clearance_m=float(raw["bridge_clearance_m"]),
        water_depth_m=float(raw.get("water_depth_m", 1.5)),
        buildings=dict(raw.get("buildings", {})),
        pedestrian=dict(raw.get("pedestrian", {})),
        barriers=dict(raw.get("barriers", {})),
        forks=dict(raw.get("forks", {})),
        clusters=dict(raw.get("clusters", {})),
        drivable_classes=tuple(raw["drivable_classes"]),
        pedestrian_classes=tuple(raw["pedestrian_classes"]),
        excluded_highway_values=frozenset(raw["excluded_highway_values"]),
        excluded_service_values=frozenset(raw["excluded_service_values"]),
        excluded_access_values=frozenset(raw["excluded_access_values"]),
        parking=dict(raw.get("parking", {})),
        bridges=dict(raw.get("bridges", {})),
        implied_oneway_classes=frozenset(raw["implied_oneway_classes"]),
        major_classes=frozenset(raw["major_classes"]),
        likely_real_dead_end_classes=frozenset(raw["likely_real_dead_end_classes"]),
        defaults=defaults,
        source_path=str(path),
    )
    missing = [c for c in cfg.drivable_classes if c not in cfg.defaults]
    if missing:
        raise ValueError(f"{path}: drivable classes without defaults: {missing}")
    return cfg
