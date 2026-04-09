from code.work_timer import get_public_holidays, to_display
import csv

holidays = get_public_holidays(start_year=2026, years=11)
out = 'feiertage_erlangen_2026-2036.csv'
with open(out, 'w', encoding='utf-8', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['Datum', 'Name'])
    for d in sorted(holidays.keys()):
        writer.writerow([to_display(d), holidays[d]])
print('Wrote', out)
