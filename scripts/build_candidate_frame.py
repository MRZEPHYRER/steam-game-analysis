"""Build or resume the real Steam candidate sampling frame."""

from __future__ import annotations

import argparse
import logging
import os
import sys
from pathlib import Path

import pandas as pd

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from config.settings import (
    APPDETAILS_METADATA_PATH,
    APPDETAILS_PREFLIGHT_AUDIT_PATH,
    APPDETAILS_PREFLIGHT_ELIGIBLE_PATH,
    APPDETAILS_PREFLIGHT_GENRES_PATH,
    APPDETAILS_PREFLIGHT_METADATA_PATH,
    APPDETAILS_PREFLIGHT_RAW_DATA_DIR,
    APPDETAILS_PREFLIGHT_REPORT_PATH,
    APPDETAILS_PREFLIGHT_SAMPLE_PATH,
    APPDETAILS_RAW_DATA_DIR,
    CANDIDATE_CANONICAL_PATH,
    CANDIDATE_CATALOG_MATCH_PATH,
    CANDIDATE_DISCOVERED_PATH,
    CATALOG_CHECKPOINT_PATH,
    CATALOG_RAW_DATA_DIR,
    ELIGIBILITY_AUDIT_PATH,
    ELIGIBLE_SAMPLING_FRAME_PATH,
    END_DATE,
    LOG_DIR,
    OFFICIAL_CATALOG_PATH,
    RANDOM_SEED,
    SAMPLE_GAMES_PATH,
    SEARCH_CHECKPOINT_PATH,
    SEARCH_RAW_DATA_DIR,
    START_DATE,
    STEP2_REPORT_PATH,
    TARGET_SAMPLE_SIZE,
)
from src.catalog import (
    api_key_is_configured,
    collect_official_game_catalog,
    match_candidates_to_catalog,
)
from src.eligibility import build_eligibility_frame, collect_candidate_appdetails
from src.finalization import (
    TechnicalFailureBlock,
    validate_audit_coverage,
    validate_eligible_frame,
    validate_final_sample,
    validate_metadata_finalization,
)
from src.io_utils import atomic_write_csv
from src.preflight import (
    build_genre_relations,
    build_preflight_report,
    build_study_window_population,
    preflight_sample_as_candidates,
    select_preflight_sample,
)
from src.reporting import build_step2_report
from src.sampling import canonicalize_candidates, proportional_stratified_sample
from src.search_collector import collect_search_candidates
from src.steam_client import SteamClient
from src.utils import ensure_data_directories, load_local_env


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--restart",
        action="store_true",
        help="Clear generated collector state and restart discovery.",
    )
    parser.add_argument(
        "--discovery-only",
        action="store_true",
        help="Stop after Steam Search discovery and canonicalization.",
    )
    parser.add_argument(
        "--skip-appdetails",
        action="store_true",
        help="Stop after official catalog intersection.",
    )
    parser.add_argument(
        "--max-pages",
        type=int,
        default=None,
        help="Process at most this many Search pages in the current run.",
    )
    parser.add_argument(
        "--max-appdetails",
        type=int,
        default=None,
        help=(
            "Run a deterministic N-AppID study-window preflight; "
            "no final sample is built."
        ),
    )
    return parser.parse_args()


def configure_logging() -> logging.Logger:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    log_path = LOG_DIR / "step2_candidate_frame.log"
    console_handler = logging.StreamHandler()
    console_handler.setLevel(logging.WARNING)
    file_handler = logging.FileHandler(log_path, encoding="utf-8")
    file_handler.setLevel(logging.INFO)
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
        handlers=[console_handler, file_handler],
    )
    return logging.getLogger("step2")


def remove_downstream_outputs() -> None:
    for path in (
        CANDIDATE_CANONICAL_PATH,
        OFFICIAL_CATALOG_PATH,
        CANDIDATE_CATALOG_MATCH_PATH,
        APPDETAILS_METADATA_PATH,
        ELIGIBILITY_AUDIT_PATH,
        ELIGIBLE_SAMPLING_FRAME_PATH,
        SAMPLE_GAMES_PATH,
        STEP2_REPORT_PATH,
        CATALOG_CHECKPOINT_PATH,
    ):
        path.unlink(missing_ok=True)


