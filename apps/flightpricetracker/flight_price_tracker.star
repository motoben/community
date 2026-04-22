load("cache.star", "cache")
load("http.star", "http")
load("render.star", "render")
load("schema.star", "schema")

# App default settings
DEFAULT_ORIGIN = "FRA"
DEFAULT_DESTINATION = "LIS"
DEFAULT_DEP_DATE = "2026-05-15"

PLANE_PIXELS = [
    ".......#....",
    "......##....",
    ".....###....",
    ".##..####...",
    "############",
    ".##..####...",
    ".....###....",
    "......##....",
    ".......#....",
]

def render_plane():
    rows = []
    for row_str in PLANE_PIXELS:
        cols = []
        for char in row_str.elems():
            if char == "#":
                cols.append(render.Box(width = 1, height = 1, color = "#fff"))
            else:
                # Transparent pixel
                cols.append(render.Box(width = 1, height = 1, color = "#0000"))
        rows.append(render.Row(children = cols))

    # Wrap in a padded box to give it a little space on the sides
    return render.Padding(
        pad = (2, 0, 2, 0),
        child = render.Column(children = rows),
    )

def main(config):
    origin = config.str("origin", DEFAULT_ORIGIN).upper()
    destination = config.str("destination", DEFAULT_DESTINATION).upper()
    departure_date = config.str("departure_date", DEFAULT_DEP_DATE)
    return_date = config.str("return_date", "")
    api_key = config.str("serpapi_api_key", "")

    if not api_key:
        return display_message("API Key\nMissing", "Please add SerpApi key\nin app config.")

    # Keys for caching
    base_key = "%s_%s_%s_%s" % (origin, destination, departure_date, return_date)
    price_cache_key = "flight_info_%s" % base_key
    search_id_cache_key = "flight_search_id_%s" % base_key

    cached_info = cache.get(price_cache_key)

    best_price = "?"
    best_airline = ""
    is_searching = False

    if cached_info:
        parts = cached_info.split("|")
        best_price = parts[0]
        if len(parts) > 1:
            best_airline = parts[1]
    else:
        search_id = cache.get(search_id_cache_key)

        if search_id:
            poll_url = "https://serpapi.com/searches/%s.json?api_key=%s" % (search_id, api_key)
            res = http.get(url = poll_url)

            if res.status_code != 200:
                return display_message("API Error", "Code: %s" % res.status_code)

            data = res.json()
            status = data.get("search_metadata", {}).get("status", "")

            if status == "Processing":
                is_searching = True
            elif status == "Success":
                best_flights = data.get("best_flights", [])
                other_flights = data.get("other_flights", [])

                flight_data = None
                if len(best_flights) > 0:
                    flight_data = best_flights[0]
                elif len(other_flights) > 0:
                    flight_data = other_flights[0]

                if flight_data:
                    best_price = str(flight_data.get("price", "?"))

                    flights_arr = flight_data.get("flights", [])
                    if len(flights_arr) > 0:
                        best_airline = flights_arr[0].get("airline", "Unknown")
                    else:
                        best_airline = "Unknown"

                    cache_val = "%s|%s" % (best_price, best_airline)
                    cache.set(price_cache_key, cache_val, ttl_seconds = 21600)
                else:
                    best_price = "N/A"
                    best_airline = ""
                    cache.set(price_cache_key, "N/A|", ttl_seconds = 21600)
            else:
                return display_message("Search Failed", status)

        else:
            search_url = "https://serpapi.com/search.json"
            params = {
                "engine": "google_flights",
                "departure_id": origin,
                "arrival_id": destination,
                "outbound_date": departure_date,
                "currency": "EUR",
                "api_key": api_key,
                "hl": "en",
                "async": "true",
            }
            if return_date:
                params["return_date"] = return_date

            query_parts = []
            for k, v in params.items():
                query_parts.append("%s=%s" % (k, v))

            full_url = search_url + "?" + "&".join(query_parts)
            res = http.get(url = full_url)

            if res.status_code != 200:
                return display_message("API Error", "Code: %s" % res.status_code)

            data = res.json()
            new_search_id = data.get("search_metadata", {}).get("id")

            if new_search_id:
                cache.set(search_id_cache_key, new_search_id, ttl_seconds = 3600)
                is_searching = True
            else:
                return display_message("Search Error", "No Search ID returned")

    # Format dates
    dep_display = departure_date[5:7] + "/" + departure_date[8:10] if len(departure_date) >= 10 else departure_date
    if return_date and len(return_date) >= 10:
        ret_display = return_date[5:7] + "/" + return_date[8:10]
        dates_display = "%s - %s" % (dep_display, ret_display)
    else:
        dates_display = dep_display

    display_children = [
        # Origin -> Destination Row
        render.Row(
            expanded = True,  # Forces row to be 64px wide
            main_align = "center",
            cross_align = "center",
            children = [
                render.Text(origin, color = "#0f0"),
                render_plane(),
                render.Text(destination, color = "#0f0"),
            ],
        ),
        # Dates Row
        render.Row(
            expanded = True,
            main_align = "center",
            children = [
                render.Text(dates_display, color = "#0ff", font = "tom-thumb"),
            ],
        ),
    ]

    if is_searching:
        display_children.append(
            render.Row(
                expanded = True,
                main_align = "center",
                children = [
                    render.Text("Searching...", color = "#ffa500", font = "tom-thumb"),
                ],
            ),
        )
    elif best_price == "N/A":
        display_children.append(
            render.Row(
                expanded = True,
                main_align = "center",
                children = [
                    render.Text("No Flights", color = "#f00", font = "tom-thumb"),
                ],
            ),
        )
    else:
        # Price Row
        display_children.append(
            render.Row(
                expanded = True,
                main_align = "center",
                cross_align = "end",
                children = [
                    render.Text("Best: ", color = "#ccc", font = "tom-thumb"),
                    render.Text("\u20AC%s" % best_price, color = "#ff0"),
                ],
            ),
        )

        # Airline Row
        if best_airline:
            airline_display = best_airline if len(best_airline) < 16 else best_airline[:14] + ".."
            display_children.append(
                render.Row(
                    expanded = True,
                    main_align = "center",
                    children = [
                        render.Text(airline_display, color = "#fff", font = "tom-thumb"),
                    ],
                ),
            )

    # Main wrapper
    return render.Root(
        child = render.Column(
            expanded = True,
            main_align = "center",
            cross_align = "center",
            children = display_children,
        ),
    )

