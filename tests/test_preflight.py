from __future__ import annotations

import json
from pathlib import Path

import pandas as pd

from src.eligibility import collect_candidate_appdetails
from src.preflight import (
    build_genre_relations,
    build_study_window_population,
    select_preflight_sample,
)
from src.steam_client import JSONResponse


def test_study_population_filters_date_and_catalog_then_samples_all_months() -> None:
    rows = []
    appid = 1
    for month in range(7, 13):
        for day in (1, 2):
            rows.append(
                {
                    "appid": appid,
                    "name": f"Game {appid}",
                    "release_date": f"2025-{month:02d}-{day:02d}",
                    "in_official_game_catalog": True,
                    "search_rank": appid,
                    "candidate_collected_at": "2026-09-12T00:00:00+00:00",
                }
            )
            appid += 1
    rows.extend(
        [
            {
                "appid": 100,
                "name": "Outside",
                "release_date": "2026-01-01",
                "in_official_game_catalog": True,
            },
            {
                "appid": 101,
                "name": "Unmatched",
                "release_date": "2025-08-01",
                "in_official_game_catalog": False,
            },
        ]
    )
    population = build_study_window_population(pd.DataFrame(rows))
    assert len(population) == 12

    first = select_preflight_sample(population, sample_size=6)
    second = select_preflight_sample(population, sample_size=6)
    pd.testing.assert_frame_equal(first, second)
    assert first["release_month"].value_counts().to_dict() == {
        f"2025-{month:02d}": 1 for month in range(7, 13)
    }


def test_genres_are_normalized_to_relation_rows() -> None:
    metadata = pd.DataFrame(
        [
            {
                "appid": 1,
                "genres": json.dumps(
                    [
                        {"id": "1", "description": "Action"},
                        {"id": "2", "description": "Indie"},
                    ]
                ),
            },
            {"appid": 2, "genres": None},
        ]
    )
    relations = build_genre_relations(metadata)
    assert relations.to_dict(orient="records") == [
        {"appid": 1, "genre_id": "1", "genre_name": "Action"},
        {"appid": 1, "genre_id": "2", "genre_name": "Indie"},
    ]


class FakeAppdetailsClient:
    def get_json(self, _url, *, params, collector, context) -> JSONResponse:
        del collector, context
        requested = int(params["appids"])
        returned = requested if requested == 1 else 999
        payload = {
            str(requested): {
                "success": True,
                "data": {
                    "steam_appid": returned,
                    "type": "game",
                    "name": f"Game {requested}",
                    "is_free": False,
                    "release_date": {"coming_soon": False, "date": "1 Jul, 2025"},
                    "platforms": {"windows": True, "mac": False, "linux": False},
                    "price_overview": {
                        "currency": "USD",
                        "initial": 1999,
                        "final": 999,
                        "discount_percent": 50,
                    },
                },
            }
        }
        return JSONResponse(payload, 200, "2026-09-12T00:00:00+00:00")


def test_one_schema_invalid_app_is_isolated_and_raw_is_preserved(
    tmp_path: Path,
) -> None:
    candidates = pd.DataFrame(
        {
            "appid": [1, 2],
            "in_official_game_catalog": [True, True],
        }
    )
    raw_dir = tmp_path / "raw"
    output = tmp_path / "metadata.csv"
    metadata, complete = collect_candidate_appdetails(
        FakeAppdetailsClient(),  # type: ignore[arg-type]
        candidates,
        raw_dir=raw_dir,
        output_path=output,
        show_progress=False,
    )
    assert complete is True
    assert metadata["appdetails_status"].tolist() == ["success", "schema_invalid"]
    assert (raw_dir / "appdetails_0000000001.json").exists()
    assert (raw_dir / "appdetails_0000000002.json").exists()
    first_raw = json.loads(
        (raw_dir / "appdetails_0000000001.json").read_text(encoding="utf-8")
    )
    assert first_raw["appid"] == 1
    assert isinstance(first_raw["appid"], int)
    assert output.exists()
    assert metadata.loc[0, "list_price_cents"] == 1999