def write_report(
    *,
    discovered,
    canonical,
    discovery_completed: bool,
    api_key_detected: bool,
    candidate_match=None,
    metadata=None,
    eligible=None,
    audit=None,
    sample=None,
) -> None:
    build_step2_report(
        STEP2_REPORT_PATH,
        discovered=discovered,
        canonical=canonical,
        candidate_match=candidate_match,
        metadata=metadata,
        eligible=eligible,
        audit=audit,
        sample=sample,
        discovery_completed=discovery_completed,
        api_key_detected=api_key_detected,
    )


def run_appdetails_preflight(
    client: SteamClient,
    *,
    sample_size: int,
    logger: logging.Logger,
) -> int:
    """Run an isolated deterministic preflight without rebuilding prior stages."""
    required_files = (
        CANDIDATE_CANONICAL_PATH,
        OFFICIAL_CATALOG_PATH,
        CANDIDATE_CATALOG_MATCH_PATH,
    )
    missing = [str(path) for path in required_files if not path.exists()]
    if missing:
        raise FileNotFoundError(
            "Preflight requires completed Step 2A/2B files: " + ", ".join(missing)
        )

    candidate_match = pd.read_csv(CANDIDATE_CATALOG_MATCH_PATH)
    source_population = build_study_window_population(candidate_match)
    sample = select_preflight_sample(source_population, sample_size=sample_size)
    atomic_write_csv(APPDETAILS_PREFLIGHT_SAMPLE_PATH, sample)

    preflight_candidates = preflight_sample_as_candidates(sample)
    metadata, metadata_complete = collect_candidate_appdetails(
        client,
        preflight_candidates,
        raw_dir=APPDETAILS_PREFLIGHT_RAW_DATA_DIR,
        output_path=APPDETAILS_PREFLIGHT_METADATA_PATH,
        logger=logger,
    )
    if not metadata_complete:
        raise RuntimeError("Preflight collector did not process the complete sample.")

    eligible, audit = build_eligibility_frame(preflight_candidates, metadata)
    genres = build_genre_relations(metadata)
    atomic_write_csv(APPDETAILS_PREFLIGHT_ELIGIBLE_PATH, eligible)
    atomic_write_csv(APPDETAILS_PREFLIGHT_AUDIT_PATH, audit)
    atomic_write_csv(APPDETAILS_PREFLIGHT_GENRES_PATH, genres)
    build_preflight_report(
        APPDETAILS_PREFLIGHT_REPORT_PATH,
        source_population=source_population,
        sample=sample,
        metadata=metadata,
        audit=audit,
        genre_relations=genres,
    )

    print(f"[INFO] Study-window source population: {len(source_population):,}")
    print(f"[INFO] Deterministic preflight sample: {len(sample)}")
    print(
        "[INFO] appdetails successes: "
        f"{int((metadata['appdetails_status'] == 'success').sum())}"
    )
    print(f"[INFO] Eligible in preflight: {int(audit['is_eligible'].sum())}")
    print("[STOP] appdetails preflight complete; full collection not started.")
    return 0