def display_message(title, subtitle):
    return render.Root(
        child = render.Column(
            expanded = True,
            main_align = "center",
            cross_align = "center",
            children = [
                render.Text(title, color = "#f00", font = "tb-8"),
                render.Text(subtitle, color = "#fff", font = "tom-thumb"),
            ],
        ),
    )

def get_schema():
    return schema.Schema(
        version = "1",
        fields = [
            schema.Text(
                id = "origin",
                name = "Origin Airport",
                desc = "3-letter code e.g. FRA",
                icon = "planeDeparture",
            ),
            schema.Text(
                id = "destination",
                name = "Destination Airport",
                desc = "3-letter code e.g. LIS",
                icon = "planeArrival",
            ),
            schema.Text(
                id = "departure_date",
                name = "Departure Date",
                desc = "YYYY-MM-DD",
                icon = "calendar",
            ),
            schema.Text(
                id = "return_date",
                name = "Return Date",
                desc = "Optional (YYYY-MM-DD)",
                icon = "calendarCheck",
            ),
            schema.Toggle(
                id = "flexible_dates",
                name = "Flexible Dates (+/- 3 days)",
                desc = "Note: Uses more SerpApi quota.",
                icon = "arrowsAltH",
                default = False,
            ),
            schema.Text(
                id = "serpapi_api_key",
                name = "SerpApi Key (Google Flights)",
                desc = "Get free key from serpapi.com",
                icon = "key",
            ),
        ],
    )
