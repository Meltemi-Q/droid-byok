"""
test_schema.py - 校验所有 preset 文件的 schema 有效性
"""

import os
import sys
import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'scripts'))
from install import get_all_presets
from validate import validate_schema

VALID_PROVIDERS = ['generic-chat-completion-api', 'anthropic', 'openai', 'zai']


def get_preset_ids():
    presets = get_all_presets()
    return [(p['_file'].replace('.yaml', ''), p) for p in presets]


@pytest.mark.parametrize("name,preset", get_preset_ids(), ids=[x[0] for x in get_preset_ids()])
def test_preset_schema(name, preset):
    errors = validate_schema(preset, name)
    assert not errors, f"Schema errors in {name}: {errors}"


@pytest.mark.parametrize("name,preset", get_preset_ids(), ids=[x[0] for x in get_preset_ids()])
def test_preset_has_models(name, preset):
    models = preset.get('models', preset.get('_models', []))
    assert len(models) > 0, f"{name} has no models defined"


@pytest.mark.parametrize("name,preset", get_preset_ids(), ids=[x[0] for x in get_preset_ids()])
def test_preset_has_region(name, preset):
    regions = preset.get('regions', preset.get('_regions', {}))
    assert isinstance(regions, dict) and len(regions) > 0, f"{name} has no regions"


@pytest.mark.parametrize("name,preset", get_preset_ids(), ids=[x[0] for x in get_preset_ids()])
def test_provider_valid(name, preset):
    provider = preset.get('provider', '')
    assert provider in VALID_PROVIDERS, f"{name} has invalid provider: {provider}"
