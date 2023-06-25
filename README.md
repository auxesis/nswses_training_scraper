# NSW SES training scraper

Scrapes training courses and workshops for NSW SES members published at https://nswses.axcelerate.com.au/

> **Note**
>
> If you just want the scraped data, [download the SQLite database](https://github.com/auxesis/nswses_training_scraper/releases/tag/scraper).

## Quickstart

To run locally:

``` bash
# Clone the repo
git clone https://github.com/auxesis/nswses_training_scraper
cd nswses_training_scraper

# Install dependencies
bundle

# Run the scraper
bundle exec ruby scraper.rb

# Query the data
sqlite3 data.sqlite 'select count(*) from workshops'
```
