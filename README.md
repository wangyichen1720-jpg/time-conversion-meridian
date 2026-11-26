# Meridian

Meridian is a native macOS menu bar time converter. It requires macOS 13 or later.

## Use

1. Open Meridian.app. The menu bar shows the live date and 24-hour time in your chosen local zone, such as **SH·Dec 22 20:30** for Shanghai. When the selected match names a source zone, its date and time appear on a second line in the same format, such as **LA·Dec 22 04:30** for Los Angeles. Change **Show detected zone’s live time in menu bar** in Settings to turn the second clock on or off. Click the icon or the date to show or dismiss the converter. It stays open while you use other apps or choose an image.
2. Click the city under the large clock or open **Settings → My local time zone**. Choose a city or **Follow my Mac**. Meridian remembers this and your clock-format preference.
3. Type a time, drop an image onto the menu bar icon or screenshot area, or paste a copied screenshot with **⌘V**. Click the drop area to open an image file. Text recognition runs on the Mac.
4. Read **Detected time** and **Converted time** side by side. Each shows the weekday, month, day, time zone and UTC offset for the selected instant. Edit any recognized text in the input box. Use the arrows to review multiple matches and **Copy result** to copy the selected conversion.

The clock shows the current time in the destination zone until it has a conversion to display. The display omits the year. A year supplied in the input still determines the correct calendar date and time zone offset.

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
