# SPDX-License-Identifier: AGPL-3.0-or-later
"""Wikidata engine stub - disabled to avoid Wikimedia WDQS 403 blocks.

Other engines (openstreetmap) import helpers from this module, so we provide
no-op stubs for those symbols as well.
"""

about = {
    "website": 'https://wikidata.org/',
    "wikidata_id": 'Q2013',
    "official_api_documentation": 'https://query.wikidata.org/',
    "use_official_api": True,
    "require_api_key": False,
    "results": 'JSON',
}

display_type = ["infobox"]


def send_wikidata_query(_query, **_kwargs):
    return None


def sparql_string_escape(text):
    return text


def get_thumbnail(_item):
    return None


def init(_):
    pass


def request(query, params):
    return params


def response(_):
    return []
