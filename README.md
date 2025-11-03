# BskyPoliticsLabeler

A labeler service for Bluesky that labels posts about US Politics.

The app connects to the Jetstream and tracks likes for each new post (`app.bsky.feed.post`) created.
Once a post reaches more than `MIN_LIKES`, it is analyzed if it is about US Politics.
If it is, than a label event is emitted to the Ozone server.

## Post Analysis

Currently the post content and image alt-texts are matched against a list regexes.
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

## Deployment

First you need to set-up Ozone: https://github.com/bluesky-social/ozone/blob/main/HOSTING.md

If you have a previous Ozone hosting, you must re-use the same signing key.

You can co-host this app on the same host,
the described host specs on the Ozone guide is more than enough.

(You can replace `docker` with `podman` for build and save steps.)  
After cloning this directory (can be on your local machine), run
```
docker build --tag bsky_politics_labeler .
docker save -o bsky_politics_labeler.docker.tar bsky_politics_labeler:latest
```
Then copy the exported image to the server:
```
scp -C bsky_politics_labeler.docker.tar  <your_server>:~/bsky_politics_labeler.docker.tar
```

On the server, load the image:
```
sudo docker load -i bsky_politics_labeler.docker.tar
```

Then first set-up the patterns.txt file.
The one on this repo is an example. 
Each line needs to be a valid regex (PCRE2).
`u` flag is added when matching.

Next is the secrets file.
Look at the `secret.example` file for the required values.
Save it as the file `bsky_politics_labeler_secret`.

Alternatively, you can use `podman secrets` to create a secret
and skip the upcoming `/run/secrets/` mount step.

Then create a docker network:
```sh
sudo docker network create bsky-pol-labeler-network
```

Start a Postgres container (don't forget to set a password):
```sh
sudo docker run --name bsky-pol-labeler-postgres \
  -e POSTGRES_PASSWORD=yourpostgrespassword \
  -e POSTGRES_DB=bsky_politics_labeler_repo \
  --network bsky-pol-labeler-network \
  -d docker.io/library/postgres
```

You may use the Postgres CLI argument `--synchronous_commit=off` to improve IO performance,
as the data written to disk is not critical.

Finally, start our app:
```sh
sudo docker run -e POSTGRES_HOST=bsky-pol-labeler-postgres \
  -e MIN_LIKES=10 \
  --network bsky-pol-labeler-network \
  -d --name bsky-politics-labeler \
  -v /your/dir/pattern/patterns.txt:/pattern/patterns.txt \
  -v /your/dir/secrets/bsky_politics_labeler_secret:/run/secrets/bsky_politics_labeler_secret \
  -e REGEX_FILE="/pattern/patterns.txt" \
  -p 127.0.0.1:4000:4000 \
  localhost/bsky_politics_labeler
```

* `POSTGRES_HOST` is the domain name of the postgres container
    within the network. No need to change it.
* `MIN_LIKES` **is the minimum like treshold** for the post to be
    analyzed. If not supplied, 50 by default.
* The first volume mount mounts the `patterns.txt` file.
* The second volume mount mounts the "secret" file.
* `REGEX_FILE` points to where we mounted the file.
* `-p 127.0.0.1:4000:4000` publishes the admin dashboard locally.
* `localhost/bsky_politics_labeler` is the image path.

You can look at config/runtime.exs for more configuration
options.

Logs can be viewed with
```sh
sudo docker logs bsky-politics-labeler --follow
```

### Admin dashboard (Phoenix LiveDashboard)
The admin dashboard is useful for development,
as well as to view the Postgres stats.

Since it uses basic auth. and doesn't have
https, it must not be used over the internet.
Instead, you can use ssh tunneling:
```sh
ssh -L 4000:localhost:4000 your_remote_server
```
While this is running, the admin dashboard will be available at
http://localhost:4000/admin/dashboard/

### Patterns file

The file can be edited, and the changes will be reloaded immediately.
Any invalid regex error will be logged as well.

# Copyright and License Notice

Copyright 2025, meozk

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program. If not, see <https://www.gnu.org/licenses/>. 