def main() -> int:
    args = parse_args()
    if args.max_pages is not None and args.max_pages <= 0:
        raise SystemExit("--max-pages must be positive.")
    if args.max_appdetails is not None and args.max_appdetails <= 0:
        raise SystemExit("--max-appdetails must be positive.")

    ensure_data_directories()
    load_local_env(PROJECT_ROOT / ".env")
    api_key = os.getenv("STEAM_API_KEY")
    key_detected = api_key_is_configured(api_key)
    logger = configure_logging()

    if key_detected:
        print("[INFO] Steam Web API key detected: YES")
    else:
        print("[WARNING] STEAM_API_KEY not configured.")
        print("[INFO] Step 2A can continue.")

    if args.restart:
        if args.max_appdetails is not None:
            raise SystemExit("--restart cannot be combined with appdetails preflight.")
        remove_downstream_outputs()

    with SteamClient(logger=logger) as client:
        if args.max_appdetails is not None:
            return run_appdetails_preflight(
                client,
                sample_size=args.max_appdetails,
                logger=logger,
            )

        discovered, search_checkpoint = collect_search_candidates(
            client,
            raw_dir=SEARCH_RAW_DATA_DIR,
            checkpoint_path=SEARCH_CHECKPOINT_PATH,
            output_path=CANDIDATE_DISCOVERED_PATH,
            max_pages=args.max_pages,
            restart=args.restart,
            logger=logger,
        )
        canonical = canonicalize_candidates(discovered, START_DATE, END_DATE)
        atomic_write_csv(CANDIDATE_CANONICAL_PATH, canonical)

        discovery_completed = bool(search_checkpoint["completed"])
        if not discovery_completed:
            print(
                "[INFO] Search discovery checkpoint saved; rerun without "
                "--restart to resume."
            )
            write_report(
                discovered=discovered,
                canonical=canonical,
                discovery_completed=False,
                api_key_detected=key_detected,
            )
            return 0

        if args.discovery_only:
            print("[SKIP] Official Steam Game Catalog validation (--discovery-only).")
            write_report(
                discovered=discovered,
                canonical=canonical,
                discovery_completed=True,
                api_key_detected=key_detected,
            )
            return 0

        if not key_detected:
            print("[SKIP] Official Steam Game Catalog validation.")
            write_report(
                discovered=discovered,
                canonical=canonical,
                discovery_completed=True,
                api_key_detected=False,
            )
            return 0

        assert api_key is not None
        catalog, _ = collect_official_game_catalog(
            client,
            api_key=api_key,
            raw_dir=CATALOG_RAW_DATA_DIR,
            checkpoint_path=CATALOG_CHECKPOINT_PATH,
            output_path=OFFICIAL_CATALOG_PATH,
            restart=args.restart,
            logger=logger,
        )
        candidate_match = match_candidates_to_catalog(canonical, catalog)
        atomic_write_csv(CANDIDATE_CATALOG_MATCH_PATH, candidate_match)
        study_population = build_study_window_population(candidate_match)

        if args.skip_appdetails:
            print("[SKIP] appdetails eligibility validation (--skip-appdetails).")
            write_report(
                discovered=discovered,
                canonical=canonical,
                discovery_completed=True,
                api_key_detected=True,
                candidate_match=candidate_match,
            )
            return 0

        metadata, metadata_complete = collect_candidate_appdetails(
            client,
            study_population,
            raw_dir=APPDETAILS_RAW_DATA_DIR,
            output_path=APPDETAILS_METADATA_PATH,
            logger=logger,
        )
        if not metadata_complete:
            raise RuntimeError("Full appdetails collection ended before completion.")
        try:
            validate_metadata_finalization(study_population, metadata)
        except TechnicalFailureBlock as exc:
            print(
                "[BLOCK] Full appdetails collection contains unresolved "
                "technical failures."
            )
            print(f"request_failed: {exc.request_failed}")
            print(f"schema_invalid: {exc.schema_invalid}")
            print("Rerun the command to retry request_failed AppIDs.")
            write_report(
                discovered=discovered,
                canonical=canonical,
                discovery_completed=True,
                api_key_detected=True,
                candidate_match=candidate_match,
                metadata=metadata,
            )
            return 2

        eligible, audit = build_eligibility_frame(study_population, metadata)
        validate_audit_coverage(study_population, audit)
        validate_eligible_frame(eligible)
        sample = proportional_stratified_sample(
            eligible,
            target_size=TARGET_SAMPLE_SIZE,
            random_seed=RANDOM_SEED,
            start_date=START_DATE,
            end_date=END_DATE,
        )
        validate_final_sample(eligible, sample, target_size=TARGET_SAMPLE_SIZE)
        if len(eligible) < TARGET_SAMPLE_SIZE:
            print(
                "[WARNING] Eligible population is below the 3,000 target; "
                "the documented full-pool fallback was used."
            )
        atomic_write_csv(ELIGIBLE_SAMPLING_FRAME_PATH, eligible)
        atomic_write_csv(ELIGIBILITY_AUDIT_PATH, audit)
        atomic_write_csv(SAMPLE_GAMES_PATH, sample)
        write_report(
            discovered=discovered,
            canonical=canonical,
            discovery_completed=True,
            api_key_detected=True,
            candidate_match=candidate_match,
            metadata=metadata,
            eligible=eligible,
            audit=audit,
            sample=sample,
        )

    print("[OK] Step 2 candidate sampling frame completed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
