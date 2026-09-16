from __future__ import annotations

import json

import pandas as pd
import pytest

from src.metadata_materialization import (
    MetadataMaterializationError,
    materialize_sample_metadata,
    validate_genre_relations,
    validate_monthly_counts,
)


def source_frames(
    *,
    appids: tuple[int, ...] = (1, 2),
    free_appids: tuple[int, ...] = (2,),
) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    sample_rows = []
    metadata_rows = []
    eligible_rows = []
    for position, appid in enumerate(appids):
        month = 7 + position
        release_date = f"2025-{month:02d}-01"
        is_free = appid in free_appids
        sample_rows.append(
            {
                "appid": appid,
                "name": f"Search {appid}",
                "release_date": release_date,
                "release_month": release_date[:7],
                "developer": json.dumps([f"Developer {appid}"]),
                "publisher": json.dumps([f"Publisher {appid}"]),
                "is_free": is_free,
                "platform_windows": True,
                "platform_mac": False,
                "platform_linux": appid == 2,
                "search_release_date": release_date,
                "store_release_date": release_date,
                "release_date_conflict": False,
                "is_early_access": None,
            }
        )
        metadata_rows.append(
            {
                "appid": appid,
                "appdetails_status": "success",
                "app_type": "game",
                "store_name": f"Store {appid}",
                "is_free": is_free,
                "store_release_date": release_date,
                "platform_windows": True,
                "platform_mac": False,
                "platform_linux": appid == 2,
                "genres": json.dumps(
                    [
                        {"id": "1", "description": "Action"},
                        {"id": "2", "description": "Indie"},
                    ]
                ),
                "list_price_cents": None if is_free else 1999,
                "current_price_cents": None if is_free else 999,
                "discount_percent": None if is_free else 50,
                "price_currency": None if is_free else "USD",
                "price_overview_present": not is_free,
                "metadata_collected_at": "2026-09-12T00:00:00+00:00",
            }
        )
        eligible_rows.append({"appid": appid, "release_date": release_date})
    return (
        pd.DataFrame(sample_rows),
        pd.DataFrame(metadata_rows),
        pd.DataFrame(eligible_rows),
    )


def materialize(**kwargs) -> tuple[pd.DataFrame, pd.DataFrame]:
    sample, metadata, eligible = source_frames(**kwargs)
    return materialize_sample_metadata(sample, metadata, eligible)


def test_sample_appid_join_adds_or_removes_nothing() -> None:
    sample, metadata, eligible = source_frames()
    extras = metadata.assign(appid=[10, 11])
    metadata = pd.concat([metadata, extras], ignore_index=True)
    games, _ = materialize_sample_metadata(sample, metadata, eligible)
    assert len(games) == 2
    assert set(games["appid"]) == {1, 2}


def test_duplicate_appid_is_blocked() -> None:
    sample, metadata, eligible = source_frames()
    sample = pd.concat([sample, sample.iloc[[0]]], ignore_index=True)
    with pytest.raises(MetadataMaterializationError, match="duplicate AppID"):
        materialize_sample_metadata(sample, metadata, eligible)


def test_release_month_is_derived_from_final_store_date() -> None:
    games, _ = materialize()
    assert games.set_index("appid")["release_month"].to_dict() == {
        1: "2025-07",
        2: "2025-08",
    }


def test_cents_are_preserved_and_usd_is_derived() -> None:
    games, _ = materialize()
    paid = games.loc[games["appid"] == 1].iloc[0]
    assert paid["list_price_cents"] == 1999
    assert paid["current_price_cents"] == 999
    assert paid["list_price_usd"] == 19.99
    assert paid["current_price_usd"] == 9.99


def test_null_cents_produce_null_usd() -> None:
    games, _ = materialize()
    free = games.loc[games["appid"] == 2].iloc[0]
    assert pd.isna(free["list_price_cents"])
    assert pd.isna(free["list_price_usd"])
    assert pd.isna(free["current_price_usd"])


def test_free_game_does_not_require_price_overview() -> None:
    games, _ = materialize()
    free = games.loc[games["appid"] == 2].iloc[0]
    assert free["is_free"]
    assert not free["price_overview_present"]


def test_paid_price_overview_requires_complete_schema() -> None:
    sample, metadata, eligible = source_frames()
    metadata.loc[metadata["appid"] == 1, "price_currency"] = None
    with pytest.raises(MetadataMaterializationError, match="requires complete"):
        materialize_sample_metadata(sample, metadata, eligible)


def test_genres_normalize_to_all_relation_rows() -> None:
    _, genres = materialize()
    assert len(genres) == 4
    assert genres.groupby("appid")["genre_name"].apply(list).to_dict() == {
        1: ["Action", "Indie"],
        2: ["Action", "Indie"],
    }


def test_genre_relation_rejects_out_of_sample_appid() -> None:
    relations = pd.DataFrame(
        [{"appid": 99, "genre_id": "1", "genre_name": "Action"}]
    )
    with pytest.raises(MetadataMaterializationError, match="outside games"):
        validate_genre_relations(relations, {1, 2})


def test_monthly_sample_allocation_is_validated_exactly() -> None:
    games, _ = materialize()
    validate_monthly_counts(games, {"2025-07": 1, "2025-08": 1})
    with pytest.raises(MetadataMaterializationError, match="differs"):
        validate_monthly_counts(games, {"2025-07": 2})


def test_missing_publisher_is_allowed() -> None:
    sample, metadata, eligible = source_frames()
    sample.loc[sample["appid"] == 1, "publisher"] = None
    games, _ = materialize_sample_metadata(sample, metadata, eligible)
    assert games.loc[games["appid"] == 1, "publisher"].isna().all()


def test_early_access_remains_unknown() -> None:
    games, _ = materialize()
    assert games["is_early_access"].isna().all()
