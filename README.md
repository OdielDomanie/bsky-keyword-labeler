# BskyLabeler

A labeler service for Bluesky that labels posts that match a pattern.

The app connects to the Jetstream and tracks likes for each new post
(`app.bsky.feed.post`) created. Once a post reaches more than `MIN_LIKES`,
it is analyzed if it matches any of the configured regexen. If it is, than a
label event is emitted to the Ozone server.

## Post Analysis

Currently the post content, image alt-texts, and OCR'ed texts of images 
without the alt-text are matched against a list of regexes.
This list is updated frequently; the file on this repo is only as an example.

I have tried using a locally hosted 1B gen-AI for classification,
but the accuracy was worse than using a word list and had weird false
positives.
For cases where the text implies its subject without using any obvious
keywords (ie. relying on the zeitgeist to get its meaning across),
even large a cloud model struggled. LLMs without further training
are sub-optimal for this task.

Currently, the majority of false-negatives are screenshots without alt-text.
The next step is to run OCR on the images. 
Testing shows it takes ~0.5 second per image on a single thread
on my local PC.

## Patterns file

`patterns.txt` file contains regexen seperated by lines.
The one on this repo is an example. 

It is reloaded automatically when modified.
If any regex is invalid an error is logged.

Each line needs to be a valid regex (PCRE2).
`u` flag is added when matching.
Lines starting with `//` and empty lines are ignored.

A line can have multiple regices seperated by "`  &&  `" (note the spaces).
That pattern will match only if all the regices match.

## Secrets
Secrets can be provided as environment variables like other config options,
or read from secrets files.
The secret files are specified by the `SECRET_FILES` environment variable
and default to `/run/secrets/bsky_labeler_secret,secret`.
(latter takes priority, comma seperated, backslash escaped)

## Config
Configuration options are to be provided as environment variables.

* `START_WEBSOCKET` — If not `true`, websocket connection to the jetstream
    to ingest bluesky events is not started.
* `LABELER_SIMULATE` — If not `true`, HTTP calls to post the labels are not
    made.
* `MIN_LIKES` — Minimum number of likes to analyze a post. Defaults to 50.
    Recommended 10.
* `REGEX_FILE` — Defaults to `patterns.txt`
* `LABELER_LABEL` — The label identifier. Required.

## Deployment

First you need to set-up Ozone:
https://github.com/bluesky-social/ozone/blob/main/HOSTING.md

If you have a previous Ozone hosting, you must re-use the same signing key.

You can co-host this app on the same host,
the described host specs on the Ozone guide is more than enough.

The deployment guide in [Deployment.md](./Deployment.md)

## Additional dependencies

### Postgres
A __Postgres__ instance with the database `bsky_labeler_repo` is required.

### Prometheus

The app has a Prometheus endpoint at `/metrics` secured with basic auth.
Several telemetry measurement are available.

## Admin dashboard (Phoenix LiveDashboard)
The admin dashboard is useful for development,
as well as to view the Postgres stats.

Since it uses basic auth. and is not served with
https, it must *not* be used over the internet.

Provide a `DASHBOARD_PASSWORD` secret to enable it.
It is served on `/admin/dashboard/` on port `4000`.

# About LLM Use
This software was written organically, *without* the need for an LLM.

# Copyright and License Notice

Copyright 2025, meozk

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program. If not, see <https://www.gnu.org/licenses/>. 
