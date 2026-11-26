# Meridian

Meridian is a native macOS menu bar time converter. It requires macOS 13 or later.

## Use

1. Open Meridian.app. Click the clock icon in the menu bar to reopen it.
2. Click the city under the large clock or open **Settings → My local time zone**. Choose a city or **Follow my Mac**. Meridian remembers this and your clock-format preference.
3. Type a time, drop an image onto the menu bar icon or screenshot area, or paste a copied screenshot with **⌘V**. Click the drop area to open an image file. Text recognition runs on the Mac.
4. Read the destination date and time at the top. Edit any recognized text in the input box. Use the arrows to review multiple matches and **Copy result** to copy the selected conversion.

The clock shows the current time in the destination zone until it has a conversion to display. The small source line under a converted result shows the original time and source date.

## Input examples

| Input | Interpretation |
| --- | --- |
| 9:30 AM Tokyo | A city’s local time |
| 2026-12-31 11:45 PM New York | A time on a specified date |
| 18:00 UTC+05:45 | A fixed offset |
| Tomorrow 3 PM PT | The following day in US Pacific time |
| 2026-11-25T14:00:00Z | A UTC timestamp |
| 09:00 | The default source zone configured in the app |

City names and regional forms such as ET and PT follow the zone’s historical and seasonal rules. Explicit abbreviations such as EST and PDT use their named fixed offsets. For an ambiguous abbreviation such as CST, choose a meaning in the converter. Use a city, a full IANA identifier, or a UTC offset when a place is unclear. The parser recognizes English time and date expressions. Use an ISO date or spell out the month for numeric dates that could be misread.

Undated times default to today in the source zone. **Settings → Choose a source date** changes the date used for undated input for the current session. Dates in the text take precedence. A nonexistent spring-forward time produces a message. A repeated fall-back time produces two results in chronological order.

For a screenshot copied to the Mac clipboard, press **Control–Shift–Command–4**, select the area containing the time and zone, open Meridian, and press **⌘V**.

## Build

Run `./build.sh` with the macOS Command Line Tools installed. The script creates a universal, ad-hoc-signed app in `build/`. An optional argument chooses the output directory.

## Test

Run `./test.sh` in a normal macOS login session. The tests cover parser and calendar behavior and generate an image to exercise Vision recognition through to the converted date in Seoul. Vision requires access to the macOS recognition service.
