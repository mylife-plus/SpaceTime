#!/usr/bin/env python3
"""Overwrite known-broken l10n values in en/es/fr/de (same English templates for all locales)."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
L10N = ROOT / "assets" / "l10n"

PATCH_EN = {
    "l10n_literal_none": "None",
    "snackbar_widget_failed_to_add_widget_istagmode": "Failed to add $1",
    "snackbar_widget_failed_to_add_widget_istagmode_2": "Failed to add $1",
    "snackbar_widget_failed_to_update_widget_istagmode": "Failed to update $1",
    "snackbar_widget_failed_to_update_widget_istagmode_2": "Failed to update $1",
    "snackbar_widget_moved_to_location": "📍 Moved to $1",
    "snackbar_widget_moved_to_location_2": "📍 Moved to $1",
    "snackbar_widget_please_enter_a_widget_istagmode": "Please enter a $1 name",
    "snackbar_widget_please_enter_a_widget_istagmode_2": "Please enter a $1 name",
    "text_current_region_service_currentdownloadregion_value": "Current Region: $1",
    "text_downloading_currentregion_length_20": "Downloading: $1",
    "text_memory_2": "• $1",
    "text_no_widget_hint_replaceall": "No $1 found",
    "text_offline_tiles_backgroundservice_totaltilesdownloade": "Offline tiles: $1 / 30,000 required",
    "text_totaltiles_tostring_replaceallmapped_regexp_r": "$1 tiles",
}

LOCALE_PATCH = {
    "en": PATCH_EN,
    "es": {
        **{k: v for k, v in PATCH_EN.items() if k != "l10n_literal_none"},
        "l10n_literal_none": "Ninguno",
        "snackbar_widget_failed_to_add_widget_istagmode": "No se pudo añadir $1",
        "snackbar_widget_failed_to_add_widget_istagmode_2": "No se pudo añadir $1",
        "snackbar_widget_failed_to_update_widget_istagmode": "No se pudo actualizar $1",
        "snackbar_widget_failed_to_update_widget_istagmode_2": "No se pudo actualizar $1",
        "snackbar_widget_moved_to_location": "📍 Movido a $1",
        "snackbar_widget_moved_to_location_2": "📍 Movido a $1",
        "snackbar_widget_please_enter_a_widget_istagmode": "Introduce un nombre de $1",
        "snackbar_widget_please_enter_a_widget_istagmode_2": "Introduce un nombre de $1",
        "text_current_region_service_currentdownloadregion_value": "Región actual: $1",
        "text_downloading_currentregion_length_20": "Descargando: $1",
        "text_memory_2": "• $1",
        "text_no_widget_hint_replaceall": "No se encontró $1",
        "text_offline_tiles_backgroundservice_totaltilesdownloade": "Mosaicos sin conexión: $1 / 30.000 requeridos",
        "text_totaltiles_tostring_replaceallmapped_regexp_r": "$1 mosaicos",
    },
    "fr": {
        **{k: v for k, v in PATCH_EN.items() if k != "l10n_literal_none"},
        "l10n_literal_none": "Aucun",
        "snackbar_widget_failed_to_add_widget_istagmode": "Échec de l’ajout de $1",
        "snackbar_widget_failed_to_add_widget_istagmode_2": "Échec de l’ajout de $1",
        "snackbar_widget_failed_to_update_widget_istagmode": "Échec de la mise à jour de $1",
        "snackbar_widget_failed_to_update_widget_istagmode_2": "Échec de la mise à jour de $1",
        "snackbar_widget_moved_to_location": "📍 Déplacé vers $1",
        "snackbar_widget_moved_to_location_2": "📍 Déplacé vers $1",
        "snackbar_widget_please_enter_a_widget_istagmode": "Veuillez saisir un nom de $1",
        "snackbar_widget_please_enter_a_widget_istagmode_2": "Veuillez saisir un nom de $1",
        "text_current_region_service_currentdownloadregion_value": "Région actuelle : $1",
        "text_downloading_currentregion_length_20": "Téléchargement : $1",
        "text_memory_2": "• $1",
        "text_no_widget_hint_replaceall": "Aucun résultat pour $1",
        "text_offline_tiles_backgroundservice_totaltilesdownloade": "Tuiles hors ligne : $1 / 30 000 requises",
        "text_totaltiles_tostring_replaceallmapped_regexp_r": "$1 tuiles",
    },
    "de": {
        **{k: v for k, v in PATCH_EN.items() if k != "l10n_literal_none"},
        "l10n_literal_none": "Keine",
        "snackbar_widget_failed_to_add_widget_istagmode": "$1 konnte nicht hinzugefügt werden",
        "snackbar_widget_failed_to_add_widget_istagmode_2": "$1 konnte nicht hinzugefügt werden",
        "snackbar_widget_failed_to_update_widget_istagmode": "$1 konnte nicht aktualisiert werden",
        "snackbar_widget_failed_to_update_widget_istagmode_2": "$1 konnte nicht aktualisiert werden",
        "snackbar_widget_moved_to_location": "📍 Verschoben nach $1",
        "snackbar_widget_moved_to_location_2": "📍 Verschoben nach $1",
        "snackbar_widget_please_enter_a_widget_istagmode": "Bitte einen $1-Namen eingeben",
        "snackbar_widget_please_enter_a_widget_istagmode_2": "Bitte einen $1-Namen eingeben",
        "text_current_region_service_currentdownloadregion_value": "Aktuelle Region: $1",
        "text_downloading_currentregion_length_20": "Wird heruntergeladen: $1",
        "text_memory_2": "• $1",
        "text_no_widget_hint_replaceall": "Kein $1 gefunden",
        "text_offline_tiles_backgroundservice_totaltilesdownloade": "Offline-Kacheln: $1 / 30.000 erforderlich",
        "text_totaltiles_tostring_replaceallmapped_regexp_r": "$1 Kacheln",
    },
}


def main() -> None:
    en_path = L10N / "en.json"
    en_data = json.loads(en_path.read_text(encoding="utf-8"))

    for code in ("en", "es", "fr", "de"):
        path = L10N / f"{code}.json"
        data = json.loads(path.read_text(encoding="utf-8"))
        patch = LOCALE_PATCH[code]
        for k, v in patch.items():
            data[k] = v
        if code != "en":
            for k, v in list(data.items()):
                if "${" in v:
                    data[k] = en_data.get(k, v)
        path.write_text(
            json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
    print("Patched", len(PATCH_EN), "keys × 4 locales + ${} leaks from en")


if __name__ == "__main__":
    main()
